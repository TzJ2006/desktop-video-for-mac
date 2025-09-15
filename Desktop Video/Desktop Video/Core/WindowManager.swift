import AppKit
import Combine

/// Centralises creation and lifetime management for wallpaper and menu bar overlay
/// controllers so that each physical screen owns at most one instance of either
/// window at any time.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var wallpaperControllers: [String: WallpaperWindowController] = [:]
    private var overlayControllers: [String: ForeignMenuBarMirrorController] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var notificationObservers: [NSObjectProtocol] = []

    private init() {
        observeScreenChanges()
        observeWorkspaceEvents()
        observeSettings()
    }

    deinit {
        for token in notificationObservers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func startForAllScreens() {
        dlog("WindowManager.startForAllScreens")
        syncScreens()
    }

    @discardableResult
    func ensureWallpaper(on screen: NSScreen) -> WallpaperWindowController {
        let sid = screen.dv_displayUUID
        if let existing = wallpaperControllers[sid] {
            existing.start(on: screen)
            return existing
        }
        let controller = SharedWallpaperWindowManager.shared.ensureWallpaperController(for: screen)
        wallpaperControllers[sid] = controller
        return controller
    }

    @discardableResult
    func ensureOverlay(on screen: NSScreen) -> ForeignMenuBarMirrorController? {
        guard Settings.shared.showInMenuBar else {
            removeOverlay(on: screen)
            return nil
        }
        let sid = screen.dv_displayUUID
        if let existing = overlayControllers[sid] {
            existing.refresh()
            return existing
        }
        guard let controller = SharedWallpaperWindowManager.shared.updateStatusBarVideo(for: screen) else {
            overlayControllers.removeValue(forKey: sid)
            return nil
        }
        overlayControllers[sid] = controller
        controller.refresh()
        return controller
    }

    func removeOverlay(on screen: NSScreen) {
        let sid = screen.dv_displayUUID
        SharedWallpaperWindowManager.shared.tearDownMenuBarMirror(for: screen)
        overlayControllers.removeValue(forKey: sid)
    }

    private func observeScreenChanges() {
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.syncScreens()
        }
        notificationObservers.append(token)
    }

    private func observeWorkspaceEvents() {
        let workspace = NSWorkspace.shared
        let nc = workspace.notificationCenter
        let spaceToken = nc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshVisibleOverlays()
        }
        notificationObservers.append(spaceToken)

        let activationToken = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshVisibleOverlays()
        }
        notificationObservers.append(activationToken)
    }

    private func observeSettings() {
        Settings.shared.$showInMenuBar
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    for screen in NSScreen.screens {
                        self.ensureOverlay(on: screen)
                    }
                } else {
                    for id in Array(self.overlayControllers.keys) {
                        SharedWallpaperWindowManager.shared.tearDownMenuBarMirror(forID: id)
                    }
                    self.overlayControllers.removeAll()
                }
            }
            .store(in: &cancellables)
    }

    private func syncScreens() {
        let screens = NSScreen.screens
        let activeIDs = Set(screens.map { $0.dv_displayUUID })

        for screen in screens {
            _ = ensureWallpaper(on: screen)
            if Settings.shared.showInMenuBar {
                _ = ensureOverlay(on: screen)
            } else {
                removeOverlay(on: screen)
            }
        }

        for id in Array(wallpaperControllers.keys) where !activeIDs.contains(id) {
            wallpaperControllers.removeValue(forKey: id)
        }

        for id in Array(overlayControllers.keys) where !activeIDs.contains(id) {
            SharedWallpaperWindowManager.shared.tearDownMenuBarMirror(forID: id)
            overlayControllers.removeValue(forKey: id)
        }
    }

    private func refreshVisibleOverlays() {
        guard Settings.shared.showInMenuBar else { return }
        for screen in NSScreen.screens {
            overlayControllers[screen.dv_displayUUID]?.refresh()
        }
    }
}

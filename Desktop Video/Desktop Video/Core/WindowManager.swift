import AppKit

/// Centralises creation and lifetime management for wallpaper controllers so
/// that each physical screen owns at most one instance at any time.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var wallpaperControllers: [String: WallpaperWindowController] = [:]
    private var notificationObservers: [NSObjectProtocol] = []

    private init() {
        observeScreenChanges()
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

    private func observeScreenChanges() {
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.syncScreens()
            }
        }
        notificationObservers.append(token)
    }

    private func syncScreens() {
        let screens = NSScreen.screens
        let activeIDs = Set(screens.map { $0.dv_displayUUID })

        for screen in screens {
            _ = ensureWallpaper(on: screen)
        }

        for id in Array(wallpaperControllers.keys) where !activeIDs.contains(id) {
            wallpaperControllers.removeValue(forKey: id)
        }
    }

}

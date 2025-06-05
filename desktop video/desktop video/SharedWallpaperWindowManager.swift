//
//  WallpaperWindow 2.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/25/25.
//

import Cocoa
import AVKit
import Foundation
import UniformTypeIdentifiers

class SharedWallpaperWindowManager {
    static let shared = SharedWallpaperWindowManager()
    
    private var debounceWorkItem: DispatchWorkItem?
    
    init() {
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(handleScreensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(handleScreensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func id(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.dv_displayID
    }

    @objc private func handleWake() {
        dlog("handling wake")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for (_, player) in self.players {
                if let currentItem = player.currentItem {
                    // 如果播放已经暂停但应该播放
                    if player.timeControlStatus != .playing {
                        player.seek(to: currentItem.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            player.play()
                        }
                    }
                }
            }
        }
    }

    @objc private func handleScreensDidWake() {
        dlog("screens did wake")
        handleWake()
        handleScreenChange()
    }

    @objc private func handleScreensDidSleep() {
        dlog("screens did sleep")
        for (_, player) in players {
            player.pause()
        }
    }
    
    func syncWindow(to screen: NSScreen, from source: NSScreen) {
        dlog("syncing window from \(source.dv_localizedName) to \(screen.dv_localizedName)")
        guard let destID = id(for: screen),
              let srcID = id(for: source),
              let entry = screenContent[srcID] else { return }
        
        // Get playback state info
        let currentVolume = players[srcID]?.volume ?? 1.0
        let isVideoStretch: Bool
        if let gravity = (currentViews[srcID] as? AVPlayerView)?.videoGravity {
            isVideoStretch = (gravity == .resizeAspectFill)
        } else {
            isVideoStretch = false
        }
        let isImageStretch = (currentViews[srcID] as? NSImageView)?.imageScaling == .scaleAxesIndependently
        let currentTime = players[srcID]?.currentItem?.currentTime()
        let shouldPlay = players[srcID]?.rate != 0
        
        // Clear existing content
        clear(for: screen)
        
        switch entry.type {
        case .image:
            showImage(for: screen, url: entry.url, stretch: isImageStretch)
        case .video:
            showVideo(for: screen, url: entry.url, stretch: isVideoStretch, volume: currentVolume) {
                if let time = currentTime {
                    self.players[destID]?.pause()
                    self.players[destID]?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        if shouldPlay {
                            self.players[destID]?.play()
                        }
                    }
                }
            }
        }
        
        // Update AppState.shared.lastMediaURL to the source entry’s original URL if not image
        if let sourceEntry = screenContent[srcID], sourceEntry.type != .image {
            AppState.shared.lastMediaURL = sourceEntry.url
        }
    }
    
    var selectedScreenIndex: Int {
        get { UserDefaults.standard.integer(forKey: "selectedScreenIndex") }
        set { UserDefaults.standard.set(newValue, forKey: "selectedScreenIndex") }
    }
    
    var selectedScreen: NSScreen? {
        let screens = NSScreen.screens
        guard selectedScreenIndex < screens.count else { return NSScreen.main }
        return screens[selectedScreenIndex]
    }
    
    /// Remember each screen's volume before a global mute is applied
    private var savedVolumes: [CGDirectDisplayID: Float] = [:]
    private var currentViews: [CGDirectDisplayID: NSView] = [:]
    private var loopers: [CGDirectDisplayID: AVPlayerLooper] = [:]
    var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    var players: [CGDirectDisplayID: AVQueuePlayer] = [:]
    var screenContent: [CGDirectDisplayID: (type: ContentType, url: URL, stretch: Bool, volume: Float?)] = [:]
    
    enum ContentType {
        case image
        case video
    }

    private func ensureWindow(for screen: NSScreen) {
        dlog("ensure window for \(screen.dv_localizedName)")
        guard let sid = id(for: screen) else { return }
        if windows[sid] != nil {
            windows[sid]?.orderFrontRegardless()
            return
        }
        
        let screenFrame = screen.frame
        let win = WallpaperWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.contentView = NSView(frame: screenFrame)
        win.orderFrontRegardless()
        
        self.windows[sid] = win
    }

    func showImage(for screen: NSScreen, url: URL, stretch: Bool) {
        dlog("show image \(url.lastPathComponent) on \(screen.dv_localizedName) stretch=\(stretch)")
        guard let sid = id(for: screen) else { return }
        ensureWindow(for: screen)
        stopVideoIfNeeded(for: screen)

        guard let image = NSImage(contentsOf: url),
              let contentView = windows[sid]?.contentView else { return }
        
        let imageView = NSImageView(frame: contentView.bounds)
        imageView.image = image
        imageView.imageScaling = stretch ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        
        self.screenContent[sid] = (.image, url, stretch, nil)
        saveBookmark(for: url, stretch: stretch, volume: nil, screen: screen)
        
        switchContent(to: imageView, for: screen)
        NotificationCenter.default.post(name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
    }
    
    /// Plays a video for the given screen, always using memory-cached video data.
    func showVideo(for screen: NSScreen, url: URL, stretch: Bool, volume: Float, onReady: (() -> Void)? = nil) {
        dlog("show video \(url.lastPathComponent) on \(screen.dv_localizedName) stretch=\(stretch) volume=\(volume)")
        do {
            let data = try Data(contentsOf: url)
            showVideoFromMemory(for: screen, data: data, stretch: stretch, volume: desktop_videoApp.shared!.globalMute ? 0.0 : volume, originalURL: url, onReady: onReady)
        } catch {
            errorLog("Cannot load from memory!")
        }
    }
    
    /// Mute every screen by re‑using the same logic as the per‑screen mute button.
    /// This saves each screen's last non‑zero volume before muting.
    func muteAllScreens() {
        dlog("mute all screens")
        // Save each screen's last non‑zero volume, then mute.
        for sid in screenContent.keys {
            let currentVol = screenContent[sid]?.volume ?? 0
            if currentVol > 0 { savedVolumes[sid] = currentVol }
            if let screen = NSScreen.screen(forDisplayID: sid) {
                setVolume(0, for: screen)
            }
        }
    }

    /// Restore every screen's volume to what it was before the last global mute.
    /// Screens that were already at 0 remain muted.
    func restoreAllScreens() {
        dlog("restore all screens")
        for sid in screenContent.keys {
            let newVol = savedVolumes[sid] ?? (screenContent[sid]?.volume ?? 0)
            if let screen = NSScreen.screen(forDisplayID: sid) {
                setVolume(newVol, for: screen)
            }
        }
        savedVolumes.removeAll()

        // Notify UI panels so sliders refresh
        NotificationCenter.default.post(
            name: Notification.Name("WallpaperContentDidChange"),
            object: nil
        )
    }

    func syncGlobalMuteToAllVolumes() {
        dlog("sync global mute to volumes")
        if desktop_videoApp.shared!.globalMute {
            muteAllScreens()
        } else {
            restoreAllScreens()
        }
    }
    
    func applyGlobalMuteIfNeeded() {
        dlog("apply global mute if needed: \(desktop_videoApp.shared!.globalMute)")
        if desktop_videoApp.shared!.globalMute {
            muteAllScreens()
        } else {
            restoreAllScreens()
        }
        NotificationCenter.default.post(
            name: Notification.Name("WallpaperContentDidChange"),
            object: nil
        )
    }
    
    // if update, the video is no longer showing from memory
    // actually, this is a weird problem that it will only occur when handeling large videos.
    func updateVideoSettings(for screen: NSScreen, stretch: Bool, volume: Float) {
        dlog("update video settings on \(screen.dv_localizedName) stretch=\(stretch) volume=\(volume)")
        guard let sid = id(for: screen) else { return }
        players[sid]?.volume = desktop_videoApp.shared!.globalMute ? 0.0 : volume
        if let playerView = currentViews[sid] as? AVPlayerView {
            playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
        }
        updateBookmark(stretch: stretch, volume: volume, screen: screen)
    }
    
    func updateImageStretch(for screen: NSScreen, stretch: Bool) {
        dlog("update image stretch on \(screen.dv_localizedName) stretch=\(stretch)")
        guard let sid = id(for: screen) else { return }
        if let imageView = currentViews[sid] as? NSImageView {
            imageView.imageScaling = stretch ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        }
    }
    
    func clear(for screen: NSScreen) {
        dlog("clear content for \(screen.dv_localizedName)")
        guard let sid = id(for: screen) else { return }
        stopVideoIfNeeded(for: screen)
        if let entry = screenContent[sid], entry.type == .video {
            players[sid]?.replaceCurrentItem(with: nil)
        }
        currentViews[sid]?.removeFromSuperview()
        currentViews.removeValue(forKey: sid)
        windows[sid]?.orderOut(nil)
        screenContent.removeValue(forKey: sid)
        windows.removeValue(forKey: sid)
        NotificationCenter.default.post(name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
        
        // 按照屏幕的 displayID 删除对应的 bookmark、stretch、volume 和 savedAt
        if let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
            UserDefaults.standard.removeObject(forKey: "bookmark-\(displayID)")
            UserDefaults.standard.removeObject(forKey: "stretch-\(displayID)")
            UserDefaults.standard.removeObject(forKey: "volume-\(displayID)")
            UserDefaults.standard.removeObject(forKey: "savedAt-\(displayID)")
        }
    }
    
    func restoreContent(for screen: NSScreen) {
        dlog("restore content for \(screen.dv_localizedName)")
        guard let sid = id(for: screen), let entry = screenContent[sid] else { return }
        switch entry.type {
        case .image:
            showImage(for: screen, url: entry.url, stretch: entry.stretch)
        case .video:
            showVideo(for: screen, url: entry.url, stretch: entry.stretch, volume: entry.volume ?? 1.0)
        }
    }

    private func stopVideoIfNeeded(for screen: NSScreen) {
        dlog("stop video if needed on \(screen.dv_localizedName)")
        guard let sid = id(for: screen) else { return }
        players[sid]?.pause()
        players[sid]?.replaceCurrentItem(with: nil)
        players.removeValue(forKey: sid)
        loopers.removeValue(forKey: sid)
    }

    private func switchContent(to newView: NSView, for screen: NSScreen) {
        dlog("switch content on \(screen.dv_localizedName)")
        guard let sid = id(for: screen), let contentView = windows[sid]?.contentView else { return }
        currentViews[sid]?.removeFromSuperview()
        contentView.addSubview(newView)
        currentViews[sid] = newView
    }
    
    func updateBookmark(stretch: Bool, volume: Float?, screen: NSScreen){
        dlog("update bookmark for \(screen.dv_localizedName) stretch=\(stretch) volume=\(String(describing: volume))")
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return }
        UserDefaults.standard.set(stretch, forKey: "stretch-\(displayID)")
        UserDefaults.standard.set(volume, forKey: "volume-\(displayID)")
    }
    
    private func saveBookmark(for url: URL, stretch: Bool, volume: Float?, screen: NSScreen) {
        dlog("save bookmark for \(screen.dv_localizedName) url=\(url.lastPathComponent) stretch=\(stretch) volume=\(String(describing: volume))")
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return }
        do {
            guard url.startAccessingSecurityScopedResource() else {
                errorLog("Failed to access security scoped resource for saving bookmark: \(url)")
                return
            }
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "bookmark-\(displayID)")
            UserDefaults.standard.set(stretch, forKey: "stretch-\(displayID)")
            UserDefaults.standard.set(volume, forKey: "volume-\(displayID)")
            // Save current timestamp
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "savedAt-\(displayID)")
            url.stopAccessingSecurityScopedResource()
        } catch {
            errorLog("Failed to save bookmark for \(url): \(error)")
        }
    }
    
    func restoreFromBookmark() {
        dlog("restore from bookmark")
        for screen in NSScreen.screens {
            guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            guard let bookmarkData = UserDefaults.standard.data(forKey: "bookmark-\(displayID)") else { continue }
            
            // Check saved time
            let savedAt = UserDefaults.standard.double(forKey: "savedAt-\(displayID)")
            if savedAt > 0, Date().timeIntervalSince1970 - savedAt > 86400 {
                // 超过 24 小时，删除记录
                UserDefaults.standard.removeObject(forKey: "bookmark-\(displayID)")
                UserDefaults.standard.removeObject(forKey: "stretch-\(displayID)")
                UserDefaults.standard.removeObject(forKey: "volume-\(displayID)")
                UserDefaults.standard.removeObject(forKey: "savedAt-\(displayID)")
                continue
            }
            
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                guard url.startAccessingSecurityScopedResource() else { continue }
                let ext = url.pathExtension.lowercased()
                let stretch = UserDefaults.standard.bool(forKey: "stretch-\(displayID)")
                let volume = UserDefaults.standard.object(forKey: "volume-\(displayID)") as? Float ?? 1.0
                
                if ["mp4", "mov", "m4v"].contains(ext) {
                    dlog("restoring video \(url.lastPathComponent) on \(screen.dv_localizedName)")
                    showVideo(for: screen, url: url, stretch: stretch, volume: volume)
                } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                    dlog("restoring image \(url.lastPathComponent) on \(screen.dv_localizedName)")
                    showImage(for: screen, url: url, stretch: stretch)
                }
            } catch {
                errorLog("Failed to restore bookmark for screen \(displayID): \(error)")
            }
        }
    }
    
    func setVolume(_ volume: Float, for screen: NSScreen) {
        dlog("set volume for \(screen.dv_localizedName) volume=\(volume)")
        guard let sid = id(for: screen) else { return }
        if let entry = screenContent[sid], entry.type == .video {
            // Any manual change to volume disables global mute
            if volume > 0 {
                desktop_videoApp.shared!.globalMute = false
            }

            // Apply to the player and persist
            updateVideoSettings(for: screen, stretch: entry.stretch, volume: volume)
            screenContent[sid] = (.video, entry.url, entry.stretch, volume)
        }

        // Notify all UI panels so their sliders/labels refresh immediately
        NotificationCenter.default.post(
            name: Notification.Name("WallpaperContentDidChange"),
            object: nil
        )
    }
    
    private func cleanupDisconnectedScreens() {
        dlog("cleanup disconnected screens")
        let activeIDs = Set(NSScreen.screens.compactMap { $0.dv_displayID })
        for sid in Array(windows.keys) {
            if !activeIDs.contains(sid) {
                let savedAt = UserDefaults.standard.double(forKey: "savedAt-\(sid)")
                if savedAt > 0, Date().timeIntervalSince1970 - savedAt > 86400 {
                    UserDefaults.standard.removeObject(forKey: "bookmark-\(sid)")
                    UserDefaults.standard.removeObject(forKey: "stretch-\(sid)")
                    UserDefaults.standard.removeObject(forKey: "volume-\(sid)")
                    UserDefaults.standard.removeObject(forKey: "savedAt-\(sid)")
                }
                if let screen = NSScreen.screen(forDisplayID: sid) {
                    clear(for: screen)
                } else {
                    // remove without screen object
                    players.removeValue(forKey: sid)
                    loopers.removeValue(forKey: sid)
                    currentViews.removeValue(forKey: sid)
                    windows.removeValue(forKey: sid)
                    screenContent.removeValue(forKey: sid)
                }
            }
        }
    }
    
    func syncAllWindows(sourceScreen: NSScreen) {
        dlog("sync all windows from \(sourceScreen.dv_localizedName)")
        cleanupDisconnectedScreens()
        guard let srcID = id(for: sourceScreen), let currentEntry = screenContent[srcID] else {
            return
        }

        let currentVolume = players[srcID]?.volume ?? 1.0
        let isVideoStretch: Bool
        if let gravity = (currentViews[srcID] as? AVPlayerView)?.videoGravity {
            isVideoStretch = (gravity == .resizeAspectFill)
        } else {
            isVideoStretch = false
        }
        let isImageStretch = (currentViews[srcID] as? NSImageView)?.imageScaling == .scaleAxesIndependently
        let currentTime = players[srcID]?.currentItem?.currentTime()
        
        for screen in NSScreen.screens {
            if screen == sourceScreen { continue }
            
            // Always clear content for this screen before setting new content
            self.clear(for: screen)
            
            if currentEntry.type == .video {
                let shouldPlay = players[srcID]?.rate != 0
                showVideo(for: screen, url: currentEntry.url, stretch: isVideoStretch, volume: currentVolume) {
                    if let time = currentTime, let destID = self.id(for: screen) {
                        self.players[destID]?.pause()
                        self.players[destID]?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            if shouldPlay {
                                self.players[destID]?.play()
                            }
                        }
                    }
                }
            } else if currentEntry.type == .image {
                showImage(for: screen, url: currentEntry.url, stretch: isImageStretch)
            }
        }
    }
    
    func selectAndImportVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.begin { result in
            if result == .OK, let url = panel.url {
                let stretch = UserDefaults.standard.bool(forKey: "lastUsedStretch")
                let volume = UserDefaults.standard.object(forKey: "lastUsedVolume") as? Float ?? 1.0
                if let screen = self.selectedScreen {
                    self.showVideo(for: screen, url: url, stretch: stretch, volume: volume)
                }
            }
        }
    }
    @objc private func handleScreenChange() {
        dlog("handle screen change")
        debounceWorkItem?.cancel()
        debounceWorkItem = DispatchWorkItem { [weak self] in
            self?.reloadScreens()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: debounceWorkItem!)
    }

    private func reloadScreens() {
        dlog("reload screens")
        let activeIDs = Set(NSScreen.screens.compactMap { $0.dv_displayID })
        let knownIDs = Set(windows.keys)

        // Remove windows for disconnected screens
        for sid in knownIDs.subtracting(activeIDs) {
            dlog("remove window for display \(sid)")
            if let screen = NSScreen.screen(forDisplayID: sid) {
                clear(for: screen)
            } else {
                players.removeValue(forKey: sid)
                loopers.removeValue(forKey: sid)
                currentViews.removeValue(forKey: sid)
                windows.removeValue(forKey: sid)
                screenContent.removeValue(forKey: sid)
            }
        }

        // Add windows for newly connected screens
        for screen in NSScreen.screens {
            guard let sid = screen.dv_displayID, !knownIDs.contains(sid) else { continue }
            dlog("add window for \(screen.dv_localizedName)")
            if let entry = screenContent[sid] {
                switch entry.type {
                case .image:
                    showImage(for: screen, url: entry.url, stretch: entry.stretch)
                case .video:
                    showVideo(for: screen, url: entry.url, stretch: entry.stretch, volume: entry.volume ?? 1.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let player = self.players[sid], player.timeControlStatus != .playing {
                            player.play()
                        }
                    }
                }
            }
        }
    }
    
    /// Plays a video from memory data by writing it to a temporary file and playing as usual.
    /// - Parameters:
    ///   - screen: The screen to display the video on.
    ///   - data: The video data.
    ///   - stretch: Whether to stretch the video.
    ///   - volume: The playback volume.
    ///   - originalURL: The original (user-chosen) video URL, to preserve user intent.
    ///   - onReady: Callback when ready.
    func showVideoFromMemory(for screen: NSScreen, data: Data, stretch: Bool, volume: Float, originalURL: URL? = nil, onReady: (() -> Void)? = nil) {
        dlog("show video from memory on \(screen.dv_localizedName) stretch=\(stretch) volume=\(volume)")
        guard let sid = id(for: screen) else { return }
        ensureWindow(for: screen)
        stopVideoIfNeeded(for: screen)
        guard let contentView = windows[sid]?.contentView else { return }
        
        // Write data to a temporary file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mov")
        do {
            try data.write(to: tempURL)
        } catch {
            errorLog("Failed to write video data to temp file: \(error)")
            return
        }
        
        let item = AVPlayerItem(url: tempURL)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        
        queuePlayer.volume = volume
        
        let playerView = AVPlayerView(frame: contentView.bounds)
        playerView.player = queuePlayer
        playerView.controlsStyle = .none
        playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
        playerView.autoresizingMask = [.width, .height]
        
        players[sid] = queuePlayer
        loopers[sid] = looper
        // Track the original source URL, not the temp path, to preserve user intent.
        screenContent[sid] = (.video, originalURL ?? tempURL, stretch, volume)
        
        if let sourceURL = originalURL {
            saveBookmark(for: sourceURL, stretch: stretch, volume: volume, screen: screen)
        }
        
        switchContent(to: playerView, for: screen)
        NotificationCenter.default.post(name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            queuePlayer.play()
            onReady?()
        }
    }
}


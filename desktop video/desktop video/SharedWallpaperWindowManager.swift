// Debug log function: Only prints in DEBUG builds
func dlog(_ message: String) {
#if DEBUG
    print(message)
#endif
}
/// Synchronize the wallpaper content from a source screen to a target screen.

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
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func handleWake() {
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
    
    func syncWindow(to screen: NSScreen, from source: NSScreen) {
        guard let entry = screenContent[source] else { return }
        
        // Get playback state info
        let currentVolume = players[source]?.volume ?? 1.0
        let isVideoStretch: Bool
        if let gravity = (currentViews[source] as? AVPlayerView)?.videoGravity {
            isVideoStretch = (gravity == .resizeAspectFill)
        } else {
            isVideoStretch = false
        }
        let isImageStretch = (currentViews[source] as? NSImageView)?.imageScaling == .scaleAxesIndependently
        let currentTime = players[source]?.currentItem?.currentTime()
        let shouldPlay = players[source]?.rate != 0
        
        // Clear existing content
        clear(for: screen)
        
        switch entry.type {
        case .image:
            showImage(for: screen, url: entry.url, stretch: isImageStretch)
        case .video:
            showVideo(for: screen, url: entry.url, stretch: isVideoStretch, volume: currentVolume) {
                if let time = currentTime {
                    self.players[screen]?.pause()
                    self.players[screen]?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        if shouldPlay {
                            self.players[screen]?.play()
                        }
                    }
                }
            }
        }
        
        // Update AppState.shared.lastMediaURL to the source entry’s original URL if not image
        if let sourceEntry = screenContent[source], sourceEntry.type != .image {
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
    private var savedVolumes: [NSScreen: Float] = [:]
    private var currentViews: [NSScreen: NSView] = [:]
    private var loopers: [NSScreen: AVPlayerLooper] = [:]
    var windows: [NSScreen: WallpaperWindow] = [:]
    var players: [NSScreen: AVQueuePlayer] = [:]
    var screenContent: [NSScreen: (type: ContentType, url: URL, stretch: Bool, volume: Float?)] = [:]
    
    enum ContentType {
        case image
        case video
    }
    
    private func ensureWindow(for screen: NSScreen) {
        if windows[screen] != nil {
            windows[screen]?.orderFrontRegardless()
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
        
        self.windows[screen] = win
    }
    
    func showImage(for screen: NSScreen, url: URL, stretch: Bool) {
        ensureWindow(for: screen)
        stopVideoIfNeeded(for: screen)
        
        guard let image = NSImage(contentsOf: url),
              let contentView = windows[screen]?.contentView else { return }
        
        let imageView = NSImageView(frame: contentView.bounds)
        imageView.image = image
        imageView.imageScaling = stretch ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        
        self.screenContent[screen] = (.image, url, stretch, nil)
        saveBookmark(for: url, stretch: stretch, volume: nil, screen: screen)
        
        switchContent(to: imageView, for: screen)
        NotificationCenter.default.post(name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
    }
    
    /// Plays a video for the given screen, always using memory-cached video data.
    func showVideo(for screen: NSScreen, url: URL, stretch: Bool, volume: Float, onReady: (() -> Void)? = nil) {
        do {
            let data = try Data(contentsOf: url)
            showVideoFromMemory(for: screen, data: data, stretch: stretch, volume: desktop_videoApp.shared!.globalMute ? 0.0 : volume, originalURL: url, onReady: onReady)
        } catch {
            print("Cannot load from memory!")
        }
    }
    
    /// Mute every screen by re‑using the same logic as the per‑screen mute button.
    /// This saves each screen's last non‑zero volume before muting.
    func muteAllScreens() {
        // Save each screen's last non‑zero volume, then mute.
        for screen in screenContent.keys {
            let currentVol = screenContent[screen]?.volume ?? 0
            if currentVol > 0 { savedVolumes[screen] = currentVol }
            setVolume(0, for: screen)
        }
    }

    /// Restore every screen's volume to what it was before the last global mute.
    /// Screens that were already at 0 remain muted.
    func restoreAllScreens() {
        for screen in screenContent.keys {
            let newVol = savedVolumes[screen] ?? (screenContent[screen]?.volume ?? 0)
            setVolume(newVol, for: screen)
        }
        savedVolumes.removeAll()

        // Notify UI panels so sliders refresh
        NotificationCenter.default.post(
            name: Notification.Name("WallpaperContentDidChange"),
            object: nil
        )
    }

    func syncGlobalMuteToAllVolumes() {
        if desktop_videoApp.shared!.globalMute {
            muteAllScreens()
        } else {
            restoreAllScreens()
        }
    }
    
    func applyGlobalMuteIfNeeded() {
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
        players[screen]?.volume = desktop_videoApp.shared!.globalMute ? 0.0 : volume
        print(players[screen]!.volume)
        if let playerView = currentViews[screen] as? AVPlayerView {
            playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
        }
        updateBookmark(stretch: stretch, volume: volume, screen: screen)
    }
    
    func updateImageStretch(for screen: NSScreen, stretch: Bool) {
        if let imageView = currentViews[screen] as? NSImageView {
            imageView.imageScaling = stretch ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        }
    }
    
    func clear(for screen: NSScreen) {
        stopVideoIfNeeded(for: screen)
        if let entry = screenContent[screen], entry.type == .video {
            players[screen]?.replaceCurrentItem(with: nil)
        }
        currentViews[screen]?.removeFromSuperview()
        currentViews.removeValue(forKey: screen)
        windows[screen]?.orderOut(nil)
        screenContent.removeValue(forKey: screen)
        windows.removeValue(forKey: screen)
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
        guard let entry = screenContent[screen] else { return }
        switch entry.type {
        case .image:
            showImage(for: screen, url: entry.url, stretch: entry.stretch)
        case .video:
            showVideo(for: screen, url: entry.url, stretch: entry.stretch, volume: entry.volume ?? 1.0)
        }
    }
    
    private func stopVideoIfNeeded(for screen: NSScreen) {
        players[screen]?.pause()
        players[screen]?.replaceCurrentItem(with: nil)
        players.removeValue(forKey: screen)
        loopers.removeValue(forKey: screen)
    }
    
    private func switchContent(to newView: NSView, for screen: NSScreen) {
        guard let contentView = windows[screen]?.contentView else { return }
        currentViews[screen]?.removeFromSuperview()
        contentView.addSubview(newView)
        currentViews[screen] = newView
    }
    
    func updateBookmark(stretch: Bool, volume: Float?, screen: NSScreen){
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return }
        UserDefaults.standard.set(stretch, forKey: "stretch-\(displayID)")
        UserDefaults.standard.set(volume, forKey: "volume-\(displayID)")
    }
    
    private func saveBookmark(for url: URL, stretch: Bool, volume: Float?, screen: NSScreen) {
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return }
        do {
            guard url.startAccessingSecurityScopedResource() else {
                dlog("Failed to access security scoped resource for saving bookmark: \(url)")
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
            dlog("Failed to save bookmark for \(url): \(error)")
        }
    }
    
    func restoreFromBookmark() {
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
                    showVideo(for: screen, url: url, stretch: stretch, volume: volume)
                } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                    showImage(for: screen, url: url, stretch: stretch)
                }
            } catch {
                dlog("Failed to restore bookmark for screen \(displayID): \(error)")
            }
        }
    }
    
    func setVolume(_ volume: Float, for screen: NSScreen) {
        if let entry = screenContent[screen], entry.type == .video {
            // Any manual change to volume disables global mute
            if volume > 0 {
                desktop_videoApp.shared!.globalMute = false
            }

            // Apply to the player and persist
            updateVideoSettings(for: screen, stretch: entry.stretch, volume: volume)
            screenContent[screen] = (.video, entry.url, entry.stretch, volume)
        }

        // Notify all UI panels so their sliders/labels refresh immediately
        NotificationCenter.default.post(
            name: Notification.Name("WallpaperContentDidChange"),
            object: nil
        )
    }
    
    private func cleanupDisconnectedScreens() {
        let activeScreens = Set(NSScreen.screens)
        for screen in Array(windows.keys) {
            if !activeScreens.contains(screen) {
                // Check if over 24 hours, then remove bookmark and related data
                if let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
                    let savedAt = UserDefaults.standard.double(forKey: "savedAt-\(displayID)")
                    if savedAt > 0, Date().timeIntervalSince1970 - savedAt > 86400 {
                        UserDefaults.standard.removeObject(forKey: "bookmark-\(displayID)")
                        UserDefaults.standard.removeObject(forKey: "stretch-\(displayID)")
                        UserDefaults.standard.removeObject(forKey: "volume-\(displayID)")
                        UserDefaults.standard.removeObject(forKey: "savedAt-\(displayID)")
                    }
                }
                clear(for: screen)
            }
        }
    }
    
    func syncAllWindows(sourceScreen: NSScreen) {
        cleanupDisconnectedScreens()
        guard let currentEntry = screenContent[sourceScreen] else {
            return
        }
        
        let currentVolume = players[sourceScreen]?.volume ?? 1.0
        let isVideoStretch: Bool
        if let gravity = (currentViews[sourceScreen] as? AVPlayerView)?.videoGravity {
            isVideoStretch = (gravity == .resizeAspectFill)
        } else {
            isVideoStretch = false
        }
        let isImageStretch = (currentViews[sourceScreen] as? NSImageView)?.imageScaling == .scaleAxesIndependently
        let currentTime = players[sourceScreen]?.currentItem?.currentTime()
        
        for screen in NSScreen.screens {
            if screen == sourceScreen { continue }
            
            // Always clear content for this screen before setting new content
            self.clear(for: screen)
            
            if currentEntry.type == .video {
                let shouldPlay = players[sourceScreen]?.rate != 0
                showVideo(for: screen, url: currentEntry.url, stretch: isVideoStretch, volume: currentVolume) {
                    if let time = currentTime {
                        self.players[screen]?.pause()
                        self.players[screen]?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            if shouldPlay {
                                self.players[screen]?.play()
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
        debounceWorkItem?.cancel()
        debounceWorkItem = DispatchWorkItem { [weak self] in
            self?.reloadScreens()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: debounceWorkItem!)
    }
    
    private func reloadScreens() {
        let activeScreens = Set(NSScreen.screens)
        let knownScreens = Set(windows.keys)
        
        // Remove windows for disconnected screens
        for screen in knownScreens.subtracting(activeScreens) {
            clear(for: screen)
        }
        
        // Add windows for newly connected screens
        for screen in activeScreens.subtracting(knownScreens) {
            if let entry = screenContent[screen] {
                switch entry.type {
                case .image:
                    showImage(for: screen, url: entry.url, stretch: entry.stretch)
                case .video:
                    showVideo(for: screen, url: entry.url, stretch: entry.stretch, volume: entry.volume ?? 1.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let player = self.players[screen], player.timeControlStatus != .playing {
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
        ensureWindow(for: screen)
        stopVideoIfNeeded(for: screen)
        guard let contentView = windows[screen]?.contentView else { return }
        
        // Write data to a temporary file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mov")
        do {
            try data.write(to: tempURL)
        } catch {
            dlog("Failed to write video data to temp file: \(error)")
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
        
        players[screen] = queuePlayer
        loopers[screen] = looper
        // Track the original source URL, not the temp path, to preserve user intent.
        screenContent[screen] = (.video, originalURL ?? tempURL, stretch, volume)
        
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


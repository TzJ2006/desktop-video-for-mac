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
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func handleScreenChange() {
        for (_, player) in players {
            if player.timeControlStatus != .playing {
                print("📺 屏幕配置变更后恢复播放")
                player.play()
            }
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

    private var windows: [NSScreen: WallpaperWindow] = [:]
    private var currentViews: [NSScreen: NSView] = [:]
    var players: [NSScreen: AVQueuePlayer] = [:]
    private var loopers: [NSScreen: AVPlayerLooper] = [:]
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
        saveBookmark(for: url, stretch: stretch, volume: nil)

        switchContent(to: imageView, for: screen)
        NotificationCenter.default.post(name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
    }

    func showVideo(for screen: NSScreen, url: URL, stretch: Bool, volume: Float) {
        ensureWindow(for: screen)
        stopVideoIfNeeded(for: screen)

        guard let contentView = windows[screen]?.contentView else { return }

        let queuePlayer = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.volume = volume
        // queuePlayer.play()  // Removed playback start here

        let playerView = AVPlayerView(frame: contentView.bounds)
        playerView.player = queuePlayer
        playerView.controlsStyle = .none
        playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
        playerView.autoresizingMask = [.width, .height]

        players[screen] = queuePlayer
        loopers[screen] = looper

        self.screenContent[screen] = (.video, url, stretch, queuePlayer.volume)
        saveBookmark(for: url, stretch: stretch, volume: volume)

        switchContent(to: playerView, for: screen)
        NotificationCenter.default.post(name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
    }

    func updateVideoSettings(for screen: NSScreen, stretch: Bool, volume: Float) {
        players[screen]?.volume = volume
        if let playerView = currentViews[screen] as? AVPlayerView {
            playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
        }
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

    private func saveBookmark(for url: URL, stretch: Bool, volume: Float?) {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Failed to access security scoped resource for saving bookmark")
                return
            }

            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "lastUsedBookmark")
            UserDefaults.standard.set(stretch, forKey: "lastUsedStretch")
            if let volume = volume {
                UserDefaults.standard.set(volume, forKey: "lastUsedVolume")
            }

            url.stopAccessingSecurityScopedResource()
        } catch {
            print("❌ Failed to save bookmark: \(error)")
        }
    }

    func restoreFromBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "lastUsedBookmark") else { return }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                print("⚠️ Bookmark is stale, consider refreshing it.")
            }
            guard url.startAccessingSecurityScopedResource() else { return }
            let ext = url.pathExtension.lowercased()
            let stretch = UserDefaults.standard.bool(forKey: "lastUsedStretch")
            let volume = UserDefaults.standard.object(forKey: "lastUsedVolume") as? Float ?? 1.0
            if ["mp4", "mov", "m4v"].contains(ext) {
                if let screen = selectedScreen {
                    showVideo(for: screen, url: url, stretch: stretch, volume: volume)
                }
            } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                if let screen = selectedScreen {
                    showImage(for: screen, url: url, stretch: stretch)
                }
            }
        } catch {
            print("❌ Failed to restore from bookmark: \(error)")
        }
    }

//    func syncAutoFillToAllControllers() {
//        for (screen, entry) in screenContent {
//            switch entry.type {
//            case .image:
//                updateImageStretch(for: screen, stretch: AppDelegate.shared.autoFill)
//            case .video:
//                updateVideoSettings(for: screen, stretch: AppDelegate.shared.autoFill, volume: entry.volume ?? 1.0)
//            }
//        }
//    }

    func syncGlobalMuteToAllVolumes() {
        guard AppDelegate.shared.globalMute else { return }
        for (screen, entry) in screenContent {
            if entry.type == .video {
                updateVideoSettings(for: screen, stretch: entry.stretch, volume: 0.0)
                screenContent[screen] = (.video, entry.url, entry.stretch, 0.0)
            }
        }
    }

    func setVolume(_ volume: Float, for screen: NSScreen) {
        if volume > 0 {
            AppDelegate.shared.globalMute = false
        }
        if let entry = screenContent[screen], entry.type == .video {
            updateVideoSettings(for: screen, stretch: entry.stretch, volume: volume)
            screenContent[screen] = (.video, entry.url, entry.stretch, volume)
        }
    }
    
    // Old syncAllWindows() is replaced by syncAllWindows(sourceScreen:)
    /*
    func syncAllWindows() {
        // Deprecated: Use syncAllWindows(sourceScreen:) instead
    }
    */

    func syncAllWindows(sourceScreen: NSScreen) {
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

            if currentEntry.type == .video {
                showVideo(for: screen, url: currentEntry.url, stretch: isVideoStretch, volume: currentVolume)
                if let time = currentTime {
                    players[screen]?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [self] _ in
                        if players[sourceScreen]?.rate != 0 {
                            players[screen]?.play()
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
}

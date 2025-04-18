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

    private var windows: [NSScreen: WallpaperWindow] = [:]
    private var currentView: NSView?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var screenContent: [NSScreen: (type: ContentType, url: URL, stretch: Bool, volume: Float?)] = [:]

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

    func showImage(url: URL, stretch: Bool) {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSApp.mainWindow?.frame.origin ?? .zero)
        }) ?? NSScreen.main else { return }
        ensureWindow(for: screen)
        stopVideoIfNeeded()

        guard let image = NSImage(contentsOf: url),
              let contentView = windows[screen]?.contentView else { return }

        let imageView = NSImageView(frame: contentView.bounds)
        imageView.image = image
        imageView.imageScaling = stretch ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]

        self.screenContent[screen] = (.image, url, stretch, nil)
        saveBookmark(for: url, stretch: stretch, volume: nil)

        switchContent(to: imageView)
    }

    func showVideo(url: URL, stretch: Bool, volume: Float) {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSApp.mainWindow?.frame.origin ?? .zero)
        }) ?? NSScreen.main else { return }
        ensureWindow(for: screen)
        stopVideoIfNeeded()

        guard let contentView = windows[screen]?.contentView else { return }

        let queuePlayer = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
//        queuePlayer.replaceCurrentItem(with: item)
//        NotificationCenter.default.addObserver(
//            forName: .AVPlayerItemDidPlayToEndTime,
//            object: item,
//            queue: .main
//        ) { _ in
//            queuePlayer.seek(to: .zero)
//            queuePlayer.play()
//        }
        queuePlayer.volume = volume
        queuePlayer.play()

        let playerView = AVPlayerView(frame: contentView.bounds)
        playerView.player = queuePlayer
        playerView.controlsStyle = .none
        playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
        playerView.autoresizingMask = [.width, .height]

        self.player = queuePlayer
        self.looper = looper

        self.screenContent[screen] = (.video, url, stretch, volume)
        saveBookmark(for: url, stretch: stretch, volume: volume)

        switchContent(to: playerView)
    }

    func updateVideoSettings(stretch: Bool, volume: Float) {
        self.player?.volume = volume
        if let playerView = currentView as? AVPlayerView {
            playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
        }
    }

    func updateImageStretch(stretch: Bool) {
        if let imageView = currentView as? NSImageView {
            imageView.imageScaling = stretch ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        }
    }

    func clear() {
        if let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSApp.mainWindow?.frame.origin ?? .zero)
        }), let win = windows[screen] {
            stopVideoIfNeeded()
            currentView?.removeFromSuperview()
            currentView = nil
            win.orderOut(nil)
            windows.removeValue(forKey: screen)
        }
    }

    func restoreContent(for screen: NSScreen) {
        guard let entry = screenContent[screen] else { return }
        switch entry.type {
        case .image:
            showImage(url: entry.url, stretch: entry.stretch)
        case .video:
            showVideo(url: entry.url, stretch: entry.stretch, volume: entry.volume ?? 1.0)
        }
    }

    private func stopVideoIfNeeded() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        looper = nil
    }

    private func switchContent(to newView: NSView) {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSApp.mainWindow?.frame.origin ?? .zero)
        }) ?? NSScreen.main,
              let contentView = windows[screen]?.contentView else { return }
        currentView?.removeFromSuperview()
        contentView.addSubview(newView)
        currentView = newView
    }

    private func saveBookmark(for url: URL, stretch: Bool, volume: Float?) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "lastUsedBookmark")
            UserDefaults.standard.set(stretch, forKey: "lastUsedStretch")
            if let volume = volume {
                UserDefaults.standard.set(volume, forKey: "lastUsedVolume")
            }
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
                showVideo(url: url, stretch: stretch, volume: volume)
            } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                showImage(url: url, stretch: stretch)
            }
        } catch {
            print("❌ Failed to restore from bookmark: \(error)")
        }
    }
}

//
//  WallpaperWindow 2.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/25/25.
//


import Cocoa
import AVKit

class SharedWallpaperWindowManager {
    static let shared = SharedWallpaperWindowManager()

    private var window: WallpaperWindow?
    private var currentView: NSView?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    private func ensureWindow() {
        guard window == nil else { return }
        guard let screen = NSScreen.main else { return }

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

        self.window = win
    }

    func showImage(url: URL, stretch: Bool) {
        ensureWindow()
        stopVideoIfNeeded()

        guard let image = NSImage(contentsOf: url),
              let contentView = window?.contentView else { return }

        let imageView = NSImageView(frame: contentView.bounds)
        imageView.image = image
        imageView.imageScaling = stretch ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]

        switchContent(to: imageView)
    }

    func showVideo(url: URL, stretch: Bool, volume: Float) {
        ensureWindow()
        stopVideoIfNeeded()

        guard let contentView = window?.contentView else { return }

        let queuePlayer = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.volume = volume
        queuePlayer.play()

        let playerView = AVPlayerView(frame: contentView.bounds)
        playerView.player = queuePlayer
        playerView.controlsStyle = .none
        playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
        playerView.autoresizingMask = [.width, .height]

        self.player = queuePlayer
        self.looper = looper

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
        stopVideoIfNeeded()
        currentView?.removeFromSuperview()
        currentView = nil
        window?.orderOut(nil)
    }

    private func stopVideoIfNeeded() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        looper = nil
    }

    private func switchContent(to newView: NSView) {
        guard let contentView = window?.contentView else { return }
        currentView?.removeFromSuperview()
        contentView.addSubview(newView)
        currentView = newView
    }
}

//
//  VideoWallpaperManager.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/20/25.
//

import Cocoa
import AVKit
import CoreGraphics

class VideoWallpaperManager {
    static let shared = VideoWallpaperManager()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoWindow: NSWindow?

    func setVideoWallpaper(url: URL, stretchToFill: Bool) {
            guard let screen = NSScreen.main else { return }
            let screenFrame = screen.frame

            // Create a borderless window
            let window = NSWindow(
                contentRect: screenFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.ignoresMouseEvents = true  // Allows interaction with desktop icons
            window.makeKeyAndOrderFront(nil)

            // Setup AVQueuePlayer and looping
            let queuePlayer = AVQueuePlayer()
            let playerItem = AVPlayerItem(url: url)
            self.looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            queuePlayer.play()

            // Video Player View
            let playerView = AVPlayerView(frame: screenFrame)
            playerView.player = queuePlayer
            playerView.controlsStyle = .none

            // Adjust aspect ratio based on toggle state
            if stretchToFill {
                playerView.videoGravity = .resizeAspectFill  // Stretch to fill screen
            } else {
                playerView.videoGravity = .resizeAspect  // Keep original aspect ratio
            }

            window.contentView = playerView
            self.videoWindow = window
            self.player = queuePlayer
        }
}

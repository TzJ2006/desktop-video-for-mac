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

//    func setVideoWallpaper(url: URL, stretchToFill: Bool) {
////            self.videoWindow = nil
//            guard let screen = NSScreen.main else { return }
//            let screenFrame = screen.frame
//
//            // Create a borderless window
//            let window = NSWindow(
//                contentRect: screenFrame,
//                styleMask: .borderless,
//                backing: .buffered,
//                defer: false
//            )
//        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
//            window.isOpaque = false
//            window.backgroundColor = .clear
//            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
//            window.ignoresMouseEvents = true  // Allows interaction with desktop icons
//            window.makeKeyAndOrderFront(nil)
//
//            // Setup AVQueuePlayer and looping
//            let queuePlayer = AVQueuePlayer()
//            let playerItem = AVPlayerItem(url: url)
//            self.looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
//            queuePlayer.play()
//
//            // Video Player View
//            let playerView = AVPlayerView(frame: screenFrame)
//            playerView.player = queuePlayer
//            playerView.controlsStyle = .none
//
//            // Adjust aspect ratio based on toggle state
//            if stretchToFill {
//                playerView.videoGravity = .resizeAspectFill  // Stretch to fill screen
//            } else {
//                playerView.videoGravity = .resizeAspect  // Keep original aspect ratio
//            }
//
//            window.contentView = playerView
//            self.videoWindow = window
//            self.player = queuePlayer
//        }
    
    func setVideoWallpaper(url: URL, stretchToFill: Bool) {
        DispatchQueue.main.async {
            // 先关闭之前的视频窗口（如有）
//            self.stopVideoWallpaper()

            guard let screen = NSScreen.main else { return }
            let screenFrame = screen.frame

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
            window.ignoresMouseEvents = true
            window.makeKeyAndOrderFront(nil)

            // 播放器
            let queuePlayer = AVQueuePlayer()
            let playerItem = AVPlayerItem(url: url)
            self.looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            queuePlayer.play()

            let playerView = AVPlayerView(frame: screenFrame)
            playerView.player = queuePlayer
            playerView.controlsStyle = .none
            playerView.videoGravity = stretchToFill ? .resizeAspectFill : .resizeAspect

            window.contentView = playerView

            self.videoWindow = window
            self.player = queuePlayer
        }
    }
    
    func stopVideoWallpaper() {
        DispatchQueue.main.async {
            guard let window = self.videoWindow else { return }

            // 尝试访问一个 property 来探测是否已被销毁
            if window.responds(to: #selector(NSWindow.orderOut(_:))) == false {
                print("⚠️ Window 已被销毁或失效，跳过关闭")
                self.videoWindow = nil
                self.player = nil
                self.looper = nil
                return
            }

            self.videoWindow = nil
            self.player?.pause()
            self.player?.replaceCurrentItem(with: nil)
            self.player = nil
            self.looper = nil

            window.orderOut(nil)
            window.contentView = nil
//            window.close()
        }
    }

    func setVolume(_ value: Float) {
        DispatchQueue.main.async {
            self.player?.volume = value
        }
    }
}

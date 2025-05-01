//
//  WallpaperWindow.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/25/25.
//


import Cocoa
import AVFoundation  // Add this import for AVPlayer

class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var playerLayer: AVPlayerLayer?

    func setVideoPlayer(_ player: AVPlayer) {
        // Remove existing player layer if any
        playerLayer?.removeFromSuperlayer()

        // Create and configure the new player layer
        let layer = AVPlayerLayer(player: player)
        layer.frame = contentView?.bounds ?? .zero
        layer.videoGravity = .resizeAspectFill
        contentView?.wantsLayer = true
        contentView?.layer?.addSublayer(layer)

        self.playerLayer = layer

        // Observe frame changes to update layer size
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            self?.playerLayer?.frame = self?.contentView?.bounds ?? .zero
        }
    }
}

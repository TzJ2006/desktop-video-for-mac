//
//  WallpaperWindow.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/25/25.
//

import Cocoa
import AVFoundation  // 引入 AVPlayer 所需框架

@MainActor
final class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var playerLayer: AVPlayerLayer?
    private var resizeObserver: NSObjectProtocol?

    func setVideoPlayer(_ player: AVPlayer) {
        // 如已有图层先移除
        playerLayer?.removeFromSuperlayer()
        if let token = resizeObserver {
            NotificationCenter.default.removeObserver(token)
        }

        // 创建并配置新的播放图层
        let layer = AVPlayerLayer(player: player)
        layer.frame = contentView?.bounds ?? .zero
        layer.videoGravity = .resizeAspectFill
        contentView?.wantsLayer = true
        contentView?.layer?.addSublayer(layer)

        self.playerLayer = layer

        // 监听窗口尺寸变化以调整图层大小
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playerLayer?.frame = self?.contentView?.bounds ?? .zero
            }
        }
    }

    deinit {
        if let token = resizeObserver {
            NotificationCenter.default.removeObserver(token)
        }
        assertMainThread()
    }
}

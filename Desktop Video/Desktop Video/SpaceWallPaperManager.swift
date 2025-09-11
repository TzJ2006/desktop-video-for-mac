//
//  SpaceWallPaperManager.swift
//  Desktop Video
//
//  Created by 汤子嘉 on 6/19/25.
//

import Cocoa
import AVFoundation
import AVKit
import UniformTypeIdentifiers

// Private CoreGraphics symbol to obtain the current connection ID
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> UInt32

// MARK: - Helper: (半)私有 API—用 dlopen/dlsym 动态拿
private typealias CGSCopyManagedDisplaySpacesFunc = @convention(c) (UInt32) -> CFArray?
private typealias CGSAddWindowsToSpacesFunc = @convention(c)
        (UInt32, CFArray, CFArray) -> Void

let conn = _CGSDefaultConnection()   // = UInt32

private let CGSCopyManagedDisplaySpaces: CGSCopyManagedDisplaySpacesFunc = {
    let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    let sym = dlsym(handle, "CGSCopyManagedDisplaySpaces")
    return unsafeBitCast(sym, to: CGSCopyManagedDisplaySpacesFunc.self)
}()

private let CGSAddWindowsToSpaces: CGSAddWindowsToSpacesFunc = {
    let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    let sym = dlsym(handle, "CGSAddWindowsToSpaces")
    return unsafeBitCast(sym, to: CGSAddWindowsToSpacesFunc.self)
}()

// MARK: - Main manager
final class SpaceWallpaperManager {
    static let shared = SpaceWallpaperManager()
    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        refreshSpacesAndEnsureWindows()
    }

    // spaceID → wallpaper window
    private var windows: [UInt64: NSWindow] = [:]
    private var players: [UInt64: AVPlayer] = [:]

    /// 刷新全部 Space 列表，并为每个 Space 确保有窗口
    func refreshSpacesAndEnsureWindows() {
        guard
          let arr = CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]]
        else { return }

        for displayDict in arr {
            guard let spaces = displayDict["Spaces"] as? [[String: Any]] else { continue }
            for sp in spaces {
                guard let sid = sp["id64"] as? UInt64 else { continue }
                if windows[sid] == nil {
                    let w = buildWallpaperWindow()
                    windows[sid] = w
                    players[sid] = attachPlayer(to: w, url: pickMedia(for: sid))
                    // 将窗口显式放入该 Space
                    let winID = NSNumber(value: w.windowNumber)
                    let spaceArray = [NSNumber(value: sid)]
                    CGSAddWindowsToSpaces(conn, [winID] as CFArray, spaceArray as CFArray)
                    w.orderFrontRegardless()
                }
            }
        }
    }

    @objc private func activeSpaceChanged() {
        // 可按需在这里暂停上一个 Space、恢复当前 Space
        refreshSpacesAndEnsureWindows()
    }

    // --- helpers ----------
    private func buildWallpaperWindow() -> NSWindow {
        let screenFrame = NSScreen.main!.frame
        let w = NSWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: NSScreen.main
        )
        w.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        w.collectionBehavior = [.stationary]
        w.ignoresMouseEvents = true
        w.backgroundColor = .clear
        return w
    }

    /// Attach a video player that loads data entirely into memory before playback.
    private func attachPlayer(to win: NSWindow, url: URL) -> AVPlayer {
        dlog("attachPlayer use memory-mapped video \(url.lastPathComponent)")
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let contentType = UTType(filenameExtension: url.pathExtension) ?? .video
            let asset = AVDataAsset(data: data, contentType: contentType)
            let item = AVPlayerItem(asset: asset)
            let player = AVQueuePlayer(playerItem: item)
            _ = AVPlayerLooper(player: player, templateItem: item)
            let playerView = AVPlayerView(frame: win.contentView!.bounds)
            playerView.player = player
            playerView.controlsStyle = .none
            playerView.autoresizingMask = [.width, .height]
            win.contentView?.addSubview(playerView)
            player.play()
            return player
        } catch {
            errorLog("Failed to load video data: \(error)")
            return AVPlayer()
        }
    }

    private func pickMedia(for spaceID: UInt64) -> URL {
        // ⬅️ Demo：简写为随机选；可换成用户设置
        let all = Bundle.main.urls(forResourcesWithExtension: "mov", subdirectory: nil)!
        return all.randomElement()!
    }
}

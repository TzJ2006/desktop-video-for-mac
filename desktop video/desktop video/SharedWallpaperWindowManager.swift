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

        // 获取当前播放状态
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

        // 先清理目标屏幕内容
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

        // 若源条目是视频，则更新 AppState 中记录的地址
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

    /// 全局静音前记录各屏幕的音量
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

    /// 为指定屏幕播放视频，始终从内存缓存读取数据。
    func showVideo(for screen: NSScreen, url: URL, stretch: Bool, volume: Float, onReady: (() -> Void)? = nil) {
        dlog("show video \(url.lastPathComponent) on \(screen.dv_localizedName) stretch=\(stretch) volume=\(volume)")
        do {
            let data = try Data(contentsOf: url)
            showVideoFromMemory(for: screen, data: data, stretch: stretch, volume: desktop_videoApp.shared!.globalMute ? 0.0 : volume, originalURL: url, onReady: onReady)
        } catch {
            errorLog("Cannot load from memory!")
        }
    }

    /// 使用与单屏静音相同的逻辑静音所有屏幕，
    /// 会在静音前保存各屏幕最后一次非零音量。
    func muteAllScreens() {
        dlog("mute all screens")
        // 先记录音量再静音
        for sid in screenContent.keys {
            let currentVol = screenContent[sid]?.volume ?? 0
            if currentVol > 0 { savedVolumes[sid] = currentVol }
            if let screen = NSScreen.screen(forDisplayID: sid) {
                setVolume(0, for: screen)
            }
        }
    }

    /// 恢复所有屏幕在上次全局静音前的音量，
    /// 已经为 0 的屏幕保持静音。
    func restoreAllScreens() {
        dlog("restore all screens")
        for sid in screenContent.keys {
            let newVol = savedVolumes[sid] ?? (screenContent[sid]?.volume ?? 0)
            if let screen = NSScreen.screen(forDisplayID: sid) {
                setVolume(newVol, for: screen)
            }
        }
        savedVolumes.removeAll()

        // 通知界面刷新音量滑块
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

    // 更新设置后视频不再从内存播放，
    // 处理超大文件时会遇到此问题。
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
            // 保存当前时间戳
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

            // 检查记录是否过期
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
            // 手动调整音量会取消全局静音
            if volume > 0 {
                desktop_videoApp.shared!.globalMute = false
            }

            // 应用到播放器并持久化
            updateVideoSettings(for: screen, stretch: entry.stretch, volume: volume)
            screenContent[sid] = (.video, entry.url, entry.stretch, volume)
        }

        // 通知所有界面立即刷新滑块和标签
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
                    // 无对应屏幕对象时直接移除记录
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

            // 设置新内容前先清空该屏幕
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

        // 移除已断开的屏幕窗口
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

        // 为新连接的屏幕创建窗口
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

    /// 将内存中的视频数据写入临时文件后播放。
    /// - Parameters:
    ///   - screen: 要显示视频的屏幕
    ///   - data: 视频数据
    ///   - stretch: 是否铺满
    ///   - volume: 播放音量
    ///   - originalURL: 用户选择的视频源地址
    ///   - onReady: 准备完成回调
    func showVideoFromMemory(for screen: NSScreen, data: Data, stretch: Bool, volume: Float, originalURL: URL? = nil, onReady: (() -> Void)? = nil) {
        dlog("show video from memory on \(screen.dv_localizedName) stretch=\(stretch) volume=\(volume)")
        guard let sid = id(for: screen) else { return }
        ensureWindow(for: screen)
        stopVideoIfNeeded(for: screen)
        guard let contentView = windows[sid]?.contentView else { return }

        // 将数据写入临时文件
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
        // 记录原始视频地址而非临时文件，用于保留用户选择
        screenContent[sid] = (.video, originalURL ?? tempURL, stretch, volume)

        if let sourceURL = originalURL {
            saveBookmark(for: sourceURL, stretch: stretch, volume: volume, screen: screen)
        }

        switchContent(to: playerView, for: screen)
        NotificationCenter.default.post(name: NSNotification.Name("WallpaperContentDidChange"), object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // 在开始播放之前检查是否应当暂停播放
            if AppDelegate.shared.shouldPauseVideo(on: screen) {
                // 如果需要暂停，不调用 play，而是启动鼠标监听以便后续重新检测
//                self.startMouseMonitor()
            } else {
                // 在播放前附加循环检测，以便每次 loop 达到末尾时做一次新的 shouldPauseVideo 判断
//                self.attachLoopObserver(for: queuePlayer, screenID: sid)
                queuePlayer.play()
            }
            onReady?()
        }
    }
}


//
//  AppDelegate.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/25/25.
//

import AppKit
import SwiftUI
import AVFoundation
import CoreGraphics
import AVKit
import Combine
import IOKit
import IOKit.pwr_mgt


// AppDelegate: APP 启动项管理，启动 APP 的时候会先运行 AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    static var shared: AppDelegate!
    var window: NSWindow?
    var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?

    private var lastAppearanceChangeTime: Date = .distantPast
    private var appearanceChangeWorkItem: DispatchWorkItem?

    // 屏保相关变量
    private var screensaverTimer: Timer?
    private var eventMonitors: [Any] = []
    private var isInScreensaver = false
    // 屏保模式下的时钟标签
    private var clockDateLabels: [NSTextField] = []
    private var clockTimeLabels: [NSTextField] = []
    private var clockTimer: Timer?
    // 防止显示器休眠的断言 ID
    private var displaySleepAssertionID: IOPMAssertionID = 0
    // 外部应用禁止屏保的标记
    private var otherAppSuppressScreensaver: Bool = false

    // UserDefaults 键名
    private let screensaverEnabledKey = "screensaverEnabled"
    private let screensaverDelayMinutesKey = "screensaverDelayMinutes"

    private var cancellables = Set<AnyCancellable>()

    // lastAppearanceChangeTime 用于删除 bookmark, 24 小时后自动删除
    // appearanceChangeWorkItem 用于设置 bookmark


    func applicationDidFinishLaunching(_ notification: Notification) {
        dlog("applicationDidFinishLaunching")
        AppDelegate.shared = self

        // 从书签中恢复窗口
        SharedWallpaperWindowManager.shared.restoreFromBookmark()
        
        // Observe occlusion changes on overlay windows to auto-pause/play
        for windows in SharedWallpaperWindowManager.shared.overlayWindows.values {
            for window in windows {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(wallpaperWindowOcclusionDidChange(_:)),
                    name: NSWindow.didChangeOcclusionStateNotification,
                    object: window
                )
            }
        }

        // 切换 Dock 图标或仅菜单栏模式
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let showOnlyInMenuBar = UserDefaults.standard.bool(forKey: "isMenuBarOnly")
            self.setDockIconVisible(true)
            if showOnlyInMenuBar {
                self.setDockIconVisible(!showOnlyInMenuBar)
            }
            if self.window == nil {
                self.openMainWindow()
            }
        }

        // 监听屏保设置变化并启动计时器
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.startScreensaverTimer()
            }
            .store(in: &cancellables)

        // 监听应用激活状态以重置屏保计时器
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActiveNotification), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActiveNotification), name: NSApplication.didResignActiveNotification, object: nil)

        // 注册分布式通知，用于外部应用控制屏保
        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(self,
                               selector: #selector(handleExternalScreensaverActive(_:)),
                               name: Notification.Name("OtherAppScreensaverActive"),
                               object: nil)
        distCenter.addObserver(self,
                               selector: #selector(handleExternalScreensaverInactive(_:)),
                               name: Notification.Name("OtherAppScreensaverInactive"),
                               object: nil)

        // Ensure shouldPauseVideo is evaluated once when the app launches
        pauseVideoForAllScreens()
        // Periodically re-evaluate occlusion to pause/play videos
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pauseVideoForAllScreens()
        }
    }

    // MARK: - Screensaver Timer Methods

    func startScreensaverTimer() {
        // 若计时器已在运行则直接返回
        if screensaverTimer != nil && screensaverTimer?.isValid == true {
            dlog("startScreensaverTimer: timer already running, returning early")
            return
        }
        dlog("startScreensaverTimer isInScreensaver=\(isInScreensaver) otherAppSuppressScreensaver=\(otherAppSuppressScreensaver) url=\(AppState.shared.currentMediaURL ?? "None")")
        // 先检查是否被其他应用暂停
        guard !otherAppSuppressScreensaver else {
            dlog("Screensaver not started: external suppression active.")
            return
        }
        guard !isInScreensaver else {
            dlog("Screensaver not started: is alread in screensaver.")
            return
        }
        // 检查是否有可播放的媒体
        guard AppState.shared.currentMediaURL != nil else {
            dlog("Screensaver not started: no valid media selected or playable.")
            return
        }

        screensaverTimer?.invalidate()
        screensaverTimer = nil

        guard UserDefaults.standard.bool(forKey: screensaverEnabledKey) else {
            closeScreensaverWindows()
            return
        }

        let delayMinutes = UserDefaults.standard.integer(forKey: screensaverDelayMinutesKey)
        let delaySeconds = TimeInterval(max(delayMinutes, 1) * 60)

        screensaverTimer = Timer.scheduledTimer(withTimeInterval: delaySeconds / 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard AppState.shared.currentMediaURL != nil else {
                dlog("Screensaver not started: no valid media selected or playable.")
                self.screensaverTimer?.invalidate()
                self.screensaverTimer = nil
                return
            }
            let idleTime = self.getSystemIdleTime()
            dlog("idleTime=\(idleTime) delaySeconds=\(delaySeconds)")
            if idleTime >= delaySeconds {
                self.screensaverTimer?.invalidate()
                self.screensaverTimer = nil
                dlog("idleTime >= delaySeconds (\(idleTime) >= \(delaySeconds)), triggering runScreenSaver()")
                self.runScreenSaver()
            }
        }
    }

    // 获取系统级用户空闲时间（秒）
    private func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator)
        if result != KERN_SUCCESS { return 0 }

        let entry = IOIteratorNext(iterator)
        IOObjectRelease(iterator)

        var dict: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0)
        IOObjectRelease(entry)

        guard kr == KERN_SUCCESS, let cfDict = dict?.takeRetainedValue() as? [String: Any],
              let idleNS = cfDict["HIDIdleTime"] as? UInt64 else {
            return 0
        }

        return TimeInterval(idleNS) / 1_000_000_000
    }

    @objc func runScreenSaver() {
        dlog("runScreenSaver isInScreensaver=\(isInScreensaver)")
        guard UserDefaults.standard.bool(forKey: screensaverEnabledKey) else { return }
        if isInScreensaver { return }

        dlog("Starting screensaver mode")

//        防止系统进入屏保或息屏
        let assertionReason = "DesktopVideo screensaver active" as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionReason,
            &displaySleepAssertionID
        )

        // 使用现有窗口列表的键值
        let keys = NSScreen.screens.compactMap { screen in
            screen.dv_displayID.flatMap { id in
                SharedWallpaperWindowManager.shared.windows.keys.contains(id) ? id : nil
            }
        }
        dlog("windows.keys = \(keys)")

        // 隐藏检测窗口，避免屏保模式下触发自动暂停
        for overlays in SharedWallpaperWindowManager.shared.overlayWindows.values {
            for overlay in overlays { overlay.orderOut(nil) }
        }

        // 1. 提升现有壁纸窗口为屏保窗口，并添加淡入动画
        for id in keys {
            dlog("looping id = \(id)")
            if let screen = NSScreen.screen(forDisplayID: id) {
                dlog("found screen: \(screen)")
                guard let wallpaperWindow = SharedWallpaperWindowManager.shared.windows[id] else { continue }
                wallpaperWindow.level = .screenSaver
                wallpaperWindow.ignoresMouseEvents = false
                wallpaperWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                wallpaperWindow.alphaValue = 0 // 初始透明
                wallpaperWindow.makeKeyAndOrderFront(nil)

                // 使用动画淡入
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.5
                    wallpaperWindow.animator().alphaValue = 1
                }, completionHandler: nil)

                // 确保视频继续播放
                if let player = SharedWallpaperWindowManager.shared.players[id] {
                    player.play()
                }

                // 添加日期文本
                let dateLabel = NSTextField(labelWithString: "")
                dateLabel.font = NSFont(name: "DIN Alternate", size: 30) ?? NSFont.systemFont(ofSize: 30, weight: .medium)
                dateLabel.textColor = .white
                dateLabel.backgroundColor = .clear
                dateLabel.isBezeled = false
                dateLabel.isEditable = false
                dateLabel.sizeToFit()
                // 根据窗口内容视图计算标签位置
                if let contentBounds = wallpaperWindow.contentView?.bounds {
                    // 使用和 updateClockLabels 相同的逻辑：顶部中央，向下偏移20点
                    let dateX = contentBounds.midX - dateLabel.frame.width / 2
                    let dateY = contentBounds.maxY - dateLabel.frame.height - 20
                    dateLabel.frame.origin = CGPoint(x: dateX, y: dateY)
                }
                wallpaperWindow.contentView?.addSubview(dateLabel)
                clockDateLabels.append(dateLabel)

                // 添加时间文本，位于日期标签下方约两倍高度处
                let timeLabel = NSTextField(labelWithString: "")
                timeLabel.font = NSFont(name: "DIN Alternate", size: 100) ?? NSFont.systemFont(ofSize: 100, weight: .light)
                timeLabel.textColor = .white
                timeLabel.backgroundColor = .clear
                timeLabel.isBezeled = false
                timeLabel.isEditable = false
                timeLabel.sizeToFit()
                // 根据窗口内容视图计算标签位置
                if let contentBounds = wallpaperWindow.contentView?.bounds {
                    // 使用和 updateClockLabels 相同的逻辑：日期标签下方，间隔10点
                    let dateY = dateLabel.frame.origin.y
                    let dateHeight = dateLabel.frame.height
                    let timeX = contentBounds.midX - timeLabel.frame.width / 2
                    let timeY = dateY - dateHeight - timeLabel.frame.height - 10
                    timeLabel.frame.origin = CGPoint(x: timeX, y: timeY)
                }
                wallpaperWindow.contentView?.addSubview(timeLabel)
                clockTimeLabels.append(timeLabel)
            } else {
                dlog("no NSScreen found forDisplayID \(id), skipping")
                continue
            }
        }

        // 开始更新时钟标签
        updateClockLabels() // initial update
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClockLabels()
        }

        // 2. 延迟 0.5 秒后再添加事件监听器并设置 isInScreensaver
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let eventTypes: [NSEvent.EventTypeMask] = [.any]
            for eventType in eventTypes {
                let monitor = NSEvent.addGlobalMonitorForEvents(matching: eventType) { [weak self] _ in
                    self?.closeScreensaverWindows()
                }
                if let monitor = monitor {
                    self.eventMonitors.append(monitor)
                }
            }
            let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .any) { [weak self] event in
                self?.closeScreensaverWindows()
                return event
            }
            if let localMonitor = localMonitor {
                self.eventMonitors.append(localMonitor)
            }
            self.isInScreensaver = true
        }
    }

    func closeScreensaverWindows() {
        dlog("closeScreensaverWindows")
        if !isInScreensaver { return }

        dlog("Exiting screensaver mode")

        // 释放防休眠断言
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }

        // 清理时钟定时器和标签
        clockTimer?.invalidate()
        clockTimer = nil
        for label in clockDateLabels {
            label.removeFromSuperview()
        }
        clockDateLabels.removeAll()
        for label in clockTimeLabels {
            label.removeFromSuperview()
        }
        clockTimeLabels.removeAll()

        // 1. 对每个窗口执行淡出动画后再恢复
        for (id, wallpaperWindow) in SharedWallpaperWindowManager.shared.windows {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                wallpaperWindow.animator().alphaValue = 0
            }, completionHandler: {
                wallpaperWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
                wallpaperWindow.ignoresMouseEvents = true
                wallpaperWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                wallpaperWindow.orderBack(nil)

                // 确保视频继续播放
                if let player = SharedWallpaperWindowManager.shared.players[id] {
                    player.play()
                }
                wallpaperWindow.alphaValue = 1 // 恢复透明度供下一次屏保使用
            })
        }

        // 重新显示检测窗口
        for overlays in SharedWallpaperWindowManager.shared.overlayWindows.values {
            for overlay in overlays { overlay.orderFrontRegardless() }
        }

        // 2. 移除事件监听器
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()

        isInScreensaver = false

        // 3. 重置屏保计时器
        startScreensaverTimer()
    }

    @objc private func applicationDidBecomeActiveNotification() {
        dlog("applicationDidBecomeActiveNotification")
        // Only close screensaver if currently in screensaver
        if isInScreensaver {
            closeScreensaverWindows()
        }
    }

    @objc private func applicationDidResignActiveNotification() {
        dlog("applicationDidResignActiveNotification")
        // Only restart timer if not currently in screensaver
        if !isInScreensaver {
            startScreensaverTimer()
        }
    }

    // 打开主控制器界面
    @objc func toggleMainWindow() {
        dlog("toggleMainWindow")
        NSApp.activate(ignoringOtherApps: true)
        // 如果已经有窗口了就不新建窗口
        if let win = self.window {
            win.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow()
        }
    }

    static func openPreferencesWindow() {
        dlog("openPreferencesWindow")
        guard let delegate = shared else { return }

        if let win = delegate.preferencesWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let prefsView = PreferencesView()
            let hosting = NSHostingController(rootView: prefsView)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 320), // 修改尺寸为240×320
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = L("PreferencesTitle")
            win.contentView = hosting.view
            win.isReleasedWhenClosed = false
            win.delegate = delegate
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            delegate.preferencesWindow = win
        }
    }

    @objc func openPreferences() {
        dlog("openPreferences")
        AppDelegate.openPreferencesWindow() // 调用静态方法
    }

    func windowWillClose(_ notification: Notification) {
        dlog("windowWillClose")
        if let win = notification.object as? NSWindow, win == self.window {
            self.window = nil
        }
        // 添加处理preferences窗口关闭
        if let win = notification.object as? NSWindow, win == self.preferencesWindow {
            self.preferencesWindow = nil
        }
    }

    // 打开窗口
    func openMainWindow() {
        dlog("openMainWindow")
        if let win = self.window {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.makeKeyAndOrderFront(nil)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            return
        }

        let contentView = ContentView()
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 325),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        newWindow.center()
        newWindow.title = L("Controller")
        newWindow.contentView = NSHostingView(rootView: contentView)

        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)

        self.window = newWindow
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    // 重新打开窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dlog("applicationShouldHandleReopen visible=\(flag)")
        if !flag || window == nil || !window!.isVisible {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            openMainWindow()
        }
        return true
    }

    // 设置定时删除 bookmark 避免被塞垃圾
    func applyAppAppearanceSetting(onlyShowInMenuBar: Bool) {
        dlog("applyAppAppearanceSetting onlyShowInMenuBar=\(onlyShowInMenuBar)")
        appearanceChangeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lastAppearanceChangeTime = Date()
            if onlyShowInMenuBar {
                NSApp.setActivationPolicy(.accessory)
                self.setupStatusBarIcon()
            } else {
                NSApp.setActivationPolicy(.regular)
                self.removeStatusBarIcon()
            }
            self.statusBarIconClicked()
        }

        appearanceChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    // 设置菜单栏
    func setupStatusBarIcon() {
        dlog("setupStatusBarIcon")
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = statusItem?.button {
                button.image = NSImage(named: "MenuBarIcon")
                button.image?.isTemplate = true
                let menu = NSMenu()
                menu.addItem(
                    withTitle: L("AboutDesktopVideo"),
                    action: #selector(showAboutFromStatus),
                    keyEquivalent: ""
                )
                menu.addItem(NSMenuItem.separator())
                menu.addItem(
                    withTitle: NSLocalizedString(L("OpenMainWindow"), comment: ""),
                    action: #selector(toggleMainWindow),
                    keyEquivalent: ""
                )
                menu.addItem(
                    withTitle: NSLocalizedString(L("Preferences"), comment: ""),
                    action: #selector(openPreferences),
                    keyEquivalent: ""
                )
                menu.addItem(
                     withTitle: L("QuitDesktopVideo"),
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: ""
                 )
                statusItem?.menu = menu
            }
        }
    }

    // 删除菜单栏图标
    func removeStatusBarIcon() {
        dlog("removeStatusBarIcon")
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // 如果点击菜单栏按钮就打开主控制器界面
    @objc func statusBarIconClicked() {
        dlog("statusBarIconClicked")
        toggleMainWindow()
    }

    // 是否显示 Docker 栏图标
    public func setDockIconVisible(_ visible: Bool) {
        dlog("setDockIconVisible \(visible)")
        applyAppAppearanceSetting(onlyShowInMenuBar: !visible)
        UserDefaults.standard.set(!visible, forKey: "isMenuBarOnly")
    }

    // MARK: - Idle Timer Methods

    private func pauseVideoForAllScreens() {
        dlog("pauseVideoForAllScreens")
        if isInScreensaver { return }

        for (sid, player) in SharedWallpaperWindowManager.shared.players {
            if let screen = NSScreen.screen(forDisplayID: sid) {
                let shouldPause = shouldPauseVideo(on: screen)
                dlog("pauseVideoForAllScreens: shouldPause=\(shouldPause) on \(screen.dv_localizedName)")
                if shouldPause {
                    dlog("Pausing video on screen \(screen.dv_localizedName)")
                    player.pause()
                } else {
                    dlog("Playing video on screen \(screen.dv_localizedName)")
                    player.play()
                }
            }
        }
    }

    /// 判断指定屏幕的检测窗口是否被遮挡
    func shouldPauseVideo(on screen: NSScreen) -> Bool {
        dlog("shouldPauseVideo on \(screen.dv_localizedName)")
        if isInScreensaver { return false }

        guard let id = screen.dv_displayID,
              let windows = SharedWallpaperWindowManager.shared.overlayWindows[id] else {
            return false
        }
        return windows.allSatisfy { !$0.occlusionState.contains(.visible) }
    }

    @objc func wallpaperWindowOcclusionDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if isInScreensaver { return }
        guard let sid = SharedWallpaperWindowManager.shared.overlayWindows.first(where: { $0.value.contains(window) })?.key,
              let player = SharedWallpaperWindowManager.shared.players[sid],
              let screen = NSScreen.screen(forDisplayID: sid) else { return }
        if shouldPauseVideo(on: screen) {
            player.pause()
        } else {
            player.play()
        }
    }

    // MARK: - NSApplicationDelegate Idle Pause
    func applicationDidBecomeActive(_ notification: Notification) {
        dlog("applicationDidBecomeActive")
        pauseVideoForAllScreens()
    }
    // 从菜单栏打开关于窗口
    @objc func showAboutFromStatus() {
        dlog("showAboutFromStatus")
        desktop_videoApp.shared?.showAboutDialog()
    }
    // 更新时钟标签位置和时间
    private func updateClockLabels() {
        dlog("updateClockLabels")
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "EEEE, yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: Date())

        // 使用每个标签对应的屏幕顺序遍历，更新所有屏幕的日期/时间标签
        for (index, dateLabel) in clockDateLabels.enumerated() {
            guard index < clockTimeLabels.count, index < NSScreen.screens.count else { continue }
            let timeLabel = clockTimeLabels[index]
            let screen = NSScreen.screens[index]
            // 找到对应屏幕的 WallpaperWindow
            if let sid = screen.dv_displayID,
               let window = SharedWallpaperWindowManager.shared.windows[sid],
               let contentBounds = window.contentView?.bounds {

                // 更新日期标签
                dateLabel.stringValue = dateString
                dateLabel.sizeToFit()
                let dateX = contentBounds.midX - dateLabel.frame.width / 2
                let dateY = contentBounds.maxY - dateLabel.frame.height - 20
                dateLabel.frame.origin = CGPoint(x: dateX, y: dateY)

                // 更新时间标签
                timeLabel.stringValue = timeString
                timeLabel.sizeToFit()
                let timeX = contentBounds.midX - timeLabel.frame.width / 2
                let timeY = dateY - dateLabel.frame.height - timeLabel.frame.height - 10
                timeLabel.frame.origin = CGPoint(x: timeX, y: timeY)
            }
        }
    }
    // MARK: - External Screensaver Suppression
    @objc private func handleExternalScreensaverActive(_ notification: Notification) {
        dlog("handleExternalScreensaverActive")
        otherAppSuppressScreensaver = true
        // 若计时器存在则取消
        screensaverTimer?.invalidate()
        screensaverTimer = nil
    }

    @objc private func handleExternalScreensaverInactive(_ notification: Notification) {
        dlog("handleExternalScreensaverInactive")
        otherAppSuppressScreensaver = false
        // 如有必要重新启动计时器
        startScreensaverTimer()
    }
}

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

// 屏保窗口子类，允许成为 key/main window
class ScreenSaverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// AppDelegate: APP 启动项管理，启动 APP 的时候会先运行 AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    static var shared: AppDelegate!
    var window: NSWindow?
    var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?

    private var lastAppearanceChangeTime: Date = .distantPast
    private var appearanceChangeWorkItem: DispatchWorkItem?

    private var idleTimer: Timer?
    private var idleStartTime: Date?
    private var isPausedDueToIdle: Bool = false

    // Screensaver related
    private var screensaverTimer: Timer?
    private var screensaverWindows: [NSWindow] = []
    private var eventMonitors: [Any] = []
    private var isInScreensaver = false
    // Clock overlays for screensaver
    private var clockDateLabels: [NSTextField] = []
    private var clockTimeLabels: [NSTextField] = []
    private var clockTimer: Timer?
    // Prevent display sleep assertion
    private var displaySleepAssertionID: IOPMAssertionID = 0
    // Track external suppression of screensaver
    private var otherAppSuppressScreensaver: Bool = false
    
    // UserDefaults keys
    private let screensaverEnabledKey = "screensaverEnabled"
    private let screensaverDelayMinutesKey = "screensaverDelayMinutes"
    
    private var cancellables = Set<AnyCancellable>()

    // 防抖：上次屏保检查时间
    private var lastScreensaverCheck: Date = .distantPast

    // lastAppearanceChangeTime 用于删除 bookmark, 24 小时后自动删除
    // appearanceChangeWorkItem 用于设置 bookmark


    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // 从书签中恢复窗口
        SharedWallpaperWindowManager.shared.restoreFromBookmark()
        
        // Docker / 菜单栏切换
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

        // 监听桌面切换，恢复或重置空闲计时器
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Observe screensaver settings changes and start screensaver timer
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.startScreensaverTimer()
            }
            .store(in: &cancellables)
        
        // Observe app active/inactive notifications to reset screensaver timer
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActiveNotification), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActiveNotification), name: NSApplication.didResignActiveNotification, object: nil)

        // Register for distributed notifications for external screensaver suppression
        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(self,
                               selector: #selector(handleExternalScreensaverActive(_:)),
                               name: Notification.Name("OtherAppScreensaverActive"),
                               object: nil)
        distCenter.addObserver(self,
                               selector: #selector(handleExternalScreensaverInactive(_:)),
                               name: Notification.Name("OtherAppScreensaverInactive"),
                               object: nil)

        startScreensaverTimer()
    }

    // MARK: - Screensaver Timer Methods
    
    func startScreensaverTimer() {
        // Check for external suppression first
        guard !otherAppSuppressScreensaver else {
            print("Screensaver not started: external suppression active.")
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastScreensaverCheck) > 1 else {
            return  // 防抖：避免短时间内重复触发
        }
        lastScreensaverCheck = now

        if isInScreensaver { return }

        // Check if selected media is valid and a player exists and is ready to play
        let isPlayable = AppState.shared.currentMediaURL != nil
        
        guard isPlayable else {
            print("Screensaver not started: no valid media selected or playable.")
            return
        }
        
        screensaverTimer?.invalidate()
        
        guard UserDefaults.standard.bool(forKey: screensaverEnabledKey) else {
            closeScreensaverWindows()
            return
        }

        let delayMinutes = UserDefaults.standard.integer(forKey: screensaverDelayMinutesKey)
        let delaySeconds = TimeInterval(max(delayMinutes, 1) * 60)
        
//        let delaySeconds = 1.0
        
        screensaverTimer = Timer.scheduledTimer(withTimeInterval: delaySeconds / 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let idleTime = self.getSystemIdleTime()
            print(idleTime, delaySeconds)
            if idleTime >= delaySeconds {
                self.screensaverTimer?.invalidate()
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
        guard UserDefaults.standard.bool(forKey: screensaverEnabledKey) else { return }
        if isInScreensaver { return }
        
        print("Starting screensaver mode")

        // Prevent system screensaver/display sleep while our screensaver is active
        let assertionReason = "DesktopVideo screensaver active" as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionReason,
            &displaySleepAssertionID
        )

        // 1. 提升现有壁纸窗口为屏保窗口，并添加淡入动画
        for (id, wallpaperWindow) in SharedWallpaperWindowManager.shared.windows {
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

            // Add date overlay
            let screenFrame = wallpaperWindow.frame
            let dateLabel = NSTextField(labelWithString: "")
            dateLabel.font = NSFont.systemFont(ofSize: 30, weight: .medium)
            dateLabel.textColor = .white
            dateLabel.backgroundColor = .clear
            dateLabel.isBezeled = false
            dateLabel.isEditable = false
            dateLabel.sizeToFit()
            // Position at top center
            let dateX = screenFrame.midX - dateLabel.frame.width / 2
            let dateY = screenFrame.maxY - dateLabel.frame.height * 3
            dateLabel.frame.origin = CGPoint(x: dateX, y: dateY)
            wallpaperWindow.contentView?.addSubview(dateLabel)
            clockDateLabels.append(dateLabel)

            // Add time overlay
            let timeLabel = NSTextField(labelWithString: "")
            timeLabel.font = NSFont.systemFont(ofSize: 100, weight: .light)
            timeLabel.textColor = .white
            timeLabel.backgroundColor = .clear
            timeLabel.isBezeled = false
            timeLabel.isEditable = false
            timeLabel.sizeToFit()
            // Position below date at center
            let timeX = screenFrame.midX - timeLabel.frame.width / 2
            let timeY = screenFrame.maxY - dateLabel.frame.height * 4 - timeLabel.frame.height / 2
            timeLabel.frame.origin = CGPoint(x: timeX, y: timeY)
            wallpaperWindow.contentView?.addSubview(timeLabel)
            clockTimeLabels.append(timeLabel)
        }

        // Start clock updater
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
        if !isInScreensaver { return }

        print("Exiting screensaver mode")

        // Release the display-sleep prevention assertion
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }

        // Invalidate and clear clock timer/labels
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

        // 2. 移除事件监听器
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()

        isInScreensaver = false

        // 3. 重置屏保计时器
        startScreensaverTimer()
    }
    
    @objc private func applicationDidBecomeActiveNotification() {
        // Only close screensaver if currently in screensaver
        if isInScreensaver {
            closeScreensaverWindows()
        }
    }
    
    @objc private func applicationDidResignActiveNotification() {
        // Only restart timer if not currently in screensaver
        if !isInScreensaver {
            startScreensaverTimer()
        }
    }

    // 打开主控制器界面
    @objc func toggleMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // 如果已经有窗口了就不新建窗口
        if let win = self.window {
            win.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow()
        }
    }

    static func openPreferencesWindow() {
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
        AppDelegate.openPreferencesWindow() // 调用静态方法
    }

    func windowWillClose(_ notification: Notification) {
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
        if !flag || window == nil || !window!.isVisible {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            openMainWindow()
        }
        return true
    }

    // 设置定时删除 bookmark 避免被塞垃圾
    func applyAppAppearanceSetting(onlyShowInMenuBar: Bool) {
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
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // 如果点击菜单栏按钮就打开主控制器界面
    @objc func statusBarIconClicked() {
        toggleMainWindow()
    }

    // 是否显示 Docker 栏图标
    public func setDockIconVisible(_ visible: Bool) {
        applyAppAppearanceSetting(onlyShowInMenuBar: !visible)
        UserDefaults.standard.set(!visible, forKey: "isMenuBarOnly")
    }

    // MARK: - Idle Timer Methods
    private func resetIdleTimer() {
        guard UserDefaults.standard.bool(forKey: "idlePauseEnabled") else { return }
        idleTimer?.invalidate()
        let interval = TimeInterval(UserDefaults.standard.integer(forKey: "idlePauseSeconds"))
        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for (sid, player) in SharedWallpaperWindowManager.shared.players {
                if let screen = NSScreen.screen(forDisplayID: sid), self.shouldPauseVideo(on: screen) {
                    player.pause()
                } else {
                    player.play()
                }
            }
        }
    }

    private func pauseVideoForAllScreens() {
        for (sid, player) in SharedWallpaperWindowManager.shared.players {
            if let screen = NSScreen.screen(forDisplayID: sid), shouldPauseVideo(on: screen) {
                player.pause()
            }
        }
    }

    private func resumeVideoIfPausedByIdle() {
        if isPausedDueToIdle {
            for player in SharedWallpaperWindowManager.shared.players.values {
                player.play()
            }
            isPausedDueToIdle = false
        }
    }
    
    /// 判断指定屏幕是否需要暂停视频
    private func shouldPauseVideo(on screen: NSScreen) -> Bool {
        guard let id = screen.dv_displayID,
              SharedWallpaperWindowManager.shared.windows[id] != nil else {
            return false
        }
        let screenFrame = screen.frame
        let thresholdWidth = screenFrame.width * 0.8
        let thresholdHeight = screenFrame.height * 0.8

        // 查询全局窗口列表，包含其他应用的窗口
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // 检查是否存在大窗口
        return windowList.contains { info in
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == getpid() {
                return false
            }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else {
                return false
            }
            return width >= thresholdWidth && height >= thresholdHeight
        }
    }

    // MARK: - NSApplicationDelegate Idle Pause
    func applicationDidBecomeActive(_ notification: Notification) {
        resumeVideoIfPausedByIdle()
        resetIdleTimer()
    }

    func applicationDidResignActive(_ notification: Notification) {
        resetIdleTimer()
    }

    @objc private func spaceDidChange(_ notification: Notification) {
        // 桌面切换时，根据窗口大小决定是暂停还是播放
        for (sid, player) in SharedWallpaperWindowManager.shared.players {
            if let screen = NSScreen.screen(forDisplayID: sid), shouldPauseVideo(on: screen) {
                player.pause()
            } else {
                player.play()
            }
        }
        // 重置空闲计时器
        resetIdleTimer()
    }
    // Show About dialog from status bar
    @objc func showAboutFromStatus() {
        desktop_videoApp.shared?.showAboutDialog()
    }
    // Helper to update all clock labels with current time and center them
    private func updateClockLabels() {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "EEEE, dd-MM-yyyy" // e.g. "Tuesday, 03-06-2025"
        let dateString = dateFormatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: Date())

        let screens = SharedWallpaperWindowManager.shared.windows.keys.compactMap { NSScreen.screen(forDisplayID: $0) }
        for (index, dateLabel) in clockDateLabels.enumerated() {
            dateLabel.stringValue = dateString
            dateLabel.sizeToFit()
            let screenFrame = screens[index].frame
            let newX = screenFrame.midX - dateLabel.frame.width / 2
            let newY = screenFrame.maxY - dateLabel.frame.height - 50
            dateLabel.frame.origin = CGPoint(x: newX, y: newY)
        }
        for (index, timeLabel) in clockTimeLabels.enumerated() {
            timeLabel.stringValue = timeString
            timeLabel.sizeToFit()
            let screenFrame = screens[index].frame
            let newX = screenFrame.midX - timeLabel.frame.width / 2
            let newY = screenFrame.midY - timeLabel.frame.height / 2
            timeLabel.frame.origin = CGPoint(x: newX, y: newY)
        }
    }
    // MARK: - External Screensaver Suppression
    @objc private func handleExternalScreensaverActive(_ notification: Notification) {
        otherAppSuppressScreensaver = true
        // If a timer is running, invalidate it
        screensaverTimer?.invalidate()
        screensaverTimer = nil
    }

    @objc private func handleExternalScreensaverInactive(_ notification: Notification) {
        otherAppSuppressScreensaver = false
        // Restart timer if appropriate
        startScreensaverTimer()
    }
}

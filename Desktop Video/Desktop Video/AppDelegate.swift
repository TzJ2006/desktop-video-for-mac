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
import Foundation


// AppDelegate: APP 启动项管理，启动 APP 的时候会先运行 AppDelegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

   static var shared: AppDelegate!
   /// Tracks whether the main window has been opened once already
   private var hasOpenedMainWindowOnce = false
   private let clockVerticalPositionFactor: CGFloat = 0.85
   var window: NSWindow?
   var statusItem: NSStatusItem?
   private var preferencesWindow: NSWindow?

   // lastAppearanceChangeTime 用于删除 bookmark, 24 小时后自动删除
   // appearanceChangeWorkItem 用于设置 bookmark
   
   private var lastAppearanceChangeTime: Date = .distantPast
   private var appearanceChangeWorkItem: DispatchWorkItem?

   // 屏保相关变量
   private var screensaverTimer: Timer?
   private var eventMonitors: [Any] = []
   private var isInScreensaver = false
   // Debounce work item for occlusion events
   private var occlusionDebounceWorkItem: DispatchWorkItem?
   /// 记录上次 pauseAll 状态，仅在变化时发送通知
   private var lastPauseAllState: Bool?
   /// Token to keep the system awake while screensaver videos play
   private var systemSleepActivity: NSObjectProtocol?
   // 屏保模式下的时钟标签
   private var clockTimer: Timer?
   // 独立时钟窗口（per-screen UUID → NSWindow）
   private var clockWindows: [String: NSWindow] = [:]
   // 无壁纸屏幕的黑色背景窗口（per-screen UUID → NSWindow）
   private var screensaverBlackWindows: [String: NSWindow] = [:]
   // 防止显示器休眠的断言 ID
   private var displaySleepAssertionID: IOPMAssertionID = 0
   // 外部应用禁止屏保的标记
   private var otherAppSuppressScreensaver: Bool = false
   // 菜单栏“启动屏保”按钮引用，便于根据内容启用/禁用
   private var startScreensaverMenuItem: NSMenuItem?

   // UserDefaults 键名
   private let screensaverEnabledKey = "screensaverEnabled"
   private let screensaverDelayMinutesKey = "screensaverDelayMinutes"

   private var cancellables = Set<AnyCancellable>()


   func applicationDidFinishLaunching(_: Notification) {
       dlog("applicationDidFinishLaunching")
       AppDelegate.shared = self

       // Register default idle pause sensitivity
       UserDefaults.standard.register(defaults: ["idlePauseSensitivity": 40.0])

       // 从书签中恢复窗口
       SharedWallpaperWindowManager.shared.restoreFromBookmark()

       Task { @MainActor in
           WindowManager.shared.startForAllScreens()
       }
       
       // Observe occlusion changes on overlay windows to auto-pause/play
       for window in SharedWallpaperWindowManager.shared.overlayWindows.values {
           NotificationCenter.default.addObserver(
               self,
               selector: #selector(wallpaperWindowOcclusionDidChange(_:)),
               name: NSWindow.didChangeOcclusionStateNotification,
               object: window
           )
       }

       // Observe occlusion changes on screensaver overlay windows to restart screensaver timer
       for win in SharedWallpaperWindowManager.shared.screensaverOverlayWindows.values {
           NotificationCenter.default.addObserver(
               self,
               selector: #selector(screensaverOverlayOcclusionChanged(_:)),
               name: NSWindow.didChangeOcclusionStateNotification,
               object: win
           )
       }

       // 切换 Dock 图标或仅菜单栏模式
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let showOnlyInMenuBar = UserDefaults.standard.bool(forKey: "isMenuBarOnly")
                self.setDockIconVisible(true)
                if showOnlyInMenuBar {
                    self.setDockIconVisible(!showOnlyInMenuBar)
                }
                self.captureMainWindowFromSwiftUI()
                if let trackedWindow = self.window {
                    trackedWindow.makeKeyAndOrderFront(nil)
                    NSRunningApplication.current.activate(options: [.activateAllWindows])
                } else {
                    self.openMainWindow()
                }
            }
        }

       // 监听屏保设置变化并启动计时器
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.startScreensaverTimer()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: Notification.Name("WallpaperContentDidChange"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateScreensaverMenuItemState()
                }
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

       // 监听低电量模式变化，用于自动模式的行为切换
       NotificationCenter.default.addObserver(
           self,
           selector: #selector(powerStateDidChange),
           name: Notification.Name.NSProcessInfoPowerStateDidChange,
           object: nil
       )

       // Ensure shouldPauseVideo is evaluated once when the app launches
       updatePlaybackStateForAllScreens()

       // 应用运行于沙盒环境，不再检查 GitHub 更新以避免网络错误
   }

   // MARK: - Screensaver Timer Methods

   func startScreensaverTimer() {
       // Ensure timer is always scheduled on the main thread
       if !Thread.isMainThread {
           DispatchQueue.main.async { [weak self] in self?.startScreensaverTimer() }
           return
       }
       // Reset any existing timer before scheduling a new one
       screensaverTimer?.invalidate()
       screensaverTimer = nil
       // 先检查是否被其他应用暂停
       guard !otherAppSuppressScreensaver else {
           dlog("Screensaver not started: external suppression active.")
           return
       }
       guard !isInScreensaver else {
           dlog("Screensaver not started: is alread in screensaver.")
           return
       }
       // Suppress screensaver if any screensaver overlay window is fully covered
       let suppressed = SharedWallpaperWindowManager.shared.screensaverOverlayWindows.values.contains {
           !$0.occlusionState.contains(.visible)
       }
       if suppressed {
           dlog("Screensaver not started: a screensaver overlay fully covered")
           return
       }
       guard UserDefaults.standard.bool(forKey: screensaverEnabledKey) else {
           closeScreensaverWindows()
           return
       }
       let delayMinutes = UserDefaults.standard.double(forKey: screensaverDelayMinutesKey)
       let delaySeconds = TimeInterval(max(delayMinutes, 1) * 60)
       dlog("startScreensaverTimer scheduling timer delaySeconds=\(delaySeconds)")
       //debug settings
//      var delaySeconds = 10
//       dlog("Warning! Debug settings on !!!")

       screensaverTimer = Timer.scheduledTimer(withTimeInterval: delaySeconds / 5, repeats: true) { [weak self] _ in
           Task { @MainActor [weak self] in
               guard let self else { return }
               let idleTime = self.getSystemIdleTime()
               if idleTime >= delaySeconds {
                   self.screensaverTimer?.invalidate()
                   self.screensaverTimer = nil
                   dlog("idleTime >= delaySeconds (\(idleTime) >= \(delaySeconds)), scheduling runScreenSaver() after 3 s grace period")

                   Task { @MainActor [weak self] in
                       try? await Task.sleep(nanoseconds: 3_000_000_000)
                       self?.runScreenSaver()
                   }
               }
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

       // 若全屏覆盖窗口被完全遮挡，则取消进入屏保
       let shouldCancel = SharedWallpaperWindowManager.shared.screensaverOverlayWindows.values.contains { window in
           !window.occlusionState.contains(.visible)
       }
       if shouldCancel {
           dlog("Screensaver not started: overlay fully covered")
           startScreensaverTimer()
           return
       }

       // 屏保模式即将开启，立即标记以避免窗口遮挡事件暂停视频
       isInScreensaver = true

       dlog("Starting screensaver mode")

//        防止系统进入屏保或息屏
       let assertionReason = "DesktopVideo screensaver active" as CFString
       IOPMAssertionCreateWithName(
           kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
           IOPMAssertionLevel(kIOPMAssertionLevelOn),
           assertionReason,
           &displaySleepAssertionID
       )
       // Disable system sleep while the screensaver is running
       systemSleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled], reason: "DesktopVideo screensaver active")
       dlog("beginActivity to keep system awake during screensaver")

       dlog("runScreenSaver iterating all screens")

       // 隐藏检测窗口，避免屏保模式下触发自动暂停
       for overlay in SharedWallpaperWindowManager.shared.overlayWindows.values {
           overlay.orderOut(nil)
       }
       // 隐藏全屏检测窗口，避免干扰
       for overlay in SharedWallpaperWindowManager.shared.screensaverOverlayWindows.values {
           overlay.orderOut(nil)
       }

       // 1. 遍历所有屏幕，有壁纸窗口的提升为屏保，没有壁纸的创建黑色背景窗口
       var pendingResumeIDs: [String] = []
       let dateText = formatScreensaverDate()
       let timeText = formatScreensaverTime()

       for screen in NSScreen.screens {
           let id = screen.dv_displayUUID
           dlog("looping screen id = \(id)")

           let hasWallpaper = SharedWallpaperWindowManager.shared.windowControllers[id]?.window != nil
           let referenceFrame: NSRect
           var referenceWindowNumber: Int?

           if hasWallpaper, let wallpaperWindow = SharedWallpaperWindowManager.shared.windowControllers[id]?.window {
               // === 有壁纸窗口：提升为屏保级别 ===
               wallpaperWindow.contentView?.wantsLayer = true
               wallpaperWindow.level = .screenSaver
               wallpaperWindow.ignoresMouseEvents = false
               wallpaperWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
               wallpaperWindow.alphaValue = 0
               wallpaperWindow.orderFront(nil)
               referenceFrame = wallpaperWindow.frame
               referenceWindowNumber = wallpaperWindow.windowNumber
               pendingResumeIDs.append(id)
           } else {
               // === 无壁纸窗口：创建黑色全屏窗口 ===
               let blackWin = NSWindow(
                   contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false
               )
               blackWin.isOpaque = true
               blackWin.backgroundColor = .black
               blackWin.hasShadow = false
               blackWin.ignoresMouseEvents = false
               blackWin.level = .screenSaver
               blackWin.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
               blackWin.alphaValue = 0
               blackWin.orderFront(nil)
               screensaverBlackWindows[id] = blackWin
               referenceFrame = screen.frame
               referenceWindowNumber = blackWin.windowNumber
           }

           // === 创建时钟窗口（两种屏幕共用） ===
           let clockWin = NSWindow(
               contentRect: referenceFrame,
               styleMask: .borderless,
               backing: .buffered,
               defer: false
           )
           clockWin.isOpaque = false
           clockWin.backgroundColor = .clear
           clockWin.hasShadow = false
           clockWin.ignoresMouseEvents = true
           clockWin.level = .screenSaver
           clockWin.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

           let highlightHost = NSHostingView(rootView: ScreensaverClockHighlight(dateText: dateText, timeText: timeText))
           let clockSize = highlightHost.fittingSize

           let contentBounds = CGRect(origin: .zero, size: referenceFrame.size)
           let originX = (contentBounds.width - clockSize.width) / 2
           let originY = contentBounds.height * clockVerticalPositionFactor - clockSize.height / 2
           let clockFrame = CGRect(origin: CGPoint(x: originX, y: originY), size: clockSize)

           if hasWallpaper {
               // 有壁纸：使用毛玻璃 + 高光
               let blurView = NSVisualEffectView(frame: clockWin.contentView!.bounds)
               blurView.blendingMode = .behindWindow
               blurView.material = .hudWindow
               blurView.state = .active
               blurView.wantsLayer = true
               blurView.frame = clockFrame
               blurView.autoresizingMask = []

               let maskImage = renderTextMask(dateText: dateText, timeText: timeText, size: clockSize)
               let maskLayer = CALayer()
               maskLayer.frame = blurView.bounds
               maskLayer.contents = maskImage
               maskLayer.contentsGravity = .resize
               blurView.layer?.mask = maskLayer

               highlightHost.frame = clockFrame
               highlightHost.wantsLayer = true
               highlightHost.layer?.backgroundColor = .clear

               clockWin.contentView?.addSubview(blurView)
               clockWin.contentView?.addSubview(highlightHost)
           } else {
               // 无壁纸：黑色背景上直接显示白色文字（不需要毛玻璃）
               highlightHost.frame = clockFrame
               highlightHost.wantsLayer = true
               highlightHost.layer?.backgroundColor = .clear

               clockWin.contentView?.addSubview(highlightHost)
           }

           clockWin.alphaValue = 0
           if let refNum = referenceWindowNumber {
               clockWin.order(.above, relativeTo: refNum)
           }
           clockWindows[id] = clockWin

           // 淡入动画
           NSAnimationContext.runAnimationGroup({ context in
               context.duration = 1.0
               context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
               if hasWallpaper, let wallpaperWindow = SharedWallpaperWindowManager.shared.windowControllers[id]?.window {
                   wallpaperWindow.animator().alphaValue = 1
               }
               if let blackWin = self.screensaverBlackWindows[id] {
                   blackWin.animator().alphaValue = 1
               }
               clockWin.animator().alphaValue = 1
           }, completionHandler: nil)
       }

       // === 立即恢复各屏幕的视频播放 ===
       for pid in pendingResumeIDs {
           reloadAndPlayVideo(displayUUID: pid)
       }

       // 视频重载可能调用 orderFrontRegardless，需要把时钟窗口重新排到壁纸上方
       for (sid, clockWin) in clockWindows {
           if let wallpaperWin = SharedWallpaperWindowManager.shared.windowControllers[sid]?.window {
               clockWin.order(.above, relativeTo: wallpaperWin.windowNumber)
           }
       }

       // 开始更新时钟标签
       updateClockLabels() // initial update
       clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
           Task { @MainActor [weak self] in
               self?.updateClockLabels()
           }
       }
       dlog("updateClockLabels")

       // 2. 延迟 0.5 秒后再添加事件监听器并设置 isInScreensaver
       eventMonitors.forEach { NSEvent.removeMonitor($0) }
       eventMonitors.removeAll()

       DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
           Task { @MainActor [weak self] in
               guard let self else { return }
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
           }
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
       if let token = systemSleepActivity {
           ProcessInfo.processInfo.endActivity(token)
           systemSleepActivity = nil
           dlog("endActivity restore system sleep settings")
       }

       // 清理时钟定时器和标签
       clockTimer?.invalidate()
       clockTimer = nil
        // 1. 对每个窗口执行淡出动画后再恢复
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.5
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        for (_, clockWin) in clockWindows {
            clockWin.animator().alphaValue = 0
        }

        for (_, wallpaperWindowController) in SharedWallpaperWindowManager.shared.windowControllers {
            guard let wallpaperWindow = wallpaperWindowController.window else { continue }
            wallpaperWindow.animator().alphaValue = 0
        }

        // 淡出黑色背景窗口
        for (_, blackWin) in screensaverBlackWindows {
            blackWin.animator().alphaValue = 0
        }

        NSAnimationContext.current.completionHandler = {
            for (_, clockWin) in self.clockWindows {
                clockWin.orderOut(nil)
            }
            self.clockWindows.removeAll()

            // 清理黑色背景窗口
            for (_, blackWin) in self.screensaverBlackWindows {
                blackWin.orderOut(nil)
            }
            self.screensaverBlackWindows.removeAll()

            for (_, wallpaperWindowController) in SharedWallpaperWindowManager.shared.windowControllers {
                guard let wallpaperWindow = wallpaperWindowController.window else { continue }
                wallpaperWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
                wallpaperWindow.ignoresMouseEvents = true
                wallpaperWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                wallpaperWindow.orderBack(nil)
                wallpaperWindow.alphaValue = 1 // 恢复透明度供下一次屏保使用
            }
        }
        NSAnimationContext.endGrouping()

       // 重新显示检测窗口
       for overlay in SharedWallpaperWindowManager.shared.overlayWindows.values {
           overlay.orderFrontRegardless()
       }
       // 恢复全屏检测窗口
       for overlay in SharedWallpaperWindowManager.shared.screensaverOverlayWindows.values {
           overlay.orderFrontRegardless()
       }

       // 2. 移除事件监听器
       eventMonitors.forEach { NSEvent.removeMonitor($0) }
       eventMonitors.removeAll()

       isInScreensaver = false

       // 3. 重置屏保计时器
       startScreensaverTimer()
       
       // 4. 恢复视频播放状态
       updatePlaybackStateForAllScreens()
       
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
        captureMainWindowFromSwiftUI()
        if let win = self.window {
            win.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow()
        }
    }

    func adoptMainWindowIfNeeded(_ window: NSWindow) {
        dlog("adoptMainWindowIfNeeded alreadyTracked=\(self.window === window)")
        guard self.window !== window else { return }
        self.window = window
        hasOpenedMainWindowOnce = true
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    private func captureMainWindowFromSwiftUI() {
        dlog("captureMainWindowFromSwiftUI trackedExists=\(self.window != nil) windowCount=\(NSApp.windows.count)")
        guard self.window == nil else { return }
        if let swiftWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "MainWindow" }) {
            adoptMainWindowIfNeeded(swiftWindow)
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
   @objc func openMainWindow() {
        captureMainWindowFromSwiftUI()
        // Only delay on the very first open
        if !hasOpenedMainWindowOnce {
            dlog("OpenMainWindow for the first time")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.performOpenMainWindow()  // call helper to do the actual open
                }
            }
       } else {
           dlog("OpenMainWindow immediately")
           // Subsequent opens happen immediately
           performOpenMainWindow()
       }
   }

    /// Actual implementation to open or activate the main window
    private func performOpenMainWindow() {
        dlog("openMainWindow (delayed or immediate)")
        captureMainWindowFromSwiftUI()
        if let win = self.window {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
           win.makeKeyAndOrderFront(nil)
           NSRunningApplication.current.activate(options: [.activateAllWindows])
           return
       }
       // Existing creation code...
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
        hasOpenedMainWindowOnce = true
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastAppearanceChangeTime = Date()
                if onlyShowInMenuBar {
                    NSApp.setActivationPolicy(.accessory)
                    self.setupStatusBarIcon()
                } else {
                    NSApp.setActivationPolicy(.regular)
                    self.removeStatusBarIcon()
                }
                if self.hasOpenedMainWindowOnce {
                    self.toggleMainWindow()
                }
                hasOpenedMainWindowOnce = true
 //           self.statusBarIconClicked()
            }
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
               let ssItem = menu.addItem(
                   withTitle: L("StartScreensaver"),          // 本地化键
                   action: #selector(manualRunScreensaver(_:)),
                   keyEquivalent: KeyBindings.startScreensaverKey
               )
               ssItem.keyEquivalentModifierMask = KeyBindings.startScreensaverModifiers
               startScreensaverMenuItem = ssItem
               updateScreensaverMenuItemState()
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
           startScreensaverMenuItem = nil
       }
   }

   // 如果点击菜单栏按钮就打开主控制器界面
//   @objc func statusBarIconClicked() {
//       dlog("statusBarIconClicked")
//       toggleMainWindow()
//   }
    
    /// Manually trigger the screensaver from UI.
   @objc func manualRunScreensaver(_: Any? = nil) {
        dlog("manualRunScreensaver")
        // 若用户在偏好里关闭了屏保，也顺便帮他打开
        if !UserDefaults.standard.bool(forKey: screensaverEnabledKey) {
            UserDefaults.standard.set(true, forKey: screensaverEnabledKey)
        }
        runScreenSaver()    // 已有方法，直接复用
    }

   /// 根据屏保开关状态启用或禁用菜单栏中的屏保按钮（无视频时也允许启动屏保）
   private func updateScreensaverMenuItemState() {
       let screensaverEnabled = UserDefaults.standard.bool(forKey: screensaverEnabledKey)
       dlog("updateScreensaverMenuItemState screensaverEnabled=\(screensaverEnabled)", level: .info)
       startScreensaverMenuItem?.isEnabled = true
   }

   // 是否显示 Docker 栏图标
   public func setDockIconVisible(_ visible: Bool) {
       dlog("setDockIconVisible \(visible)")
       applyAppAppearanceSetting(onlyShowInMenuBar: !visible)
       UserDefaults.standard.set(!visible, forKey: "isMenuBarOnly")
//       hasOpenedMainWindowOnce = true
   }

   // MARK: - Video Control

   /// 重新加载并播放指定显示器上的视频。
   /// - Parameter sid: 显示器的唯一标识符
   func reloadAndPlayVideo(displayUUID sid: String) {
       dlog("reloadAndPlayVideo displayUUID=\(sid)")
       guard let screen = NSScreen.screen(forUUID: sid),
             let entry = SharedWallpaperWindowManager.shared.screenContent[sid],
             entry.type == .video else {
           SharedWallpaperWindowManager.shared.players[sid]?.play()
           return
       }

       SharedWallpaperWindowManager.shared.showVideo(
           for: screen,
           url: entry.url,
           stretch: entry.stretch,
           volume: entry.volume ?? 1.0,
           allowReuse: false
       )
   }

    func updatePlaybackStateForAllScreens() {
        let pauseAll = shouldPauseAllVideos()
        dlog("[IdlePause] pauseAll=\(pauseAll)")
        for (sid, player) in SharedWallpaperWindowManager.shared.players {
            if pauseAll {
                if player.timeControlStatus != .paused {
                    player.pause()
                }
            } else {
                if player.timeControlStatus != .playing {
                    if player.currentItem != nil {
                        player.play()
                    } else {
                        reloadAndPlayVideo(displayUUID: sid)
                    }
                }
            }
        }
        // 网页中的视频/音频暂停与恢复
        let jsCommand = pauseAll
            ? "document.querySelectorAll('video,audio').forEach(e=>e.pause())"
            : "document.querySelectorAll('video,audio').forEach(e=>e.play())"
        for (_, webView) in SharedWallpaperWindowManager.shared.webViews {
            webView.evaluateJavaScript(jsCommand, completionHandler: nil)
        }
        // 仅在状态变化时才通知 UI 刷新
        if lastPauseAllState != pauseAll {
            lastPauseAllState = pauseAll
            NotificationCenter.default.post(name: Notification.Name("WallpaperContentDidChange"), object: nil)
        }
    }

    /// Determines whether all videos should be paused (e.g., all overlays are fully occluded).
    private func shouldPauseAllVideos() -> Bool {
        // Respect screensaver first
        if isInScreensaver { return false }

        // Fast path for “总是播放”
        switch AppState.shared.playbackMode {
        case .alwaysPlay:
            return false

        case .automatic:
            let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            dlog("testing pause videos or not (automatic) isLowPower=\(isLowPower)")
            if isLowPower {
                // 低电量模式：行为等同省电+（任意遮挡即暂停全部）
                return SharedWallpaperWindowManager.shared.anyOverlayCompletelyCovered()
            } else {
                // 正常电量：行为等同省电（全部遮挡才暂停）
                return SharedWallpaperWindowManager.shared.allOverlaysCompletelyCovered()
            }

        case .powerSave:
            // 省电：所有 overlay 都被完全遮挡才暂停
            return SharedWallpaperWindowManager.shared.allOverlaysCompletelyCovered()

        case .powerSavePlus:
            // 省电+：任意 overlay 被完全遮挡即暂停
            return SharedWallpaperWindowManager.shared.anyOverlayCompletelyCovered()
        
        case .stationary:
            return true
        }
    }
        
    @objc private func powerStateDidChange(_ notification: Notification) {
        dlog("[LowPower] isLowPowerModeEnabled=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
        updatePlaybackStateForAllScreens()
    }

        @objc
    func wallpaperWindowOcclusionDidChange(_: Notification) {
        // 防抖：短时间内只评估一次
        occlusionDebounceWorkItem?.cancel()
        occlusionDebounceWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.updatePlaybackStateForAllScreens()
            }
        }
        // Give the system a longer grace period (0.5 s) before re‑evaluating playback,
        // so that transient occlusion states don't cause premature pauses.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: occlusionDebounceWorkItem!)
        dlog("occlusion change")
    }

    /// Called when a screensaver overlay window's occlusion changes.
    @objc
    private func screensaverOverlayOcclusionChanged(_: Notification) {
        // If no overlay is fully occluded, restart the screensaver timer
        let suppressed = SharedWallpaperWindowManager.shared.screensaverOverlayWindows.values.contains {
            !$0.occlusionState.contains(.visible)
        }
        if !suppressed {
            dlog("screensaver overlay no longer fully covered, restarting timer")
            startScreensaverTimer()
        }
    }

   // MARK: - NSApplicationDelegate Idle Pause
   func applicationDidBecomeActive(_: Notification) {
       dlog("applicationDidBecomeActive")
       updatePlaybackStateForAllScreens()
   }
   // 从菜单栏打开关于窗口
   @objc func showAboutFromStatus() {
       dlog("showAboutFromStatus")
       desktop_videoApp.shared?.showAboutDialog()
   }
   // 更新时钟标签位置和时间
    private func updateClockLabels() {
        let dateString = formatScreensaverDate()
        let timeString = formatScreensaverTime()

        for screen in NSScreen.screens {
            let sid = screen.dv_displayUUID
            guard let clockWin = clockWindows[sid] else { continue }

            // 使用壁纸窗口或黑色窗口或屏幕本身作为参考尺寸
            let contentBounds: NSRect
            if let wallpaperWindow = SharedWallpaperWindowManager.shared.windowControllers[sid]?.window {
                contentBounds = wallpaperWindow.contentView?.bounds ?? wallpaperWindow.frame
            } else if let blackWin = screensaverBlackWindows[sid] {
                contentBounds = blackWin.contentView?.bounds ?? blackWin.frame
            } else {
                contentBounds = CGRect(origin: .zero, size: screen.frame.size)
            }

            // 更新高光文字
            if let highlightHost = clockWin.contentView?.subviews.compactMap({ $0 as? NSHostingView<ScreensaverClockHighlight> }).first {
                highlightHost.rootView = ScreensaverClockHighlight(dateText: dateString, timeText: timeString)
                let clockSize = highlightHost.fittingSize
                let originX = (contentBounds.width - clockSize.width) / 2
                let originY = contentBounds.height * clockVerticalPositionFactor - clockSize.height / 2
                let clockFrame = CGRect(origin: CGPoint(x: originX, y: originY), size: clockSize)
                highlightHost.frame = clockFrame

                // 更新 blur 遮罩（仅有壁纸的屏幕才有 blurView）
                // 禁用 CALayer 隐式动画，避免旧遮罩残留（默认 ~0.25s 交叉淡入淡出）
                if let blurView = clockWin.contentView?.subviews.compactMap({ $0 as? NSVisualEffectView }).first {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    blurView.frame = clockFrame
                    let maskImage = renderTextMask(dateText: dateString, timeText: timeString, size: clockSize)
                    blurView.layer?.mask?.frame = blurView.bounds
                    blurView.layer?.mask?.contents = maskImage
                    CATransaction.commit()
                }
            }
        }
    }

    /// Renders clock text into a CGImage for use as a CALayer mask on the blur view.
    /// Uses NSAttributedString drawing instead of SwiftUI snapshot because NSHostingView
    /// renders via CALayer, making cacheDisplay produce a blank bitmap.
    private func renderTextMask(dateText: String, timeText: String, size: CGSize) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        // Match fonts from ScreensaverClockMask / ScreensaverClockHighlight
        let timeFont: NSFont = {
            let base = NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .regular)
            if let desc = base.fontDescriptor.withDesign(.rounded) {
                return NSFont(descriptor: desc, size: 96) ?? base
            }
            return base
        }()
        let dateFont: NSFont = {
            let base = NSFont.systemFont(ofSize: 28, weight: .semibold)
            if let desc = base.fontDescriptor.withDesign(.rounded) {
                return NSFont(descriptor: desc, size: 28) ?? base
            }
            return base
        }()

        let para = NSMutableParagraphStyle()
        para.alignment = .center

        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: timeFont, .foregroundColor: NSColor.white, .paragraphStyle: para
        ]
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: dateFont, .foregroundColor: NSColor.white, .paragraphStyle: para
        ]

        let timeTextSize = (timeText as NSString).boundingRect(
            with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: timeAttrs
        ).size
        let dateTextSize = (dateText as NSString).boundingRect(
            with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: dateAttrs
        ).size

        let spacing: CGFloat = 8
        let totalH = timeTextSize.height + spacing + dateTextSize.height

        // Draw into NSImage (transparent background; CALayer mask uses alpha channel)
        let image = NSImage(size: size)
        image.lockFocus()

        // Non-flipped coordinates: y=0 at bottom, time on top, date below
        let centerY = size.height / 2
        let timeY = centerY + totalH / 2 - timeTextSize.height
        let dateY = centerY - totalH / 2

        (timeText as NSString).draw(
            in: CGRect(x: 0, y: timeY, width: size.width, height: timeTextSize.height),
            withAttributes: timeAttrs
        )
        (dateText as NSString).draw(
            in: CGRect(x: 0, y: dateY, width: size.width, height: dateTextSize.height),
            withAttributes: dateAttrs
        )

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }
   // MARK: - External Screensaver Suppression
   @objc private func handleExternalScreensaverActive(_: Notification) {
       dlog("handleExternalScreensaverActive")
       otherAppSuppressScreensaver = true
       // 若计时器存在则取消
       screensaverTimer?.invalidate()
       screensaverTimer = nil
   }

   @objc private func handleExternalScreensaverInactive(_: Notification) {
       dlog("handleExternalScreensaverInactive")
       otherAppSuppressScreensaver = false
       // 如有必要重新启动计时器
       startScreensaverTimer()
   }
}



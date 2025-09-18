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
   /// Token to keep the system awake while screensaver videos play
   private var systemSleepActivity: NSObjectProtocol?
   // 屏保模式下的时钟标签
   private var clockDateLabels: [NSTextField] = []
   private var clockTimeLabels: [NSTextField] = []
   private var clockTimer: Timer?
   // macOS 26+ SwiftUI Liquid Glass hosts (store as NSView for cross-version compile)
   private var clockDateGlassHosts: [NSView] = []
   private var clockTimeGlassHosts: [NSView] = []
   // Combined date+time Liquid Glass hosts (macOS 26+)
   private var clockCombinedGlassHosts: [NSView] = []
   private var didLogLiquidGlassForScreens: Set<String> = []
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
       //debug settings
//      var delaySeconds = 10
//       dlog("Warning! Debug settings on !!!")

       screensaverTimer = Timer.scheduledTimer(withTimeInterval: delaySeconds / 5, repeats: true) { [weak self] _ in
           Task { @MainActor [weak self] in
               guard let self else { return }
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

       // 使用现有窗口列表的键值
       let keys = NSScreen.screens.compactMap { screen in
           let id = screen.dv_displayUUID
           return SharedWallpaperWindowManager.shared.windowControllers.keys.contains(id) ? id : nil
       }
       dlog("windowControllers.keys = \(keys)")

       // 隐藏检测窗口，避免屏保模式下触发自动暂停
       for overlay in SharedWallpaperWindowManager.shared.overlayWindows.values {
           overlay.orderOut(nil)
       }
       // 隐藏全屏检测窗口，避免干扰
       for overlay in SharedWallpaperWindowManager.shared.screensaverOverlayWindows.values {
           overlay.orderOut(nil)
       }

       // 1. 提升现有壁纸窗口为屏保窗口，并添加淡入动画
       // 👇 先把需要恢复播放的屏幕 ID 收集起来，稍后统一延迟 5 s 再播放
       var pendingResumeIDs: [String] = []
       for id in keys {
           dlog("looping id = \(id)")
           if let screen = NSScreen.screen(forUUID: id) {
               dlog("found screen: \(screen)")
               guard let wallpaperWindow = SharedWallpaperWindowManager.shared.windowControllers[id]?.window else { continue }
               wallpaperWindow.contentView?.wantsLayer = true  // ensure layer-backed
               wallpaperWindow.level = .screenSaver
               wallpaperWindow.ignoresMouseEvents = false
               wallpaperWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
               wallpaperWindow.alphaValue = 0 // 初始透明
               // 仅将窗口置于最前，不请求键盘焦点以避免系统警告
               wallpaperWindow.orderFront(nil)

               // 使用动画淡入
               NSAnimationContext.runAnimationGroup({ context in
                   context.duration = 0.5
                   wallpaperWindow.animator().alphaValue = 1
               }, completionHandler: nil)

               // 👉 收集待恢复播放的屏幕，稍后统一处理
               pendingResumeIDs.append(id)

               if #available(macOS 26.0, *) {
                   // ===== SwiftUI Liquid Glass combined label (macOS 26+) =====
                   let dateFormatter = DateFormatter()
                   dateFormatter.locale = Locale.current
                   dateFormatter.dateFormat = "EEEE, yyyy-MM-dd"
                   let dateText = dateFormatter.string(from: Date())

                   let timeFormatter = DateFormatter()
                   timeFormatter.locale = Locale.current
                   timeFormatter.dateFormat = "HH:mm:ss"
                   let timeText = timeFormatter.string(from: Date())

                   // Create ONE combined hosting view with a newline between date and time
                   let combinedHost = NSHostingView(rootView: CombinedGlassClock(
                       dateText: dateText,
                       timeText: timeText
                   ))

                   // Size to fit SwiftUI content
                   let combinedSize = combinedHost.fittingSize
                   combinedHost.frame.size = combinedSize

                   // Ensure overlay renders above the video view
                   combinedHost.wantsLayer = true
                   combinedHost.layer?.zPosition = 100

                   if let contentBounds = wallpaperWindow.contentView?.bounds {
                       // Place roughly where the previous date+time block would sit
                       let originX = (contentBounds.width - combinedSize.width) / 2
                       let originY = contentBounds.height * 4/5 - combinedSize.height / 2
                       combinedHost.frame.origin = CGPoint(x: originX, y: originY)
                   }

                   wallpaperWindow.contentView?.addSubview(combinedHost, positioned: .above, relativeTo: nil)
                   clockCombinedGlassHosts.append(combinedHost)
                   if !didLogLiquidGlassForScreens.contains(id) {
                       let screenName = NSScreen.screen(forUUID: id)?.dv_localizedName ?? id
                       dlog("[LiquidGlass] Enabled for screen: \(screenName) (\(id))")
                       didLogLiquidGlassForScreens.insert(id)
                   }
               } else {
                   // ===== Fallback: AppKit labels for older macOS =====
                   // 添加日期文本
                   let dateLabel = NSTextField(labelWithString: "")
                   configureScreensaverDateLabel(dateLabel)
                   let dateFormatter = DateFormatter()
                   dateFormatter.locale = Locale.current
                   dateFormatter.dateFormat = "EEEE, yyyy-MM-dd"
                   dateLabel.stringValue = dateFormatter.string(from: Date())
                   dateLabel.sizeToFit()
                   applyScreensaverLabelPadding(dateLabel)
                   // 根据窗口内容视图计算标签位置
                   if let contentBounds = wallpaperWindow.contentView?.bounds {
                       // place at top 1/5 of view, horizontally centered
                       let dateX = (contentBounds.width - dateLabel.frame.width) / 2
                       let dateY = contentBounds.height * 4/5 - dateLabel.frame.height / 2
                       dateLabel.frame.origin = CGPoint(x: dateX, y: dateY)
                   }
                   wallpaperWindow.contentView?.addSubview(dateLabel, positioned: .above, relativeTo: nil)
                   clockDateLabels.append(dateLabel)

                   // 添加时间文本，位于日期标签下方约两倍高度处
                   let timeLabel = NSTextField(labelWithString: "")
                   configureScreensaverTimeLabel(timeLabel)
                   timeLabel.sizeToFit()
                   applyScreensaverLabelPadding(timeLabel, horizontal: 40, vertical: 20)
                   // 根据窗口内容视图计算标签位置
                   if let contentBounds = wallpaperWindow.contentView?.bounds {
                       // 使用和 updateClockLabels 相同的逻辑：日期标签下方，间隔10点
                       let dateY = dateLabel.frame.origin.y
                       let timeX = contentBounds.midX - timeLabel.frame.width / 2
                       let timeY = dateY - timeLabel.frame.height / 1.5 - dateLabel.frame.height
                       timeLabel.frame.origin = CGPoint(x: timeX, y: timeY)
                   }
                   wallpaperWindow.contentView?.addSubview(timeLabel, positioned: .above, relativeTo: nil)
                   timeLabel.wantsLayer = true
                   timeLabel.layer?.zPosition = 10_000
                   dateLabel.wantsLayer = true
                   dateLabel.layer?.zPosition = 10_000
                   clockTimeLabels.append(timeLabel)
                   // Ensure dateLabel is above all (bring to front)
                   wallpaperWindow.contentView?.addSubview(dateLabel, positioned: .above, relativeTo: nil)
               }
           } else {
               dlog("no NSScreen found forDisplayID \(id), skipping")
               continue
           }
       }

       // === 立即恢复各屏幕的视频播放 ===
       for pid in pendingResumeIDs {
           reloadAndPlayVideo(displayUUID: pid)
       }
       // Bring clock overlays to the front in case the video view was reinserted above them
       bringClockOverlaysToFront()

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
       for label in clockDateLabels {
           label.removeFromSuperview()
       }
       clockDateLabels.removeAll()
       for label in clockTimeLabels {
           label.removeFromSuperview()
       }
       clockTimeLabels.removeAll()
       if #available(macOS 26.0, *) {
           for host in clockDateGlassHosts { host.removeFromSuperview() }
           clockDateGlassHosts.removeAll()
           for host in clockTimeGlassHosts { host.removeFromSuperview() }
           clockTimeGlassHosts.removeAll()
           for host in clockCombinedGlassHosts { host.removeFromSuperview() }
           clockCombinedGlassHosts.removeAll()
       }

       // 1. 对每个窗口执行淡出动画后再恢复
       for (_, wallpaperWindowController) in SharedWallpaperWindowManager.shared.windowControllers {
           guard let wallpaperWindow = wallpaperWindowController.window else { continue }
           NSAnimationContext.runAnimationGroup({ context in
               context.duration = 0.5
               wallpaperWindow.animator().alphaValue = 0
           }, completionHandler: {
               wallpaperWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
               wallpaperWindow.ignoresMouseEvents = true
               wallpaperWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
               wallpaperWindow.orderBack(nil)
               wallpaperWindow.alphaValue = 1 // 恢复透明度供下一次屏保使用
           })
       }

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
                self.toggleMainWindow()
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
        let hasVideoContent = SharedWallpaperWindowManager.shared.screenContent.contains { _, entry in
            entry.type == .video
        }
        guard hasVideoContent else {
            dlog("manualRunScreensaver aborted: no video content available", level: .info)
            return
        }
        // 若用户在偏好里关闭了屏保，也顺便帮他打开
        if !UserDefaults.standard.bool(forKey: screensaverEnabledKey) {
            UserDefaults.standard.set(true, forKey: screensaverEnabledKey)
        }
        runScreenSaver()    // 已有方法，直接复用
    }

   /// 根据当前壁纸内容启用或禁用菜单栏中的屏保按钮
   private func updateScreensaverMenuItemState() {
       let hasVideoContent = SharedWallpaperWindowManager.shared.screenContent.contains { _, entry in
           entry.type == .video
       }
       dlog("updateScreensaverMenuItemState hasVideoContent=\(hasVideoContent)", level: .info)
       startScreensaverMenuItem?.isEnabled = hasVideoContent
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
                        let time = player.currentItem!.currentTime()
                        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            player.play()
                        }
                    } else {
                        reloadAndPlayVideo(displayUUID: sid)
                    }
                }
            }
        }
        NotificationCenter.default.post(name: Notification.Name("WallpaperContentDidChange"), object: nil)
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
            dlog("testing pause videos or not (automatic)")

            let overlaysDict = SharedWallpaperWindowManager.shared.overlayWindows
            guard !overlaysDict.isEmpty else { return false }

            let pauseAll = overlaysDict.values.allSatisfy { !$0.occlusionState.contains(.visible) }

            if !pauseAll {
                // 列出仍可见的屏幕，便于调试
                var visibleScreens: [String] = []
                for (sid, win) in overlaysDict where win.occlusionState.contains(.visible) {
                    if let screen = NSScreen.screen(forUUID: sid) {
                        visibleScreens.append(screen.dv_localizedName)
                    }
                }
                dlog("[IdlePause] overlay still visible on screens: \(visibleScreens.joined(separator: ", "))")
            }
            return pauseAll

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
        dlog("updateClockLabels")
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "EEEE, yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: Date())

        if #available(macOS 26.0, *) {
            // Update combined SwiftUI Liquid Glass hosts
            for (index, anyHost) in clockCombinedGlassHosts.enumerated() {
                guard index < NSScreen.screens.count else { continue }
                guard let host = anyHost as? NSHostingView<CombinedGlassClock> else { continue }

                let screen = NSScreen.screens[index]
                let sid = screen.dv_displayUUID
                if let window = SharedWallpaperWindowManager.shared.windowControllers[sid]?.window,
                   let contentBounds = window.contentView?.bounds {
                    // Rebuild root view with new two-line content
                    host.rootView = CombinedGlassClock(
                        dateText: dateString,
                        timeText: timeString
                    )

                    let combinedSize = host.fittingSize
                    host.frame.size = combinedSize

                    let originX = (contentBounds.width - combinedSize.width) / 2
                    let originY = contentBounds.height * 0.875 - combinedSize.height / 2
                    host.frame.origin = CGPoint(x: originX, y: originY)
                }
            }
            // Keep overlays above the video even if the player view reorders
            bringClockOverlaysToFront()
            return
        }

        // Legacy AppKit path
        for (index, dateLabel) in clockDateLabels.enumerated() {
            guard index < clockTimeLabels.count, index < NSScreen.screens.count else { continue }
            let timeLabel = clockTimeLabels[index]
            let screen = NSScreen.screens[index]
            let sid = screen.dv_displayUUID
            if let window = SharedWallpaperWindowManager.shared.windowControllers[sid]?.window,
               let contentBounds = window.contentView?.bounds {
                configureScreensaverDateLabel(dateLabel)
                dateLabel.stringValue = dateString
                dateLabel.sizeToFit()
                applyScreensaverLabelPadding(dateLabel)
                let dateX = (contentBounds.width - dateLabel.frame.width) / 2
                let dateY = contentBounds.height * 9/10 - dateLabel.frame.height / 2
                dateLabel.frame.origin = CGPoint(x: dateX, y: dateY)

                configureScreensaverTimeLabel(timeLabel)
                timeLabel.stringValue = timeString
                timeLabel.sizeToFit()
                applyScreensaverLabelPadding(timeLabel, horizontal: 40, vertical: 20)
                let timeX = contentBounds.midX - timeLabel.frame.width / 2
                let timeY = dateY - dateLabel.frame.height - timeLabel.frame.height / 1.5
                timeLabel.frame.origin = CGPoint(x: timeX, y: timeY)
            }
        }
        // Keep overlays above the video even if the player view reorders
        bringClockOverlaysToFront()
    }

    /// Re-adds clock overlays at the top of the z-order to ensure they are above the video.
    private func bringClockOverlaysToFront() {
        // SwiftUI hosts (macOS 26+)
        if #available(macOS 26.0, *) {
            for (index, host) in clockCombinedGlassHosts.enumerated() {
                guard index < NSScreen.screens.count else { continue }
                let sid = NSScreen.screens[index].dv_displayUUID
                if let window = SharedWallpaperWindowManager.shared.windowControllers[sid]?.window {
                    host.wantsLayer = true
                    host.layer?.zPosition = 10_000
                    window.contentView?.addSubview(host, positioned: .above, relativeTo: nil)
                }
            }
            for (index, host) in clockDateGlassHosts.enumerated() {
                guard index < NSScreen.screens.count else { continue }
                let sid = NSScreen.screens[index].dv_displayUUID
                if let window = SharedWallpaperWindowManager.shared.windowControllers[sid]?.window {
                    host.wantsLayer = true
                    host.layer?.zPosition = 10_000
                    window.contentView?.addSubview(host, positioned: .above, relativeTo: nil)
                }
            }
            for (index, host) in clockTimeGlassHosts.enumerated() {
                guard index < NSScreen.screens.count else { continue }
                let sid = NSScreen.screens[index].dv_displayUUID
                if let window = SharedWallpaperWindowManager.shared.windowControllers[sid]?.window {
                    host.wantsLayer = true
                    host.layer?.zPosition = 10_000
                    window.contentView?.addSubview(host, positioned: .above, relativeTo: nil)
                }
            }
        }
        // Legacy AppKit labels
        for (index, label) in clockDateLabels.enumerated() {
            guard index < NSScreen.screens.count else { continue }
            let sid = NSScreen.screens[index].dv_displayUUID
            if let window = SharedWallpaperWindowManager.shared.windowControllers[sid]?.window {
                label.wantsLayer = true
                label.layer?.zPosition = 10_000
                window.contentView?.addSubview(label, positioned: .above, relativeTo: nil)
            }
        }
        for (index, label) in clockTimeLabels.enumerated() {
            guard index < NSScreen.screens.count else { continue }
            let sid = NSScreen.screens[index].dv_displayUUID
            if let window = SharedWallpaperWindowManager.shared.windowControllers[sid]?.window {
                label.wantsLayer = true
                label.layer?.zPosition = 10_000
                window.contentView?.addSubview(label, positioned: .above, relativeTo: nil)
            }
        }
    }
    private func configureScreensaverDateLabel(_ label: NSTextField) {
        label.font = NSFont(name: "DIN Alternate", size: 30) ?? NSFont.systemFont(ofSize: 30, weight: .medium)
        label.textColor = .labelColor
        label.drawsBackground = true
        label.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.9)
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 12
        label.layer?.masksToBounds = true
        label.layer?.zPosition = 100
        label.lineBreakMode = .byWordWrapping
    }

    private func configureScreensaverTimeLabel(_ label: NSTextField) {
        label.font = NSFont(name: "DIN Alternate", size: 100) ?? NSFont.systemFont(ofSize: 100, weight: .light)
        label.textColor = .labelColor
        label.drawsBackground = true
        label.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.9)
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 12
        label.layer?.masksToBounds = true
        label.layer?.zPosition = 100
        label.lineBreakMode = .byClipping
    }

    private func applyScreensaverLabelPadding(
        _ label: NSTextField,
        horizontal: CGFloat = 24,
        vertical: CGFloat = 10
    ) {
        var frame = label.frame
        frame.origin.x -= horizontal
        frame.origin.y -= vertical
        frame.size.width += horizontal * 2
        frame.size.height += vertical * 2
        label.frame = frame
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

// MARK: - SwiftUI GlassLabel for macOS
//#if canImport(SwiftUI)
struct GlassLabel: View {
    var text: String
    var font: Font
    var hPad: CGFloat
    var vPad: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            Text(text)
                .font(font)
                .foregroundStyle(.primary)
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .glassEffect(.clear, in: shape)
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(.primary)
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .modifier(GlassCompat(shape: shape))
        }
    }
}

@available(macOS 26.0, *)
struct CombinedGlassClock: View {
    var dateText: String
    var timeText: String
    var body: some View {
        VStack(spacing: 8) {
            Text(dateText)
                .font(.system(size: 36, weight: .medium))
            Text(timeText)
                .font(.system(size: 100, weight: .light))
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A compatibility modifier that applies real Liquid Glass on new SDKs,
/// and falls back to Material on older SDKs.
private struct GlassCompat<S: Shape>: ViewModifier {
    var shape: S
    func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(macOS 26.0, *) {
            // Use the more transparent .clear variant of Liquid Glass
            content
                .glassEffect(.clear, in: shape)
        } else {
            // Fallback: use a thinner, more transparent material
            content.background(.ultraThinMaterial, in: shape)
        }
        #else
        content.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

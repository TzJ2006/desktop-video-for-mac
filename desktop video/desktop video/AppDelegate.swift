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

// Import localization function if needed
// If not already defined somewhere, uncomment the following line:
// func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

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
    }

    // 打开主控制器界面
    @objc func toggleMainWindow() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        // 如果已经有窗口了就不新建窗口
        if let win = self.window {
            win.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow()
        }
    }

    @objc func openPreferences() {
        if let win = preferencesWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let prefsView = PreferencesView()
            let hosting = NSHostingController(rootView: prefsView)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 250),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = NSLocalizedString("PreferencesTitle", comment: "")
            win.contentView = hosting.view
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            preferencesWindow = win
        }
    }

    // 关闭窗口
    func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win == self.window {
            self.window = nil
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
                    withTitle: NSLocalizedString("Open Main Window", comment: ""),
                    action: #selector(toggleMainWindow),
                    keyEquivalent: ""
                )
                menu.addItem(
                    withTitle: NSLocalizedString("Preferences...", comment: ""),
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
            for (screen, player) in SharedWallpaperWindowManager.shared.players {
                if self.shouldPauseVideo(on: screen) {
                    player.pause()
                } else {
                    player.play()
                }
            }
        }
    }

    private func pauseVideoForAllScreens() {
        for (screen, player) in SharedWallpaperWindowManager.shared.players {
            if shouldPauseVideo(on: screen) {
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
        guard SharedWallpaperWindowManager.shared.windows[screen] != nil else {
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
        for (screen, player) in SharedWallpaperWindowManager.shared.players {
            if shouldPauseVideo(on: screen) {
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
}

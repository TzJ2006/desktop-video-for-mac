//
//  AppDelegate.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/25/25.
//

import AppKit
import SwiftUI
import AVFoundation

// AppDelegate: APP 启动项管理，启动 APP 的时候会先运行 AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    static var shared: AppDelegate!
    var window: NSWindow?
    var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?

    // window: 主窗口，用于显示壁纸
    // statusItem: True则显示菜单栏图标，否则显示Docker栏图标
    
    private var lastAppearanceChangeTime: Date = .distantPast
    private var appearanceChangeWorkItem: DispatchWorkItem?
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
                    withTitle: NSLocalizedString("Open Main Window", comment: ""),
                    action: #selector(toggleMainWindow),
                    keyEquivalent: ""
                )
                menu.addItem(
                    withTitle: NSLocalizedString("Preferences...", comment: ""),
                    action: #selector(openPreferences),
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
}

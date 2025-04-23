//
//  AppDelegate.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/25/25.
//

import AppKit
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    
    var statusItem: NSStatusItem?

//    func applicationWillFinishLaunching(_ notification: Notification) {
//        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
//        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
//    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // ✅ 在启动时设置 activationPolicy，避免运行时频繁切换导致多 PID 图标问题
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        let showMenuBar = UserDefaults.standard.bool(forKey: "showMenuBarIcon")

        NSApp.setActivationPolicy(showDock ? .regular : .accessory)

        if showDock {
            NSApp.activate(ignoringOtherApps: true)
        }

        if showMenuBar {
            StatusBarController.shared.updateStatusItemVisibility()
        } else {
            StatusBarController.shared.removeStatusItem()
        }

        openMainWindow()
        SharedWallpaperWindowManager.shared.restoreFromBookmark()
    }
    
    @objc func toggleMainWindow() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if let win = self.window {
            win.makeKeyAndOrderFront(nil)
        }
    }

    var window: NSWindow?

    var globalMute: Bool {
        get { UserDefaults.standard.bool(forKey: "globalMute") }
        set { UserDefaults.standard.set(newValue, forKey: "globalMute") }
    }

    func windowWillClose(_ notification: Notification) {
//        print("🚪 windowWillClose 被调用了")
        if let win = notification.object as? NSWindow, win == self.window {
            self.window = nil
//            print("✅ 已清空 self.window")
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag || window == nil || !window!.isVisible {
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            openMainWindow()
        }
        return true
    }

    func openMainWindow() {
        if let win = self.window {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.makeKeyAndOrderFront(nil)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        let contentView = ContentView()
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.center()
        newWindow.title = "桌面壁纸控制器"
        newWindow.contentView = NSHostingView(rootView: contentView)

        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)

        self.window = newWindow
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}

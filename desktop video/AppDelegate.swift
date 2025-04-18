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
    static let shared = AppDelegate.sharedInstance
    static let sharedInstance = AppDelegate()

    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureAudioSession()
        openMainWindow()
        SharedWallpaperWindowManager.shared.restoreFromBookmark()
    }

    func windowWillClose(_ notification: Notification) {
        print("🚪 windowWillClose 被调用了")
        if let win = notification.object as? NSWindow, win == self.window {
            self.window = nil
            print("✅ 已清空 self.window")
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag || window == nil || !window!.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            openMainWindow()
        }
        return true
    }

    func openMainWindow() {
        if self.window == nil || (window != nil && !window!.isVisible) {
            // 如果 window 不存在或不可见，就创建一个新的
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
        } else {
            if let win = window, win.isMiniaturized {
                win.deminiaturize(nil)
            }
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func configureAudioSession() {
    print("ℹ️ macOS does not use AVAudioSession. Skipping audio session configuration.")
    }
}

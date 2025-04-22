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

    func applicationWillFinishLaunching(_ notification: Notification) {
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

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
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    var window: NSWindow?

    var globalMute: Bool {
        get { UserDefaults.standard.bool(forKey: "globalMute") }
        set { UserDefaults.standard.set(newValue, forKey: "globalMute") }
    }

//    var autoFill: Bool {
//        get { UserDefaults.standard.bool(forKey: "autoFill") }
//        set {
//            UserDefaults.standard.set(newValue, forKey: "autoFill")
//            syncAutoFillToAllControllers()
//        }
//    }

//    func syncAutoFillToAllControllers() {
//        for (screen, entry) in SharedWallpaperWindowManager.shared.screenContent {
//            switch entry.type {
//            case .image:
//                SharedWallpaperWindowManager.shared.updateImageStretch(stretch: self.autoFill)
//            case .video:
//                SharedWallpaperWindowManager.shared.updateVideoSettings(
//                    stretch: self.autoFill,
//                    volume: entry.volume ?? 1.0
//                )
//            }
//        }
//    }

    func windowWillClose(_ notification: Notification) {
//        print("🚪 windowWillClose 被调用了")
        if let win = notification.object as? NSWindow, win == self.window {
            self.window = nil
//            print("✅ 已清空 self.window")
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

//    func configureAudioSession() {
//    print("ℹ️ macOS does not use AVAudioSession. Skipping audio session configuration.")
//    }
}

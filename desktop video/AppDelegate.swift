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

    private var appearanceChangeWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        SharedWallpaperWindowManager.shared.restoreFromBookmark()

        // Move checkbox simulation logic here, after windows have loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
    
    @objc func toggleMainWindow() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if let win = self.window {
            win.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow()
        }
    }

    var window: NSWindow?

    var globalMute: Bool {
        get { UserDefaults.standard.bool(forKey: "globalMute") }
        set { UserDefaults.standard.set(newValue, forKey: "globalMute") }
    }

    func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win == self.window {
            self.window = nil
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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 325),
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
    
    private var lastAppearanceChangeTime: Date = .distantPast

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

    func setupStatusBarIcon() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = statusItem?.button {
                button.image = NSImage(named: "MenuBarIcon")
                button.image?.isTemplate = true
                button.action = #selector(statusBarIconClicked)
                button.target = self
            }
        }
    }

    @objc func statusBarIconClicked() {
        toggleMainWindow()
    }

    func removeStatusBarIcon() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    public func setDockIconVisible(_ visible: Bool) {
        applyAppAppearanceSetting(onlyShowInMenuBar: !visible)
        UserDefaults.standard.set(!visible, forKey: "isMenuBarOnly")
    }
}

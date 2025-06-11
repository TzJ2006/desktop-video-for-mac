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
import Foundation


// AppDelegate: APP 启动项管理，启动 APP 的时候会先运行 AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

   static var shared: AppDelegate!
   var window: NSWindow?
   private var preferencesWindow: NSWindow?

   func applicationDidFinishLaunching(_ notification: Notification) {
       dlog("applicationDidFinishLaunching")
       AppDelegate.shared = self

       // 从书签中恢复窗口
       SharedWallpaperWindowManager.shared.restoreFromBookmark()
       
       // 切换 Dock 图标或仅菜单栏模式
       DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
           let showOnlyInMenuBar = UserDefaults.standard.bool(forKey: "isMenuBarOnly")
           self.setDockIconVisible(true)
           if showOnlyInMenuBar {
               self.setDockIconVisible(!showOnlyInMenuBar)
           }
           // 始终使用 toggleMainWindow() 保证在隐藏 Dock 图标后窗口重新置顶
           self.toggleMainWindow()
       }
       ScreensaverManager.shared.startTimer()
       SharedWallpaperWindowManager.shared.pauseVideoForAllScreens()
       self.toggleMainWindow()
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

   // 是否显示 Docker 栏图标
  public func setDockIconVisible(_ visible: Bool) {
      AppAppearanceManager.shared.setDockIconVisible(visible)
  }

   // 应用重新获得焦点时重新评估暂停逻辑
   func applicationDidBecomeActive(_ notification: Notification) {
       dlog("applicationDidBecomeActive")
       SharedWallpaperWindowManager.shared.pauseVideoForAllScreens()
   }

}

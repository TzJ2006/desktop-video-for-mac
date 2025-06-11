//
//  AppAppearanceManager.swift
//  desktop video
//
//  Created by ChatGPT on 2025-06-12.
//

import AppKit
import SwiftUI

/// 管理 Dock 图标与菜单栏图标的显示
class AppAppearanceManager {
    static let shared = AppAppearanceManager()

    private var statusItem: NSStatusItem?
    private var lastAppearanceChangeTime: Date = .distantPast
    private var appearanceChangeWorkItem: DispatchWorkItem?

    private init() {
        dlog("AppAppearanceManager init")
    }

    /// 根据设置切换 Dock 图标或菜单栏模式
    func applyAppAppearanceSetting(onlyShowInMenuBar: Bool) {
        dlog("applyAppAppearanceSetting onlyShowInMenuBar=\(onlyShowInMenuBar)")
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

    /// 在菜单栏显示图标
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
                    action: #selector(AppDelegate.toggleMainWindow),
                    keyEquivalent: ""
                )
                menu.addItem(
                    withTitle: NSLocalizedString(L("Preferences"), comment: ""),
                    action: #selector(AppDelegate.openPreferences),
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

    /// 移除菜单栏图标
    func removeStatusBarIcon() {
        dlog("removeStatusBarIcon")
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// 点击菜单栏图标后的动作
    @objc func statusBarIconClicked() {
        dlog("statusBarIconClicked")
        AppDelegate.shared?.toggleMainWindow()
    }

    /// 控制 Dock 图标显示与否
    func setDockIconVisible(_ visible: Bool) {
        dlog("setDockIconVisible \(visible)")
        applyAppAppearanceSetting(onlyShowInMenuBar: !visible)
        UserDefaults.standard.set(!visible, forKey: "isMenuBarOnly")
    }

    /// 提供给菜单栏 About 按钮调用
    @objc func showAboutFromStatus() {
        dlog("showAboutFromStatus")
        desktop_videoApp.shared?.showAboutDialog()
    }
}

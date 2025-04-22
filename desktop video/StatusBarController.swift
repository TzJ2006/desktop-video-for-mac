//
//  StatusBarController.swift
//  desktop video
//
//  Created by 汤子嘉 on 4/22/25.
//

import AppKit

class StatusBarController {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?

    private init() {
        if UserDefaults.standard.bool(forKey: "showMenuBarIcon") {
            addStatusItem()
        }
    }

    func addStatusItem() {
        removeStatusItem() // Prevent duplicates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func updateStatusItemVisibility() {
        let shouldShow = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        let isVisible = statusItem != nil
        if shouldShow && !isVisible {
            addStatusItem()
        } else if !shouldShow && isVisible {
            removeStatusItem()
        }
    }

    @objc private func statusBarButtonClicked() {
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.shared.openMainWindow()
    }

    private func constructMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        return menu
    }

    @objc private func openSettings() {
        AppDelegate.shared.openMainWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

//
//  desktop_videoApp.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/20/25.
//

import SwiftUI
import ServiceManagement

@main
struct desktop_videoApp: App {
    
    static var shared: desktop_videoApp!
    init() {
        Self.shared = self
    }
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("autoSyncNewScreens") var autoSyncNewScreens: Bool = true  // Added to fix missing declaration
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = true // 新增：记录开机启动状态
    @AppStorage("globalMute") var globalMute: Bool = false
    // globalMute: True则静音所有视频，如果调整某视频音量则自动取消
    
    /// Unified handler for toggling the global‑mute switch.
    /// Writes the new flag, mutes all screens only when `enabled == true`,
    /// then notifies all views to refresh.
    static func applyGlobalMute(_ enabled: Bool) {
        // ① persist the new value
        shared.globalMute = enabled

        // ② side‑effects
        if enabled {
            // Turning ON: save & mute every screen
            SharedWallpaperWindowManager.shared.muteAllScreens()
        } else {
            // Turning OFF: restore previous volumes
            SharedWallpaperWindowManager.shared.restoreAllScreens()
        }

        // ③ broadcast so every SingleScreenView updates immediately
        NotificationCenter.default.post(
            name: Notification.Name("WallpaperContentDidChange"),
            object: nil
        )
    }
    
    var body: some Scene {
        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("自动同步新插入的显示器", isOn: $autoSyncNewScreens)
                Toggle("开机自启动", isOn: $launchAtLogin)
                Toggle("全局静音", isOn: $globalMute)
                    .onChange(of: globalMute) { newValue in
                        desktop_videoApp.applyGlobalMute(newValue)
                    }
            }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Toggle("自动同步新插入的显示器", isOn: $autoSyncNewScreens)
                Toggle("开机自启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        // 弹窗提示
                        let alert = NSAlert()
                        alert.messageText = "设置开机启动失败"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.runModal()

                        // 取消勾选（恢复状态）
                        launchAtLogin = false
                    }
                }
                Toggle("全局静音", isOn: $globalMute)
                    .onChange(of: globalMute) { newValue in
                        desktop_videoApp.applyGlobalMute(newValue)
                    }
            }
            
            CommandGroup(replacing: .appInfo) {
                Button("About Desktop Video") {
                    let alert = NSAlert()
                    alert.messageText = ""
                    alert.icon = NSImage(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "512", ofType: "png") ?? ""))
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                    alert.informativeText = """
                    Desktop Video Wallpaper
                    Version \(version) (\(build))

                    Presented by TzJ
                    Created Just For You~
                    """
                    alert.runModal()
                }
            }
        }
    }
}

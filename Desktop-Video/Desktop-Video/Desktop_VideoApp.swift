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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage("useMemoryCache") var useMemoryCache: Bool = true  // Global setting
    @AppStorage("autoSyncNewScreens") var autoSyncNewScreens: Bool = true  // Added to fix missing declaration
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = true // 新增：记录开机启动状态

    var body: some Scene {
        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("开启视频缓存", isOn: $useMemoryCache)
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
            }
            .padding()
            .frame(width: 320)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Toggle("开启视频缓存", isOn: $useMemoryCache)
                Toggle("自动同步新插入的显示器", isOn: $autoSyncNewScreens)
                Toggle("开机自启动", isOn: $launchAtLogin)
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
                    Created Just For You
                    """
                    alert.runModal()
                }
            }
        }
    }
}

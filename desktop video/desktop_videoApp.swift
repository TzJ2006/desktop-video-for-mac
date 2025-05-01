//
//  desktop_videoApp.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/20/25.
//

import SwiftUI

@main
struct desktop_videoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("useMemoryCache") var useMemoryCache: Bool = true  // Global setting
    var body: some Scene {
        Settings {
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Toggle("开启视频缓存", isOn: $useMemoryCache)
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
                    """
                    alert.runModal()
                }
            }
        }
    }
}

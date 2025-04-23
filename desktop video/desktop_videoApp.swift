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
    var body: some Scene {
        Settings {
            VStack {
                Toggle("仅显示在菜单栏（隐藏 Dock）", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "isMenuBarOnly") },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: "isMenuBarOnly")
                        AppDelegate.shared?.applyAppAppearanceSetting(onlyShowInMenuBar: newValue)
                    }
                ))
                .padding()
            }
            .frame(width: 300, height: 100)
            .onAppear {
                let onlyMenu = UserDefaults.standard.bool(forKey: "isMenuBarOnly")
                AppDelegate.shared?.applyAppAppearanceSetting(onlyShowInMenuBar: onlyMenu)
            }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Desktop Video") {
                    let alert = NSAlert()
                    alert.messageText = ""
                    alert.icon = NSImage(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "512", ofType: "png") ?? ""))
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                    alert.informativeText = """
                    Desktop Video
                    Version \(version) (\(build))
                    
                    Presented by TzJ
                    """
                    alert.runModal()
                }
            }
        }
    }
}

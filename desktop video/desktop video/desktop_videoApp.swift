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
    static var shared: desktop_videoApp?

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // 这些 AppStorage 只在菜单命令里保持最新状态，不直接绑定到 PreferencesView
    @AppStorage("autoSyncNewScreens") private var autoSyncNewScreens: Bool = true
    @AppStorage("launchAtLogin")     private var launchAtLogin:     Bool = true
    @AppStorage("globalMute")        var globalMute:        Bool = false

    init() { Self.shared = self }

    /// 切换静音的统一处理（菜单命令也会调用）
    static func applyGlobalMute(_ enabled: Bool) {
        guard let shared = shared else { return }
        shared.globalMute = enabled
        if enabled {
            SharedWallpaperWindowManager.shared.muteAllScreens()
        } else {
            SharedWallpaperWindowManager.shared.restoreAllScreens()
        }
        NotificationCenter.default.post(
            name: Notification.Name("WallpaperContentDidChange"),
            object: nil
        )
    }

    var body: some Scene {
        Settings {
            // 用一个单独 View 展示所有设置，并延迟到"确认"后才写入 AppStorage
            PreferencesView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("AboutDesktopVideo")) {
                    showAboutDialog()
                }
            }
        }
    }
    
    private func handleLaunchAtLoginChange(_ newValue: Bool) {
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("LaunchAtLoginFailed", comment: "")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
                self.launchAtLogin = false
            }
        }
    }
    
    private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = ""
        
        // Safer icon loading
        if let iconPath = Bundle.main.path(forResource: "512", ofType: "png") {
            alert.icon = NSImage(contentsOfFile: iconPath)
        }
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        alert.informativeText = """
        Desktop Video Wallpaper
        Version \(version) (\(build))

        Presented by TzJ
        Created Just For You~
        """
        alert.runModal()
    }
}


/// **首选项面板**：在 Settings 窗口中显示，修改延迟到"确认"后才写入
struct PreferencesView: View {
    // 真正存储的 AppStorage
    @AppStorage("autoSyncNewScreens") private var autoSyncNewScreensStorage: Bool = true
    @AppStorage("launchAtLogin")     private var launchAtLoginStorage:     Bool = true
    @AppStorage("globalMute")        private var globalMuteStorage:        Bool = false
    @AppStorage("selectedLanguage")  private var languageStorage:          String = "system"

    // 本地 State，用于暂存用户在界面上的修改
    @State private var autoSyncNewScreens: Bool = true
    @State private var launchAtLogin:     Bool = true
    @State private var globalMute:        Bool = false
    @State private var selectedLanguage:  String = "system"

    /// 是否有未保存的更改
    private var hasChanges: Bool {
        autoSyncNewScreens != autoSyncNewScreensStorage
        || launchAtLogin != launchAtLoginStorage
        || globalMute != globalMuteStorage
        || selectedLanguage != languageStorage
    }

    // 注入 LanguageManager
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                Toggle(L("AutoSyncNewScreens"), isOn: $autoSyncNewScreens)
                Toggle(L("LaunchAtLogin"), isOn: $launchAtLogin)
                Toggle(L("GlobalMute"), isOn: $globalMute)
                Text(L("Language"))
                    .font(.headline)
                Picker(selection: $selectedLanguage, label: EmptyView()) {
                    ForEach(SupportedLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                HStack {
                    Button(L("Confirm")) {
                        confirmChanges()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasChanges)
                }
            }
        }
        .frame(minWidth: 240, idealWidth: 320, maxWidth: 480, minHeight: 150, idealHeight: 200, maxHeight: 300)
        .onAppear {
            loadStoredValues()
        }
    }
    
    private func loadStoredValues() {
        autoSyncNewScreens = autoSyncNewScreensStorage
        launchAtLogin = launchAtLoginStorage
        globalMute = globalMuteStorage
        selectedLanguage = languageStorage
    }
    
    private func confirmChanges() {
        // 写回 AppStorage
        autoSyncNewScreensStorage = autoSyncNewScreens
        globalMuteStorage = globalMute
        languageStorage = selectedLanguage
        
        // Handle launch at login separately with error handling
        if launchAtLoginStorage != launchAtLogin {
            handleLaunchAtLoginChange()
        }

        // 静音开关立刻生效
        desktop_videoApp.applyGlobalMute(globalMute)
        // 通知 LanguageManager 刷新
        languageManager.selectedLanguage = selectedLanguage

        // 提示重启
        showRestartAlert()
    }
    
    private func handleLaunchAtLoginChange() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginStorage = launchAtLogin
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("LaunchAtLoginFailed", comment: "")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            // Reset to stored value on failure
            launchAtLogin = launchAtLoginStorage
        }
    }
    
    private func showRestartAlert() {
        let alert = NSAlert()
        alert.messageText = L("RestartRequiredTitle")
        alert.informativeText = L("RestartRequiredMessage")
        alert.alertStyle = .informational
        alert.runModal()
    }
}

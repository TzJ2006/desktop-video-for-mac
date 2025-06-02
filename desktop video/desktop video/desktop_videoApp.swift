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

    // 关联 AppDelegate，所有"打开主窗口"或"打开偏好窗口"逻辑都在 AppDelegate 中处理
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // 这些 AppStorage 只在菜单命令里保持最新状态，不直接绑定到 PreferencesView
    @AppStorage("autoSyncNewScreens") private var autoSyncNewScreens: Bool = true
    @AppStorage("launchAtLogin")     private var launchAtLogin:     Bool = true
    @AppStorage("globalMute")        var globalMute:        Bool = false

    init() {
        Self.shared = self
    }

    var body: some Scene {
        // Add the Settings scene to provide native Settings menu item
        Settings {
        }
        .commands {
            // Replace the About menu item
            CommandGroup(replacing: .appInfo) {
                Button(L("AboutDesktopVideo")) {
                    showAboutDialog()
                }
            }
            
            // Replace the default Settings menu to prevent conflicts
            CommandGroup(replacing: .appSettings) {
                Button(L("Preferences…")) {
                    AppDelegate.openPreferencesWindow() // 调用AppDelegate中的方法
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
    
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

    func showAboutDialog() {
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
    @AppStorage("idlePauseEnabled")  private var idlePauseEnabledStorage:  Bool = false
    @AppStorage("idlePauseSeconds")  private var idlePauseSecondsStorage:  Int = 10
    @AppStorage("screensaverEnabled") private var screensaverEnabledStorage: Bool = false
    @AppStorage("screensaverDelayMinutes") private var screensaverDelayMinutesStorage: Int = 5

    // 本地 State，用于暂存用户在界面上的修改
    @State private var autoSyncNewScreens: Bool = true
    @State private var launchAtLogin:     Bool = true
    @State private var globalMute:        Bool = false
    @State private var selectedLanguage:  String = "system"
    @State private var idlePauseEnabled:  Bool = false
    @State private var idlePauseSeconds:  Int = 10
    @State private var screensaverEnabled: Bool = false
    @State private var screensaverDelayMinutes: Int = 5

    // 原始值缓存，用于恢复
    @State private var originalAutoSyncNewScreens: Bool = true
    @State private var originalLaunchAtLogin:     Bool = true
    @State private var originalGlobalMute:        Bool = false
    @State private var originalSelectedLanguage:  String = "system"
    @State private var originalIdlePauseEnabled:  Bool = false
    @State private var originalIdlePauseSeconds:  Int = 10
    @State private var originalScreensaverEnabled: Bool = false
    @State private var originalScreensaverDelayMinutes: Int = 5

    /// 是否有未保存的更改
    private var hasChanges: Bool {
        autoSyncNewScreens != autoSyncNewScreensStorage
        || launchAtLogin != launchAtLoginStorage
        || globalMute != globalMuteStorage
        || selectedLanguage != languageStorage
        || idlePauseEnabled != idlePauseEnabledStorage
        || idlePauseSeconds != idlePauseSecondsStorage
        || screensaverEnabled != screensaverEnabledStorage
        || screensaverDelayMinutes != screensaverDelayMinutesStorage
    }

    // 注入 LanguageManager
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                Toggle(L("GlobalMute"), isOn: $globalMute)
                Toggle(L("LaunchAtLogin"), isOn: $launchAtLogin)
                Toggle(L("AutoSyncNewScreens"), isOn: $autoSyncNewScreens)

                HStack {
                    Text(L("Language"))
                    Picker(selection: $selectedLanguage, label: EmptyView()) {
                        ForEach(SupportedLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .padding(.top, 10)

                Toggle(L("EnableScreenSaver"), isOn: $screensaverEnabled)
                    .padding(.top, 10)

                HStack {
                    Text(L("ScreenSaverDelay"))
                    TextField("5", value: $screensaverDelayMinutes, formatter: NumberFormatter())
                        .frame(width: 40)
                    Text(L("MinutetoSaver"))
                }
                .disabled(!screensaverEnabled)

                Toggle(L("IdlePauseEnabled"), isOn: $idlePauseEnabled)
                    .padding(.top, 10)

                HStack {
                    Text(L("IdlePauseSeconds"))
                    TextField("5", value: $idlePauseSeconds, formatter: NumberFormatter())
                        .frame(width: 40)
                    Text(L("Seconds"))
                }
                .disabled(!idlePauseEnabled)

                HStack {
                    Button(L("Confirm")) {
                        showRestartAlert()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasChanges)
                }
                .padding(.top, 10)
            }
        }
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .padding(20)
        .onAppear {
            // 首次出现时缓存原始值
            originalAutoSyncNewScreens = autoSyncNewScreensStorage
            originalLaunchAtLogin = launchAtLoginStorage
            originalGlobalMute = globalMuteStorage
            originalSelectedLanguage = languageStorage
            originalIdlePauseEnabled = idlePauseEnabledStorage
            originalIdlePauseSeconds = idlePauseSecondsStorage
            originalScreensaverEnabled = screensaverEnabledStorage
            originalScreensaverDelayMinutes = screensaverDelayMinutesStorage
            loadStoredValues()
        }
    }

    private func loadStoredValues() {
        autoSyncNewScreens = originalAutoSyncNewScreens
        launchAtLogin = originalLaunchAtLogin
        globalMute = originalGlobalMute
        selectedLanguage = originalSelectedLanguage
        idlePauseEnabled = originalIdlePauseEnabled
        idlePauseSeconds = originalIdlePauseSeconds
        screensaverEnabled = originalScreensaverEnabled
        screensaverDelayMinutes = originalScreensaverDelayMinutes
    }

    private func confirmChanges() {
        // 只保存设置到 AppStorage，但不立即应用
        autoSyncNewScreensStorage = autoSyncNewScreens
        launchAtLoginStorage = launchAtLogin
        globalMuteStorage = globalMute
        languageStorage = selectedLanguage
        idlePauseEnabledStorage = idlePauseEnabled
        idlePauseSecondsStorage = idlePauseSeconds
        screensaverEnabledStorage = screensaverEnabled
        screensaverDelayMinutesStorage = screensaverDelayMinutes

        if launchAtLogin != launchAtLoginStorage {
            handleLaunchAtLoginChange()
        }
        
        desktop_videoApp.applyGlobalMute(globalMute)
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

    private func restartApplication() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        NSApp.terminate(nil)
    }
    
    private func showRestartAlert() {
        let alert = NSAlert()
        alert.messageText = L("RestartRequiredTitle")
        alert.informativeText = L("RestartRequiredMessage")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("RestartNow"))
        alert.addButton(withTitle: L("DiscardChange"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 立即重启应用
            confirmChanges()
            restartApplication()
        } else {
            loadStoredValues()
        }
    }
}

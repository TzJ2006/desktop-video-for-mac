import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin")     private var launchAtLogin:     Bool = true
    @AppStorage("selectedLanguage")  private var language:          String = "system"
    @AppStorage("maxVideoFileSizeInGB") private var maxVideoFileSizeInGB: Double = 1.0
    @AppStorage("screensaverEnabled") private var screensaverEnabled: Bool = false
    @AppStorage("screensaverDelayMinutes") private var screensaverDelayMinutes: Double = 5.0

    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    @Environment(\.theme) private var theme

    @State private var originalLaunchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    @State private var originalLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system"
    @State private var originalMaxVideoFileSizeInGB = UserDefaults.standard.double(forKey: "maxVideoFileSizeInGB")
    @State private var originalScreensaverEnabled = UserDefaults.standard.bool(forKey: "screensaverEnabled")
    @State private var originalScreensaverDelayMinutes = UserDefaults.standard.double(forKey: "screensaverDelayMinutes")

    @State private var isReverting = false

    /// 「外观 / 壁纸库排序 / 语言」三个下拉框统一宽度（容纳最长的本地化选项），右对齐。
    private let menuControlWidth: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(L("General"), subtitle: L("GeneralSubtitle")) {
                HeaderHelpButton(LocalizedStringKey(L("Common preferences.")))
            }

            preferencesCard
            // 「将壁纸设为屏保」与「视频缓存上限」并排
            HStack(alignment: .top, spacing: 16) {
                screensaverCard
                storageCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 15))
    }

    // MARK: - 通用偏好

    private var preferencesCard: some View {
        CardSection(title: LocalizedStringKey(L("General")), systemImage: "gearshape") {
            VStack(spacing: 16) {
                // 全局静音 与 登录时启动 并排（一排两个）
                HStack(spacing: 16) {
                    ToggleRow(
                        title: LocalizedStringKey(L("GlobalMute")),
                        value: Binding(
                            get: { appState.isGlobalMuted },
                            set: { desktop_videoApp.applyGlobalMute($0) }
                        )
                    )

                    ToggleRow(title: LocalizedStringKey(L("Launch at login")), value: Binding(
                        get: { launchAtLogin },
                        set: {
                            launchAtLogin = $0
                            if #available(macOS 13.0, *) {
                                do {
                                    if launchAtLogin {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                } catch { /* present alert in real app */ }
                            }
                        }
                    ))
                    .onChange(of: launchAtLogin) { newValue in
                        guard !isReverting else { isReverting = false; return }
                        dlog("launchAtLogin changed to \(newValue), restart required")
                        let previous = originalLaunchAtLogin
                        desktop_videoApp.showRestartAlert {
                            originalLaunchAtLogin = newValue
                        } onDiscard: {
                            isReverting = true
                            launchAtLogin = previous
                            if #available(macOS 13.0, *) {
                                do {
                                    if previous {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                } catch { /* present alert in real app */ }
                            }
                        }
                    }
                }

                Divider()

                // 外观：跟随系统 / 浅色 / 深色，实时生效，无需重启
                settingRow(L("Appearance")) {
                    CenteredMenuPicker(
                        selection: $themeManager.current,
                        options: AppTheme.allCases.map { MenuOption(value: $0, title: $0.displayName) },
                        width: menuControlWidth
                    )
                }

                settingRow(L("LibrarySortOrder")) {
                    CenteredMenuPicker(
                        selection: Binding(
                            get: { appState.librarySortOrder },
                            set: { appState.librarySortOrder = $0 }
                        ),
                        options: AppState.LibrarySortOrder.allCases.map { MenuOption(value: $0, title: $0.description) },
                        width: menuControlWidth
                    )
                }

                settingRow(L("Language")) {
                    CenteredMenuPicker(
                        selection: $language,
                        options: SupportedLanguage.allCases.map { MenuOption(value: $0.rawValue, title: $0.displayName) },
                        width: menuControlWidth
                    )
                }
                .onChange(of: language) { newValue in
                    guard !isReverting else { isReverting = false; return }
                    dlog("language changed to \(newValue), restart required")
                    let previous = originalLanguage
                    desktop_videoApp.showRestartAlert {
                        originalLanguage = newValue
                    } onDiscard: {
                        isReverting = true
                        language = previous
                    }
                }
            }
        }
    }

    // MARK: - 屏幕保护

    private var screensaverCard: some View {
        CardSection(
            title: LocalizedStringKey(L("ScreenSaverTitle")),
            systemImage: "moon.stars",
            trailing: {
                Toggle("", isOn: $screensaverEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: screensaverEnabled) { newValue in
                        guard !isReverting else { isReverting = false; return }
                        dlog("screensaverEnabled changed to \(newValue), restart required")
                        let previous = originalScreensaverEnabled
                        desktop_videoApp.showRestartAlert {
                            originalScreensaverEnabled = newValue
                        } onDiscard: {
                            isReverting = true
                            screensaverEnabled = previous
                        }
                    }
            }
        ) {
            settingRow(L("ScreenSaverDelay")) {
                HStack(spacing: 6) {
                    TextField("5", value: $screensaverDelayMinutes, formatter: NumberFormatter())
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Text(L("MinutetoSaver")).font(.system(size: 13)).foregroundStyle(theme.secondaryText)
                }
            }
            .disabled(!screensaverEnabled)
            .onChange(of: screensaverDelayMinutes) { newValue in
                guard !isReverting else { isReverting = false; return }
                dlog("screensaverDelayMinutes changed to \(newValue), restart required")
                let previous = originalScreensaverDelayMinutes
                desktop_videoApp.showRestartAlert {
                    originalScreensaverDelayMinutes = newValue
                } onDiscard: {
                    isReverting = true
                    screensaverDelayMinutes = previous
                }
            }
        }
    }

    // MARK: - 存储

    private var storageCard: some View {
        CardSection(title: LocalizedStringKey(L("Max video cache (GB)")), systemImage: "internaldrive") {
            // 卡片标题已说明含义，此处只放右对齐的输入框，避免半宽并排时标题重复。
            HStack(spacing: 6) {
                Spacer()
                TextField("1.0", value: $maxVideoFileSizeInGB, formatter: NumberFormatter())
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: maxVideoFileSizeInGB) { newValue in
                        guard !isReverting else { isReverting = false; return }
                        dlog("maxVideoFileSizeInGB changed to \(newValue), restart required")
                        let previous = originalMaxVideoFileSizeInGB
                        desktop_videoApp.showRestartAlert {
                            originalMaxVideoFileSizeInGB = newValue
                        } onDiscard: {
                            isReverting = true
                            maxVideoFileSizeInGB = previous
                        }
                    }
                Text("GB").font(.system(size: 13)).foregroundStyle(theme.secondaryText)
            }
        }
    }

    // MARK: - 行布局

    /// 统一的「左标题 + 右控件」设置行。
    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)   // 半宽并排时换行而非截断
            Spacer(minLength: 8)
            control()
        }
    }
}

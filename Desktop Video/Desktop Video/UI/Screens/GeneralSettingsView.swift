
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("autoSyncNewScreens") private var autoSyncNewScreens: Bool = true
    @AppStorage("launchAtLogin")     private var launchAtLogin:     Bool = true
    @AppStorage("selectedLanguage")  private var language:          String = "system"
    @AppStorage("maxVideoFileSizeInGB") private var maxVideoFileSizeInGB: Double = 1.0
    @AppStorage("globalMute") private var globalMute: Bool = false
    @AppStorage("showMenuBarVideo") private var showMenuBarVideo: Bool = false
    @AppStorage("screensaverEnabled") private var screensaverEnabled: Bool = false
    @AppStorage("screensaverDelayMinutes") private var screensaverDelayMinutes: Double = 5.0

    @ObservedObject private var appState = AppState.shared

    @State private var originalAutoSyncNewScreens = UserDefaults.standard.bool(forKey: "autoSyncNewScreens")
    @State private var originalLaunchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    @State private var originalLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system"
    @State private var originalMaxVideoFileSizeInGB = UserDefaults.standard.double(forKey: "maxVideoFileSizeInGB")
    @State private var originalScreensaverEnabled = UserDefaults.standard.bool(forKey: "screensaverEnabled")
    @State private var originalScreensaverDelayMinutes = UserDefaults.standard.double(forKey: "screensaverDelayMinutes")

    @State private var isReverting = false

    var body: some View {
        CardSection(title: LocalizedStringKey(L("General")), systemImage: "gearshape", help: LocalizedStringKey(L("Common preferences."))) {
            ToggleRow(title: LocalizedStringKey(L("GlobalMute")), value: $globalMute)
                .onChange(of: globalMute) { newValue in
                    desktop_videoApp.applyGlobalMute(newValue)
                }

            ToggleRow(title: LocalizedStringKey(L("ShowVideoInMenuBar")), value: $showMenuBarVideo)
                .onChange(of: showMenuBarVideo) { _ in
                    SharedWallpaperWindowManager.shared.updateStatusBarVideoForAllScreens()
                }

            ToggleRow(title: LocalizedStringKey(L("Auto sync new screens")), value: $autoSyncNewScreens)
                .onChange(of: autoSyncNewScreens) { newValue in
                    guard !isReverting else { isReverting = false; return }
                    dlog("autoSyncNewScreens changed to \(newValue), restart required")
                    let previous = originalAutoSyncNewScreens
                    desktop_videoApp.showRestartAlert {
                        originalAutoSyncNewScreens = newValue
                    } onDiscard: {
                        isReverting = true
                        autoSyncNewScreens = previous
                    }
                }
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
            HStack {
                Text(L("Language"))
                Picker("", selection: $language) {
                    ForEach(SupportedLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                .labelsHidden()
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

            ToggleRow(title: LocalizedStringKey(L("EnableScreenSaver")), value: $screensaverEnabled)
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

            HStack {
                Text(L("ScreenSaverDelay"))
                TextField("5", value: $screensaverDelayMinutes, formatter: NumberFormatter())
                    .frame(width: 30)
                Text(L("MinutetoSaver"))
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

            VStack {
                Text(L("PlaybackMode")).font(.subheadline)
                Picker("", selection: Binding(
                    get: { appState.playbackMode.rawValue },
                    set: { appState.playbackMode = AppState.PlaybackMode(rawValue: $0) ?? .automatic }
                )) {
                    ForEach(AppState.PlaybackMode.allCases, id: \.rawValue) { mode in
                        Text(mode.description).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                Text(appState.playbackMode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
            .frame(width: 200)
            .onChange(of: appState.playbackMode) { newValue in
                dlog("playbackMode changed to \(newValue)")
                AppDelegate.shared?.updatePlaybackStateForAllScreens()
            }

            SliderInputRow(title: LocalizedStringKey(L("idlePauseSensitivity")), value: $appState.idlePauseSensitivity, range: 0...100)
                .frame(width: 250)
                .onChange(of: appState.idlePauseSensitivity) { newValue in
                    let clamped = min(max(newValue, 0), 100)
                    appState.idlePauseSensitivity = clamped
                    dlog("set idle pause sensitivity \(clamped)")
                }

            HStack {
                Text(L("Max video cache (GB)"))
                TextField("1.0", value: $maxVideoFileSizeInGB, formatter: NumberFormatter())
                    .frame(width: 60)
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
            }
        }
    }
}


import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("autoSyncNewScreens") private var autoSyncNewScreens: Bool = true
    @AppStorage("launchAtLogin")     private var launchAtLogin:     Bool = true
    @AppStorage("selectedLanguage")  private var language:          String = "system"
    @AppStorage("maxVideoFileSizeInGB") private var maxVideoFileSizeInGB: Double = 1.0

    @State private var originalAutoSyncNewScreens = UserDefaults.standard.bool(forKey: "autoSyncNewScreens")
    @State private var originalLaunchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    @State private var originalLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system"
    @State private var originalMaxVideoFileSizeInGB = UserDefaults.standard.double(forKey: "maxVideoFileSizeInGB")

    @State private var isReverting = false

    var body: some View {
        CardSection(title: L("General"), systemImage: "gearshape", help: L("Common preferences.")) {
            ToggleRow(title: L("Auto sync new screens"), value: $autoSyncNewScreens)
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
            ToggleRow(title: L("Launch at login"), value: Binding(
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

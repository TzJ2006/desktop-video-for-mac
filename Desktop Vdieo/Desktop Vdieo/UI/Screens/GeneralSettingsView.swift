
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("autoSyncNewScreens") private var autoSyncNewScreens: Bool = true
    @AppStorage("launchAtLogin")     private var launchAtLogin:     Bool = true
    @AppStorage("selectedLanguage")  private var language:          String = "system"
    @AppStorage("maxVideoFileSizeInGB") private var maxVideoFileSizeInGB: Double = 1.0

    var body: some View {
        CardSection(title: "General", systemImage: "gearshape", help: "Common preferences.") {
            ToggleRow(title: "Auto sync new screens", value: $autoSyncNewScreens)
            ToggleRow(title: "Launch at login", value: Binding(
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
            HStack {
                Text("Max video cache (GB)")
                TextField("1.0", value: $maxVideoFileSizeInGB, formatter: NumberFormatter())
                    .frame(width: 60)
            }
        }
    }
}

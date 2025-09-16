import SwiftUI
import AppKit

struct PlaybackSettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @AppStorage("globalVolume") private var globalVolume: Double = 100
    @AppStorage("globalMute") private var globalMute: Bool = false

    private let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 0
        f.maximum = 100
        return f
    }()

    var body: some View {
        CardSection(title: LocalizedStringKey(L("Playback")), systemImage: "bolt.circle", help: LocalizedStringKey(L("Auto pause and power modes."))) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("PlaybackMode")).font(.system(size: 15))
                Picker("", selection: Binding(
                    get: { appState.playbackMode.rawValue },
                    set: { appState.playbackMode = AppState.PlaybackMode(rawValue: $0) ?? .automatic }
                )) {
                    ForEach(AppState.PlaybackMode.allCases, id: \.rawValue) { mode in
                        Text(mode.description).tag(mode.rawValue).font(.system(size: 15))
                    }
                }
                .labelsHidden()

                Text(appState.playbackMode.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

//                HStack {
//                    Text(L("Volume"))
//                    TextField("100", value: $globalVolume, formatter: numberFormatter)
//                        .frame(width: 40)
//                    Text("%")
//                    Toggle(L("MuteVideo"), isOn: $globalMute)
//                }
                .onChange(of: globalVolume) { newValue in
                    let clamped = min(max(newValue, 0), 100)
                    globalVolume = clamped
                    dlog("set global volume \(clamped)")
                    for screen in NSScreen.screens {
                        SharedWallpaperWindowManager.shared.setVolume(Float(clamped / 100.0), for: screen)
                    }
                }
                .onChange(of: globalMute) { newValue in
                    dlog("apply global mute \(newValue)")
                    desktop_videoApp.applyGlobalMute(newValue)
                }

                HStack {
                    Slider(
                        value: Binding(
                            get: { appState.idlePauseSensitivity },
                            set: { appState.idlePauseSensitivity = min(max($0, 0), 100) }
                        ),
                        in: 0...100
                    )
                    .accessibilityLabel(LocalizedStringKey(L("idlePauseSensitivity")))

                    TextField("", value: $appState.idlePauseSensitivity, formatter: numberFormatter)
                        .frame(width: 44)
                        .font(.system(size: 15))
                }
                .onChange(of: appState.idlePauseSensitivity) { newValue in
                    let clamped = min(max(newValue, 0), 100)
                    appState.idlePauseSensitivity = clamped
                    dlog("set idle pause sensitivity \(clamped)")
                }
            }
            .font(.system(size: 15)) // 统一大字
        }
    }
}

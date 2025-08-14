
import SwiftUI

struct PlaybackSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        CardSection(title: "Playback", systemImage: "bolt.circle", help: "Auto pause and power modes.") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mode").font(.subheadline)
                Picker("", selection: Binding(
                    get: { appState.playbackMode.rawValue },
                    set: { appState.playbackMode = AppState.PlaybackMode(rawValue: $0) ?? .automatic }
                )) {
                    ForEach(AppState.PlaybackMode.allCases, id: \.rawValue) { mode in
                        Text(mode.description).tag(mode.rawValue)
                    }
                }
                .labelsHidden()

                SliderRow(title: "Idle pause sensitivity", value: $appState.idlePauseSensitivity, range: 0...100)
            }
        }
    }
}

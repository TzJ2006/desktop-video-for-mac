import SwiftUI
import AppKit
import Combine

struct PlaybackSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    @Environment(\.theme) private var theme

    private let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 0
        f.maximum = 100
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(L("Playback"), subtitle: L("PlaybackSubtitle")) {
                HStack(spacing: 8) {
                    HeaderActionButton(title: L("RestoreDefaults"), systemImage: "arrow.counterclockwise") {
                        restoreDefaults()
                    }
                    HeaderHelpButton(LocalizedStringKey(L("Auto pause and power modes.")))
                }
            }

            playbackCard
            SlideshowSettingsView()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playbackCard: some View {
        CardSection(title: LocalizedStringKey(L("PlaybackMode")),
                    systemImage: "bolt.circle") {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("PlaybackModeSubtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)

                PlaybackModeSelector(selection: Binding(
                    get: { appState.playbackMode },
                    set: { appState.playbackMode = $0 }
                ))

                Text(appState.playbackMode.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)

                Divider()

                thresholdRow
            }
        }
    }

    private var thresholdRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("idlePauseSensitivity"))
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Text("\(Int(appState.idlePauseSensitivity))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(theme.controlBackground))
                    .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: 1))
            }

            SnappingSlider(
                value: Binding(
                    get: { appState.idlePauseSensitivity },
                    set: { appState.idlePauseSensitivity = $0 }
                )
            )
            .accessibilityLabel(LocalizedStringKey(L("idlePauseSensitivity")))
        }
    }

    // MARK: - 恢复默认设置（播放 + 连播，均实时生效，无需重启）

    private func restoreDefaults() {
        dlog("Playback restoreDefaults")
        appState.playbackMode = .automatic
        appState.idlePauseSensitivity = 50.0
        appState.slideshowEnabled = false
        appState.slideshowRandom = false
        appState.slideshowLoop = true
        appState.slideshowImageInterval = 60.0
    }
}

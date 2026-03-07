import SwiftUI

struct HistoryView: View {
    @StateObject private var screenObserver = ScreenObserver()
    @ObservedObject private var store = WallpaperHistoryStore.shared

    @State private var isCooldown = false

    @State private var selectedScreenID: String = {
        BookmarkStore.get(prefix: "lastScreen", id: 0) ?? (NSScreen.main?.dv_displayUUID ?? "")
    }()

    var body: some View {
        CardSection(title: LocalizedStringKey(L("History")), systemImage: "clock.arrow.circlepath", help: LocalizedStringKey(L("Previously used wallpapers."))) {
            // Screen picker for multi-display
            if screenObserver.screens.count > 1 {
                Picker(LocalizedStringKey(L("Screen")), selection: $selectedScreenID) {
                    ForEach(screenObserver.screens, id: \.dv_displayUUID) { screen in
                        Text(screen.dv_localizedName).tag(screen.dv_displayUUID).font(.system(size: 15))
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 15))
                .padding(.bottom, 4)
            }

            // Clear history button
            if !store.entries.isEmpty {
                HStack {
                    Spacer()
                    Button(action: { store.clearAll() }) {
                        Text(LocalizedStringKey(L("Clear History")))
                            .font(.system(size: 13))
                    }
                }
            }

            // History list
            if store.entries.isEmpty {
                Text(LocalizedStringKey(L("No history yet")))
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.entries) { entry in
                        HistoryItemRow(entry: entry) {
                            guard !isCooldown else { return }
                            applyWallpaper(entry)
                            isCooldown = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                isCooldown = false
                            }
                        }
                        if entry.id != store.entries.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .onChange(of: screenObserver.screens) { screens in
            if !screens.contains(where: { $0.dv_displayUUID == selectedScreenID }) {
                selectedScreenID = screens.first?.dv_displayUUID ?? ""
            }
        }
    }

    private func applyWallpaper(_ entry: WallpaperHistoryEntry) {
        guard let url = entry.url,
              let screen = screenObserver.screens.first(where: { $0.dv_displayUUID == selectedScreenID })
                ?? screenObserver.screens.first
        else { return }

        if entry.isWeb {
            SharedWallpaperWindowManager.shared.showWeb(for: screen, url: url)
        } else if entry.isVideo {
            SharedWallpaperWindowManager.shared.showVideo(
                for: screen, url: url, stretch: true, volume: AppState.shared.isGlobalMuted ? 0 : 1.0)
        } else {
            SharedWallpaperWindowManager.shared.showImage(for: screen, url: url, stretch: true)
        }
    }
}

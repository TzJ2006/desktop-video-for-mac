import SwiftUI

struct HistoryView: View {
    @StateObject private var screenObserver = ScreenObserver()
    @ObservedObject private var store = WallpaperHistoryStore.shared

    @State private var isCooldown = false

    @State private var selectedScreenID: String = {
        BookmarkStore.get(prefix: "lastScreen", id: 0) ?? (NSScreen.main?.dv_displayUUID ?? "")
    }()

    /// 当前所选屏幕的历史记录。切换屏幕选择器即切换列表。
    private var screenHistory: [WallpaperHistoryEntry] {
        store.playedEntries(for: selectedScreenID)
    }

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
            if !screenHistory.isEmpty {
                HStack {
                    Spacer()
                    Button(action: { store.clearHistory(for: selectedScreenID) }) {
                        Text(LocalizedStringKey(L("Clear History")))
                            .font(.system(size: 13))
                    }
                }
            }

            // History list（只显示真正设为过壁纸的条目；仅添加进库的不在此显示）
            if screenHistory.isEmpty {
                Text(LocalizedStringKey(L("No history yet")))
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    ForEach(screenHistory) { entry in
                        HistoryItemRow(entry: entry) {
                            guard !isCooldown else { return }
                            applyWallpaper(entry)
                            isCooldown = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                isCooldown = false
                            }
                        }
                        if entry.id != screenHistory.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .onAppear {
            // 若保存的屏幕已不在当前活动屏幕中（单屏 / 屏幕变更），重选到有效屏幕，
            // 否则按屏过滤会得到空列表，让本有历史的屏幕误显示「无历史」。
            if !screenObserver.screens.contains(where: { $0.dv_displayUUID == selectedScreenID }) {
                selectedScreenID = screenObserver.screens.first?.dv_displayUUID ?? selectedScreenID
            }
        }
        .onChange(of: selectedScreenID) { newID in
            // 与「墙纸」面板共用 lastScreen，使两处屏幕选择保持一致
            BookmarkStore.set(newID, prefix: "lastScreen", id: 0)
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

        let manager = SharedWallpaperWindowManager.shared
        if entry.isWeb {
            manager.showWeb(for: screen, url: url)
        } else {
            // 文件不可访问时先弹窗请求重新授权，成功后再切换；用户取消则保留当前壁纸（功能7）
            guard let authorized = manager.ensureAccessibleURL(url, isVideo: entry.isVideo) else { return }
            if entry.isVideo {
                manager.showVideo(
                    for: screen, url: authorized, stretch: true, volume: AppState.shared.isGlobalMuted ? 0 : 1.0)
            } else {
                manager.showImage(for: screen, url: authorized, stretch: true)
            }
        }
    }
}

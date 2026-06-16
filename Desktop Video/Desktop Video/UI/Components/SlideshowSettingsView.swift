import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 「自动连播」+「播放列表」两张并排卡片（Image #3 布局）。
/// 左卡：开关（在卡片头部）+ 顺序 / 循环 / 图片切换间隔；右卡：播放列表（加文件/文件夹、列表、清空）。
/// 播放列表可加入单个文件或整个文件夹；视频播完自动切下一项，图片按间隔切换，每屏各自独立。
struct SlideshowSettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var playlist = PlaylistStore.shared

    @Environment(\.theme) private var theme

    private let intervalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 2
        f.maximum = 86_400
        f.allowsFloats = false
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            autoAdvanceCard
            playlistCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 自动连播

    private var autoAdvanceCard: some View {
        CardSection(
            title: LocalizedStringKey(L("Slideshow")),
            systemImage: "play.rectangle.on.rectangle",
            trailing: {
                Toggle("", isOn: $appState.slideshowEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Auto-advance through a playlist of files or folders."))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Order")).font(.system(size: 13, weight: .medium))
                    Picker("", selection: $appState.slideshowRandom) {
                        Text(LocalizedStringKey(L("Sequential"))).tag(false)
                        Text(LocalizedStringKey(L("Random"))).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Toggle(LocalizedStringKey(L("Loop playlist")), isOn: $appState.slideshowLoop)
                    .toggleStyle(.checkbox)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Image interval (seconds)")).font(.system(size: 13, weight: .medium))
                    HStack(spacing: 8) {
                        TextField("", value: $appState.slideshowImageInterval, formatter: intervalFormatter)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                        Stepper("", value: $appState.slideshowImageInterval, in: 2...86_400, step: 1)
                            .labelsHidden()
                        Text(L("Seconds")).font(.system(size: 13)).foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .disabled(!appState.slideshowEnabled)
        }
    }

    // MARK: - 播放列表

    private var playlistCard: some View {
        CardSection(
            title: LocalizedStringKey(L("Playlist")),
            systemImage: "list.bullet",
            trailing: {
                if !playlist.items.isEmpty {
                    Button(role: .destructive) { playlist.clearAll() } label: {
                        Text(LocalizedStringKey(L("Clear"))).font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.errorText)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button(action: addFiles) {
                        Label(L("Add Files…"), systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: addFolder) {
                        Label(L("Add Folder…"), systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }

                if playlist.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "play.square.stack")
                            .font(.system(size: 34))
                            .foregroundStyle(theme.secondaryText)
                        Text(LocalizedStringKey(L("Playlist empty hint")))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 0) {
                        ForEach(playlist.items) { item in
                            playlistRow(item)
                            if item.id != playlist.items.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func playlistRow(_ item: PlaylistItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.isFolder ? "folder.fill" : (item.contentType == "video" ? "film" : "photo"))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 18)
            Text(item.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            if item.isFolder {
                Text("(\(playlist.mediaCount(of: item)))")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Button(role: .destructive) {
                playlist.remove(item)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    // MARK: - 添加

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        playlist.addFiles(panel.urls)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        playlist.addFolder(folder)
    }
}

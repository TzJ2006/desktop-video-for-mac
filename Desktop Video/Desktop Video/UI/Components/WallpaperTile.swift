import SwiftUI
import AppKit

/// 画廊中的单个壁纸缩略图磁贴（Apple「墙纸」面板风格）。
/// 沿用应用既有约定：双击应用到目标屏幕；选中项显示强调色描边。
struct WallpaperTile: View {
    let entry: WallpaperHistoryEntry
    let isSelected: Bool
    let onApply: () -> Void

    @State private var thumbnail: NSImage?
    @Environment(\.theme) private var theme

    static let tileSize = CGSize(width: 132, height: 84)

    init(entry: WallpaperHistoryEntry, isSelected: Bool, onApply: @escaping () -> Void) {
        self.entry = entry
        self.isSelected = isSelected
        self.onApply = onApply

        let initialThumbnail: NSImage?
        if !entry.isWeb, let url = entry.url {
            initialThumbnail = ThumbnailGenerator.cachedImageIfAvailable(for: url)
        } else {
            initialThumbnail = nil
        }
        _thumbnail = State(initialValue: initialThumbnail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                thumbView
                badge
            }
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
            .clipShape(RoundedRectangle(cornerRadius: theme.tileCornerRadius))
            .overlay(selectionRing)

            Text(entry.displayName)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.tileSize.width, alignment: .leading)
                .foregroundStyle(isSelected ? theme.accent : theme.primaryText)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onApply() }
        .help(entry.displayName)
        .task(id: entry.id) { await loadThumbnail() }
    }

    @ViewBuilder private var thumbView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.secondary.opacity(0.12)
                Image(systemName: entry.isWeb ? "globe" : (entry.isVideo ? "film" : "photo"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var badge: some View {
        Text(LocalizedStringKey(L(entry.isWeb ? "Web" : (entry.isVideo ? "Video" : "Image"))))
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(theme.contentTypeColor(isWeb: entry.isWeb, isVideo: entry.isVideo))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(theme.badgeBackground, in: Capsule())
            .padding(5)
    }

    @ViewBuilder private var selectionRing: some View {
        RoundedRectangle(cornerRadius: theme.tileCornerRadius)
            .strokeBorder(isSelected ? theme.accent : theme.tileBorder,
                          lineWidth: isSelected ? 3 : 1)
    }

    private func loadThumbnail() async {
        guard !entry.isWeb, let url = entry.url else { return }
        if thumbnail != nil { return }
        thumbnail = await ThumbnailGenerator.cached(for: url, isVideo: entry.isVideo)
    }
}

/// 画廊中的「添加」磁贴：虚线边框 + 图标 + 文案。
struct AddWallpaperTile: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme.tileCornerRadius)
                        .fill(theme.controlBackground)
                    VStack(spacing: 4) {
                        Image(systemName: systemImage)
                            .font(.title2)
                        Text(title)
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(width: WallpaperTile.tileSize.width, height: WallpaperTile.tileSize.height)

                Text(" ")
                    .font(.system(size: 11))
            }
        }
        .buttonStyle(.plain)
    }
}

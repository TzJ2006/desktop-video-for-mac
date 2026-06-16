import Foundation

/// 连播播放列表中的一项：单个媒体文件，或一个文件夹（运行时展开为其内含媒体）。
struct PlaylistItem: Codable, Identifiable, Equatable {
    let urlString: String
    let isFolder: Bool
    let contentType: String        // 文件："video"/"image"；文件夹："folder"
    let displayName: String
    /// 文件夹添加时枚举到的媒体文件（绝对字符串）；单文件为空。
    var childURLStrings: [String]

    var id: String { urlString }
    var url: URL? { URL(string: urlString) }
}

/// 连播播放列表的持久化存储（UserDefaults，JSON）。
/// 用户可加入单个文件或整个文件夹；文件夹在添加时枚举并为每个子文件保存 per-URL 书签。
@MainActor
final class PlaylistStore: ObservableObject {
    static let shared = PlaylistStore()

    @Published private(set) var items: [PlaylistItem] = []

    private let storageKey = "wallpaperPlaylist"

    private init() { load() }

    // MARK: - 增删

    /// 加入若干媒体文件（已通过 NSOpenPanel 授权），自动跳过重复项与非媒体文件。
    func addFiles(_ urls: [URL]) {
        var changed = false
        for url in urls {
            guard url.isFileURL, MediaAccess.isMediaFile(url) else { continue }
            guard !items.contains(where: { $0.urlString == url.absoluteString }) else { continue }
            MediaAccess.saveURLBookmark(for: url)
            items.append(PlaylistItem(
                urlString: url.absoluteString,
                isFolder: false,
                contentType: MediaAccess.isVideo(url) ? "video" : "image",
                displayName: url.lastPathComponent,
                childURLStrings: []))
            changed = true
        }
        if changed { save(); notifyChanged() }
    }

    /// 加入一个文件夹：枚举其中所有媒体并为每个子文件保存 per-URL 书签。
    /// 若文件夹已在列表中则刷新其内容。
    func addFolder(_ folder: URL) {
        guard folder.isFileURL else { return }
        let media = MediaAccess.scanFolder(folder)
        for fileURL in media { MediaAccess.saveURLBookmark(for: fileURL) }
        MediaAccess.saveURLBookmark(for: folder)

        let item = PlaylistItem(
            urlString: folder.absoluteString,
            isFolder: true,
            contentType: "folder",
            displayName: folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent,
            childURLStrings: media.map { $0.absoluteString })

        if let idx = items.firstIndex(where: { $0.urlString == folder.absoluteString }) {
            items[idx] = item
        } else {
            items.append(item)
        }
        save(); notifyChanged()
    }

    func remove(_ item: PlaylistItem) {
        items.removeAll { $0.id == item.id }
        save(); notifyChanged()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save(); notifyChanged()
    }

    func clearAll() {
        items.removeAll()
        save(); notifyChanged()
    }

    // MARK: - 展开

    /// 展开为可播放媒体序列（文件夹展开为子文件，保持列表顺序）。
    func resolvedMedia() -> [(url: URL, isVideo: Bool)] {
        var result: [(URL, Bool)] = []
        for item in items {
            if item.isFolder {
                for string in item.childURLStrings {
                    if let url = URL(string: string) { result.append((url, MediaAccess.isVideo(url))) }
                }
            } else if let url = item.url {
                result.append((url, item.contentType == "video"))
            }
        }
        return result
    }

    /// 文件夹项展开后的媒体数量，用于 UI 展示。
    func mediaCount(of item: PlaylistItem) -> Int {
        item.isFolder ? item.childURLStrings.count : 1
    }

    // MARK: - 持久化

    private func notifyChanged() {
        SlideshowController.shared.playlistDidChange()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PlaylistItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

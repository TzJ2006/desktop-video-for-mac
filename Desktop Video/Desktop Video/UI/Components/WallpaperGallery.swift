import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Apple「墙纸」面板风格的壁纸画廊。
/// 顶部为「添加」磁贴行（选择文件 / 输入网址），其下为按内容类型派生的
/// 「视频 / 图片 / 网页」分类行。数据源是壁纸库（快捷切换入口，与历史记录分离）。
/// 所有应用操作作用于传入的目标屏幕，沿用双击应用 + 1 秒冷却的既有约定。
struct WallpaperGallery: View {
    let screen: NSScreen
    /// 目标屏幕当前壁纸的 URL 字符串，用于在画廊中高亮选中项。
    let currentURLString: String?

    @ObservedObject private var store = WallpaperHistoryStore.shared
    @ObservedObject private var appState = AppState.shared
    @Environment(\.theme) private var theme

    @State private var isCooldown = false
    @State private var expandedRows: Set<String> = []
    @State private var showWebInput = false
    @State private var webURLString = ""
    @State private var webURLError: String?

    /// 折叠状态下横向条目上限，超过则显示「Show All」入口（展开为网格）。
    private let collapsedLimit = 6
    private let gridColumns = [GridItem(.adaptive(minimum: WallpaperTile.tileSize.width), spacing: 12, alignment: .leading)]

    private var libraryEntries: [WallpaperHistoryEntry] {
        store.libraryEntries(sortedBy: appState.librarySortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            categoryRow(key: "Videos", entries: libraryEntries.filter { $0.isVideo }, showAddFile: true)
            categoryRow(key: "Images", entries: libraryEntries.filter { !$0.isVideo && !$0.isWeb }, showAddFile: true)
            categoryRow(key: "Web", entries: libraryEntries.filter { $0.isWeb }, showAddWeb: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 分类行

    private var webInputPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(L("Input Web URL"))).font(.system(size: 13, weight: .medium))
            TextField(L("EnterWebURL"), text: $webURLString)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(applyWebURL)
            if let webURLError {
                Text(webURLError).font(.system(size: 11)).foregroundColor(theme.errorText)
            }
            HStack {
                Spacer()
                Button(L("Apply"), action: applyWebURL)
            }
        }
        .padding(14)
    }

    // MARK: - 分类行

    @ViewBuilder
    private func categoryRow(key: String, entries: [WallpaperHistoryEntry], showAddFile: Bool = false, showAddWeb: Bool = false) -> some View {
        if !entries.isEmpty || showAddFile || showAddWeb {
            // 条目数回落到上限以内时强制折叠（此时也不再显示 Show All 入口）
            let expanded = entries.count > collapsedLimit && expandedRows.contains(key)
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(title: L(key),
                              count: entries.count,
                              key: entries.count > collapsedLimit ? key : nil,
                              expanded: expanded)
                if expanded {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                        if showAddFile { addFileTile }
                        if showAddWeb { addWebTile }
                        ForEach(entries) { tile($0) }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            if showAddFile { addFileTile }
                            if showAddWeb { addWebTile }
                            ForEach(entries) { tile($0) }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
        }
    }

    private var addFileTile: some View {
        AddWallpaperTile(title: LocalizedStringKey(L("Choose File or Folder…")), systemImage: "doc.badge.plus", action: chooseFileOrFolder)
    }

    private var addWebTile: some View {
        AddWallpaperTile(title: LocalizedStringKey(L("Input Web URL")), systemImage: "globe.badge.chevron.backward", action: {
            if !showWebInput { webURLError = nil; webURLString = "" }
            showWebInput.toggle()
        })
        .popover(isPresented: $showWebInput, arrowEdge: .bottom) { webInputPopover }
    }

    private func tile(_ entry: WallpaperHistoryEntry) -> some View {
        WallpaperTile(entry: entry, isSelected: entry.urlString == currentURLString) {
            applyEntry(entry)
        }
        .contextMenu {
            Button(role: .destructive) {
                store.removeFromLibrary(entry: entry)
            } label: {
                Text(LocalizedStringKey(L("Remove from library")))
            }
        }
    }

    private func sectionHeader(title: String, count: Int?, key: String?, expanded: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            if let key {
                Button {
                    if expandedRows.contains(key) { expandedRows.remove(key) } else { expandedRows.insert(key) }
                } label: {
                    Text(expanded ? L("Show Less") : "\(L("Show All")) (\(count ?? 0))")
                        .font(.system(size: 12))
                }
                .buttonStyle(.link)
            }
        }
    }

    // MARK: - 应用 / 添加

    private func applyEntry(_ entry: WallpaperHistoryEntry) {
        guard !isCooldown, let url = entry.url else { return }
        let manager = SharedWallpaperWindowManager.shared
        if entry.isWeb {
            manager.showWeb(for: screen, url: url)
        } else {
            // 文件不可访问时先弹窗请求重新授权，成功后再切换；用户取消则保留当前壁纸（功能7）
            guard let authorized = manager.ensureAccessibleURL(url, isVideo: entry.isVideo) else {
                dlog("apply cancelled (re-auth declined) for \(entry.fileName) on \(screen.dv_localizedName)")
                return
            }
            if entry.isVideo {
                manager.showVideo(
                    for: screen, url: authorized, stretch: true,
                    volume: AppState.shared.isGlobalMuted ? 0 : 1.0)
            } else {
                manager.showImage(for: screen, url: authorized, stretch: true)
            }
        }
        dlog("apply wallpaper from gallery \(entry.fileName) on \(screen.dv_localizedName)")
        startCooldown()
    }

    private func startCooldown() {
        isCooldown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isCooldown = false }
    }

    // 统一的「选择文件 / 文件夹」入口（沿用 NSOpenPanel 以满足沙盒授权）。
    // 同一面板同时允许选文件和选文件夹：选中文件则作为壁纸应用，选中文件夹则枚举其中
    // 所有图片/视频批量加入历史记录（功能 1 合并 + 功能 4）。
    private func chooseFileOrFolder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? url.hasDirectoryPath
        if isDirectory {
            addFolder(url)
        } else {
            applyFile(url)
        }
    }

    // 把单个文件加入壁纸库并应用到目标屏幕，并保存 per-URL 书签以便后续无授权重开。
    private func applyFile(_ url: URL) {
        dlog("gallery applyFile url=\(url.lastPathComponent)")
        MediaAccess.saveURLBookmark(for: url)
        let contentType = MediaAccess.isVideo(url) ? "video" : "image"
        WallpaperHistoryStore.shared.ensureInLibrary(url: url, contentType: contentType)
        if MediaAccess.isImage(url) {
            SharedWallpaperWindowManager.shared.showImage(for: screen, url: url, stretch: true)
        } else {
            SharedWallpaperWindowManager.shared.showVideo(
                for: screen, url: url, stretch: true,
                volume: effectiveVideoVolume())
        }
    }

    // 把文件夹内所有图片/视频批量加入历史记录（功能4）。
    // 文件夹访问权来自 NSOpenPanel，枚举时为每个子文件保存 per-URL 书签以便后续访问。
    private func addFolder(_ folder: URL) {
        let media = MediaAccess.scanFolder(folder)
        guard !media.isEmpty else {
            dlog("gallery addFolder: no media found in \(folder.lastPathComponent)")
            return
        }
        for fileURL in media { MediaAccess.saveURLBookmark(for: fileURL) }
        let items = media.map { (url: $0, contentType: MediaAccess.isVideo($0) ? "video" : "image") }
        WallpaperHistoryStore.shared.recordMany(items)
        dlog("gallery addFolder added \(media.count) items from \(folder.lastPathComponent)")
    }

    /// 新视频的起始音量：全局静音为 0；否则沿用目标屏幕的当前音量（本地静音时即为 0），
    /// 无既有内容时为满音量。保持与原逐屏控件相同的双层静音 + 当前音量语义。
    private func effectiveVideoVolume() -> Float {
        if AppState.shared.isGlobalMuted { return 0 }
        let sid = screen.dv_displayUUID
        if let player = SharedWallpaperWindowManager.shared.players[sid] {
            return player.volume
        }
        if let vol = SharedWallpaperWindowManager.shared.screenContent[sid]?.volume {
            return vol
        }
        return 1.0
    }

    private func applyWebURL() {
        webURLError = nil
        var urlString = webURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else {
            webURLError = L("URLEmpty")
            return
        }
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        guard let url = URL(string: urlString) else {
            webURLError = L("InvalidURL")
            return
        }
        WallpaperHistoryStore.shared.ensureInLibrary(url: url, contentType: "web")
        // 沿用目标屏幕当前网页音量，避免重设网址时音量被重置为满音量
        let currentVolume = SharedWallpaperWindowManager.shared.screenContent[screen.dv_displayUUID]?.volume ?? 1.0
        SharedWallpaperWindowManager.shared.showWeb(for: screen, url: url, volume: currentVolume)
        webURLString = ""
        showWebInput = false
    }
}

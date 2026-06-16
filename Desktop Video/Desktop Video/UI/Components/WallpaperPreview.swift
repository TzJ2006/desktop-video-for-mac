import SwiftUI
import AppKit
import WebKit

/// Apple「墙纸」面板风格的当前壁纸大预览磁贴。
/// 视频取首帧、图片缩放、网页用实时 WKWebView 渲染缩略图（取不到内容时回退到占位图标）。
/// 注：「需重新授权」提示只保留在历史记录界面（HistoryItemRow），墙纸界面不再叠加警告。
struct WallpaperPreview: View {
    let screen: NSScreen
    /// 刷新令牌：壁纸内容变化时由父视图自增，触发缩略图重载。
    var refreshToken: Int

    @State private var thumbnail: NSImage?
    @State private var kind: Kind
    @State private var webURL: URL?
    /// 已加载内容的标识（类型 + URL）。用于在 refreshToken 频繁自增时跳过重复解码。
    @State private var loadedID: String?
    @Environment(\.theme) private var theme

    enum Kind { case none, image, video, web }

    private static let previewSize = CGSize(width: 240, height: 150)

    /// 视图重建（如切换侧边栏页面）会重置 @State，导致首帧显示占位图再异步重取 → 看起来「重新加载」。
    /// 这里在 init 时同步从内存缓存预填：命中则首帧即显示真图，配合 reload() 的去重不再触发重解码。
    init(screen: NSScreen, refreshToken: Int = 0) {
        self.screen = screen
        self.refreshToken = refreshToken

        var initialThumb: NSImage?
        var initialKind: Kind = .none
        var initialURL: URL?
        var initialLoaded: String?
        if let entry = SharedWallpaperWindowManager.shared.screenContent[screen.dv_displayUUID] {
            let contentID = "\(entry.type)#\(entry.url.absoluteString)"
            switch entry.type {
            case .web:
                initialKind = .web
                initialURL = entry.url
                initialLoaded = contentID
            case .image, .video:
                initialKind = entry.type == .video ? .video : .image
                if let cached = ThumbnailGenerator.cachedImageIfAvailable(for: entry.url) {
                    initialThumb = cached
                    initialLoaded = contentID
                }
            }
        }
        _thumbnail = State(initialValue: initialThumb)
        _kind = State(initialValue: initialKind)
        _webURL = State(initialValue: initialURL)
        _loadedID = State(initialValue: initialLoaded)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.previewCornerRadius)
                .fill(theme.controlBackground)
            if kind == .web, let webURL {
                webThumbnail(webURL)
            } else if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.previewSize.width, height: Self.previewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: theme.previewCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.previewCornerRadius)
                .strokeBorder(theme.tileBorder, lineWidth: 1)
        )
        .task(id: taskID) { await reload() }
    }

    private var taskID: String { "\(screen.dv_displayUUID)#\(refreshToken)" }

    private var placeholderSymbol: String {
        switch kind {
        case .web:   return "globe"
        case .video: return "film"
        case .image: return "photo"
        case .none:  return "photo.on.rectangle.angled"
        }
    }

    /// 用实时 WKWebView 渲染网页缩略图：按目标屏幕宽高比离屏渲染整页，再整体缩放铺进预览框。
    /// 比对桌面壁纸 WebView 截图更可靠——桌面级（canBecomeKey=false）窗口的 takeSnapshot 常返回空白。
    @ViewBuilder
    private func webThumbnail(_ url: URL) -> some View {
        let screenSize = screen.frame.size
        let aspect = screenSize.width > 0 ? screenSize.height / screenSize.width : 0.625
        let baseW = min(max(screenSize.width, 320), 1280)
        let baseH = baseW * aspect
        let scale = min(Self.previewSize.width / baseW, Self.previewSize.height / baseH)
        WebThumbnailView(url: url)
            .frame(width: baseW, height: baseH)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: baseW * scale, height: baseH * scale)
            .allowsHitTesting(false)
    }

    private func reload() async {
        let sid = screen.dv_displayUUID
        guard let entry = SharedWallpaperWindowManager.shared.screenContent[sid] else {
            kind = .none
            thumbnail = nil
            webURL = nil
            loadedID = nil
            return
        }
        // refreshToken 因遮挡/空闲暂停/静音等高频事件不断自增，但只要内容标识未变且已成功加载，
        // 就复用现有缩略图，避免反复闪占位图与重复解码视频帧。loadedID 仅在内容真正就绪后才标记。
        let contentID = "\(entry.type)#\(entry.url.absoluteString)"
        if contentID == loadedID { return }
        switch entry.type {
        case .web:
            thumbnail = nil
            kind = .web
            webURL = entry.url
            loadedID = contentID  // 网页用实时 WKWebView 渲染，无需解码，直接标记完成
        case .image, .video:
            let isVideo = (entry.type == .video)
            kind = isVideo ? .video : .image
            webURL = nil
            // 先同步命中内存缓存：命中则直接替换显示，不清空、不异步，避免占位图闪烁与重新加载
            if let cached = ThumbnailGenerator.cachedImageIfAvailable(for: entry.url) {
                thumbnail = cached
                loadedID = contentID
                return
            }
            // 未命中才清空旧图并异步生成。清空同时把 loadedID 置空，维持
            //「loadedID==contentID ⟺ 缩略图就绪」的不变式（切到失败内容后再切回仍能正确重解码）。
            thumbnail = nil
            loadedID = nil
            let image = await ThumbnailGenerator.cached(for: entry.url, isVideo: isVideo)
            // 解码期间任务可能因 refreshToken 变化被取消重启；取消时不标记 loadedID，
            // 否则后续同内容任务会因「已加载」提前返回，把缩略图永久卡在占位图。
            if Task.isCancelled { return }
            thumbnail = image
            // 仅在成功取到缩略图时标记已加载；失败（nil，如文件暂不可访问）不标记，
            // 以便文件恢复可读（重新授权后重设壁纸刷新书签）时能重试，而非永久卡占位图。
            if image != nil { loadedID = contentID }
        }
    }
}

/// 网页预览用的实时 WKWebView：禁止媒体自动播放（避免预览发声/耗电），交互由外层 allowsHitTesting(false) 屏蔽。
private struct WebThumbnailView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: config)
        // 与桌面壁纸 WebView 使用相同 UA，使预览的页面布局与实际壁纸一致
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        webView.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}

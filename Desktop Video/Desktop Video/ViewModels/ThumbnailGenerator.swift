import AppKit
import AVFoundation
import ImageIO
import CryptoKit

enum ThumbnailGenerator {
    /// 统一的缩略图解码 / 缓存尺寸（点）。历史行（64×48）、画廊磁贴（132×84）、大预览（240×150）
    /// 共用同一张缩略图，显示时各自用 .resizable() 缩放，避免同一文件因显示尺寸不同被重复解码与缓存。
    /// 取各界面最大需求（大预览 240×150 @2x = 480×300）为上限，缩小显示画质足够。
    static let canonicalSize = NSSize(width: 480, height: 300)

    static func generate(for url: URL, isVideo: Bool) async -> NSImage? {
        if isVideo {
            return await generateVideoThumbnail(url: url)
        } else {
            return generateImageThumbnail(url: url)
        }
    }

    /// 尝试激活 per-URL 安全作用域书签，返回 (可用URL, 需要释放的URL?)。
    /// 与 `MediaAccess.isAccessible` 保持一致的双分支解析：先按安全作用域解析并 startAccessing；
    /// 失败时回退到非安全作用域书签解析（saveURLBookmark 创建安全作用域书签失败时会存非作用域书签，
    /// 在同沙盒权限内仍可读）。两者都失败才退回原始 URL。缺了这条回退会导致画廊缩略图静默变空白。
    private static func activateBookmark(for url: URL) -> (URL, URL?) {
        guard url.isFileURL else { return (url, nil) }
        guard let bookmarkData: Data = BookmarkStore.get(prefix: "urlBookmark", id: url.standardized.path) else {
            dlog("thumbnail: no urlBookmark for \(url.lastPathComponent), reading url directly")
            return (url, nil)
        }
        var stale = false
        // 安全作用域书签：解析后需 startAccessing 才能在沙盒内读取，成功则返回需释放的 URL
        if let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            if resolved.startAccessingSecurityScopedResource() {
                return (resolved, resolved)
            }
            dlog("thumbnail: startAccessingSecurityScopedResource failed for \(resolved.lastPathComponent)")
        }
        // 回退：非安全作用域书签（同沙盒权限内仍可复用）
        if let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return (resolved, nil)
        }
        dlog("thumbnail: failed to resolve urlBookmark for \(url.lastPathComponent), reading url directly")
        return (url, nil)
    }

    private static func generateVideoThumbnail(url: URL) async -> NSImage? {
        let (accessURL, scopedURL) = activateBookmark(for: url)
        defer { scopedURL?.stopAccessingSecurityScopedResource() }

        let asset = AVAsset(url: accessURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // 统一解码到 canonicalSize（已是 Retina 像素上限），各界面共用并在显示时缩放
        generator.maximumSize = CGSize(width: canonicalSize.width, height: canonicalSize.height)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        do {
            let cgImage: CGImage
            if #available(macOS 13, *) {
                let result = try await generator.image(at: time)
                cgImage = result.image
            } else {
                var actualTime = CMTime.zero
                cgImage = try generator.copyCGImage(at: time, actualTime: &actualTime)
            }
            // NSImage 逻辑尺寸用 CGImage 实际像素尺寸，保留真实宽高比，
            // 让各界面 .aspectRatio(.fill) 正确裁剪而非拉伸变形
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return nsImage
        } catch {
            dlog("thumbnail: video frame extraction failed for \(accessURL.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private static func generateImageThumbnail(url: URL) -> NSImage? {
        let (accessURL, scopedURL) = activateBookmark(for: url)
        defer { scopedURL?.stopAccessingSecurityScopedResource() }

        // Use ImageIO to generate a thumbnail off-main-thread to avoid AppKit drawing QoS inversions
        guard let src = CGImageSourceCreateWithURL(accessURL as CFURL, nil) else {
            dlog("thumbnail: CGImageSource create failed for \(accessURL.lastPathComponent)")
            return nil
        }
        let maxPixelSize = Int(max(canonicalSize.width, canonicalSize.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            dlog("thumbnail: CGImageSourceCreateThumbnailAtIndex failed for \(accessURL.lastPathComponent)")
            return nil
        }
        // NSImage 逻辑尺寸用实际像素尺寸，保留真实宽高比
        let nsImage = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
        return nsImage
    }
}

// MARK: - 缓存（内存 + 磁盘 + 负缓存）
extension ThumbnailGenerator {
    /// 缩略图内存缓存：键为 URL（+本地文件修改时间）。命中即瞬时返回、不重新解码。
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        c.totalCostLimit = 96 * 1024 * 1024  // ~96MB 字节上限，防止大尺寸预览图撑爆内存
        return c
    }()

    /// 单张缩略图的内存成本估算（统一尺寸像素字节数，宽×高×4），配合 totalCostLimit 限制总内存。
    private static var memoryCost: Int { Int(canonicalSize.width * canonicalSize.height * 4) }

    // MARK: 磁盘缓存（B）：扛 NSCache 驱逐 + 跨重启复用

    /// 磁盘缓存目录（沙盒内 Caches，可被系统在磁盘紧张时回收，无需额外授权）。
    private static let diskCacheDirectory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 磁盘读写/清理用串行队列（避免阻塞主线程与并发写冲突）。
    private static let diskQueue = DispatchQueue(label: "com.desktopvideo.thumbnail.disk", qos: .utility)

    /// 启动后清理一次磁盘缓存（只跑一次，由首次 cached() 触发）。
    private static let pruneOnce: Void = {
        diskQueue.async { pruneDiskCacheIfNeeded() }
    }()

    /// 缓存键 → 磁盘文件 URL（用 SHA256 十六进制做文件名，避免路径中的非法字符）。
    private static func diskFileURL(forKey key: NSString) -> URL? {
        guard let dir = diskCacheDirectory else { return nil }
        let digest = SHA256.hash(data: Data((key as String).utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name).appendingPathExtension("png")
    }

    /// 从磁盘读取缩略图（PNG）。与生成路径一致：用实际像素尺寸构造 NSImage，保留真实宽高比。
    private static func diskCachedImage(forKey key: NSString) -> NSImage? {
        guard let fileURL = diskFileURL(forKey: key),
              FileManager.default.fileExists(atPath: fileURL.path),
              let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// 把缩略图编码为 PNG 异步写入磁盘（编码在后台队列，避免阻塞）。
    private static func writeToDisk(_ image: NSImage, forKey key: NSString) {
        guard let fileURL = diskFileURL(forKey: key),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        diskQueue.async {
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 清理磁盘缓存：总大小超过上限时，按修改时间从旧到新删除直至降到上限以下。
    private static func pruneDiskCacheIfNeeded() {
        guard let dir = diskCacheDirectory else { return }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var entries: [(url: URL, size: Int, date: Date)] = files.compactMap { f in
            guard let v = try? f.resourceValues(forKeys: Set(keys)),
                  let size = v.fileSize, let date = v.contentModificationDate else { return nil }
            return (f, size, date)
        }
        let cap = 128 * 1024 * 1024  // ~128MB 磁盘缓存上限
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > cap else { return }
        entries.sort { $0.date < $1.date }  // 最旧的先删
        for e in entries {
            if total <= cap { break }
            try? fm.removeItem(at: e.url)
            total -= e.size
        }
    }

    // MARK: 负缓存（C）：跳过已知不可访问/解码失败的文件，避免反复 isAccessible + 解码

    private static let negativeLock = NSLock()
    private static var negativeCache = Set<String>()

    /// 内容变更时清空负缓存：重新授权后会 showVideo/showImage 触发 WallpaperContentDidChange，
    /// 借此让此前不可访问的文件有机会重试。只读一次的静态观察者，应用生命周期内常驻。
    private static let negativeCacheObserver: NSObjectProtocol = {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("WallpaperContentDidChange"),
            object: nil, queue: nil) { _ in clearNegativeCache() }
    }()

    private static func isNegative(_ key: NSString) -> Bool {
        negativeLock.lock(); defer { negativeLock.unlock() }
        return negativeCache.contains(key as String)
    }
    private static func markNegative(_ key: NSString) {
        negativeLock.lock(); defer { negativeLock.unlock() }
        negativeCache.insert(key as String)
    }
    private static func clearNegativeCache() {
        negativeLock.lock(); defer { negativeLock.unlock() }
        negativeCache.removeAll()
    }

    // MARK: 公开入口

    /// 同步返回已在内存缓存中的缩略图（命中返回，未命中返回 nil，不触发生成/磁盘读）。
    /// 供视图重建（如切换侧边栏页面）时同步预填，使首帧即显示，避免异步重取导致的占位图闪烁/重新加载。
    static func cachedImageIfAvailable(for url: URL) -> NSImage? {
        cache.object(forKey: cacheKey(for: url))
    }

    /// 带缓存的缩略图获取。命中顺序：内存 → 磁盘 → 解码生成。
    /// 不可访问或解码失败记入负缓存，避免每次切页都重复昂贵调用。
    static func cached(for url: URL, isVideo: Bool) async -> NSImage? {
        _ = negativeCacheObserver  // 确保已注册「内容变更清负缓存」观察者
        _ = pruneOnce              // 启动后清理一次磁盘缓存
        let key = cacheKey(for: url)
        // 1. 内存缓存
        if let hit = cache.object(forKey: key) { return hit }
        // 2. 磁盘缓存（扛驱逐 / 跨重启）
        if let disk = diskCachedImage(forKey: key) {
            cache.setObject(disk, forKey: key, cost: memoryCost)
            return disk
        }
        // 3. 负缓存：已知不可访问/失败，直接跳过，不再触碰 isAccessible / AVFoundation / ImageIO
        if isNegative(key) { return nil }
        // 4. 可访问性预检：不可读则记负缓存返回（避免画廊对无权限文件反复敲 AVFoundation 刷错误日志）
        if url.isFileURL, !MediaAccess.isAccessible(url) {
            markNegative(key)
            return nil
        }
        // 5. 解码生成
        guard let image = await generate(for: url, isVideo: isVideo) else {
            markNegative(key)
            return nil
        }
        cache.setObject(image, forKey: key, cost: memoryCost)
        writeToDisk(image, forKey: key)
        return image
    }

    /// 带「需重新授权」状态的缩略图加载。
    /// 本地文件不可访问（被移动/删除/权限丢失）时返回 needsReauth=true，供界面叠加灰色警告。
    static func loadStatus(for url: URL, isVideo: Bool)
        async -> (image: NSImage?, needsReauth: Bool) {
        guard MediaAccess.isAccessible(url) else { return (nil, true) }
        let image = await cached(for: url, isVideo: isVideo)
        return (image, false)
    }

    /// 构造缓存键。所有界面共用同一尺寸的缩略图，故键只含 URL（本地文件附带修改时间，
    /// 避免同路径文件被替换后仍返回旧缩略图）。
    private static func cacheKey(for url: URL) -> NSString {
        var token = ""
        if url.isFileURL,
           let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            token = "|\(Int(mod.timeIntervalSince1970))"
        }
        return "\(url.absoluteString)\(token)" as NSString
    }
}


import Foundation
import AppKit
import UniformTypeIdentifiers

/// 媒体文件类型判断、文件夹枚举、安全作用域可访问性检查与 per-URL 书签保存的统一入口。
/// 供画廊「选文件夹」、播放列表、连播控制器与缩略图「需重新授权」检测复用。
enum MediaAccess {

    // MARK: - 类型判断

    /// 是否视频（优先用 UTType，回退到扩展名）
    static func isVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if let t = UTType(filenameExtension: ext) {
            if t.conforms(to: .movie) || t.conforms(to: .video) { return true }
            if t.conforms(to: .image) { return false }
        }
        return ["mp4", "mov", "m4v", "mpg", "mpeg", "avi", "mkv", "webm"].contains(ext)
    }

    /// 是否图片（优先用 UTType，回退到扩展名）
    static func isImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if let t = UTType(filenameExtension: ext) {
            if t.conforms(to: .image) { return true }
            if t.conforms(to: .movie) || t.conforms(to: .video) { return false }
        }
        return ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "webp"].contains(ext)
    }

    /// 是否为受支持的媒体文件
    static func isMediaFile(_ url: URL) -> Bool { isVideo(url) || isImage(url) }

    // MARK: - 文件夹枚举

    /// 递归枚举文件夹中的所有图片/视频，按文件名自然排序，最多 maxCount 个。
    /// 需要调用方已持有该文件夹的访问权限（如刚通过 NSOpenPanel 选择或已存书签）。
    static func scanFolder(_ folder: URL, maxCount: Int = 1000) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [URL] = []
        for case let fileURL as URL in enumerator {
            if result.count >= maxCount { break }
            if isMediaFile(fileURL) { result.append(fileURL) }
        }
        return result.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    // MARK: - 可访问性

    /// 激活 per-URL 安全作用域书签后判断本地文件是否可读；网络/远程 URL 视为始终可访问。
    /// 文件被移动、删除或权限丢失时返回 false（用于触发「需重新授权」提示）。
    static func isAccessible(_ url: URL) -> Bool {
        guard url.isFileURL else { return true }
        if let data: Data = BookmarkStore.get(prefix: "urlBookmark", id: url.standardized.path) {
            var stale = false
            if let resolved = try? URL(
                resolvingBookmarkData: data, options: .withSecurityScope,
                relativeTo: nil, bookmarkDataIsStale: &stale) {
                let started = resolved.startAccessingSecurityScopedResource()
                defer { if started { resolved.stopAccessingSecurityScopedResource() } }
                if FileManager.default.isReadableFile(atPath: resolved.path) { return true }
            } else if let resolved = try? URL(
                resolvingBookmarkData: data, options: [],
                relativeTo: nil, bookmarkDataIsStale: &stale) {
                if FileManager.default.isReadableFile(atPath: resolved.path) { return true }
            }
        }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    // MARK: - 书签

    /// 为文件创建并保存 per-URL 安全作用域书签（要求当前已有访问权限，
    /// 如来自 NSOpenPanel 选择的文件，或已授权文件夹的子文件）。
    @discardableResult
    static func saveURLBookmark(for url: URL) -> Bool {
        guard url.isFileURL else { return false }
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            BookmarkStore.set(data, prefix: "urlBookmark", id: url.standardized.path)
            return true
        } catch {
            // 回退到非安全作用域书签，仍可在相同沙盒权限内复用
            if let data = try? url.bookmarkData(
                options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                BookmarkStore.set(data, prefix: "urlBookmark", id: url.standardized.path)
                return true
            }
            errorLog("saveURLBookmark failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }
}

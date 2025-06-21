//
//  Utils.swift
//  desktop video
//
//  Created by ChatGPT on 2025-05-11.
//

import AppKit
import Foundation

// MARK: - Notification 统一管理
extension Notification.Name {
    /// 壁纸内容变更后发送，用于刷新 UI
    static let wallpaperContentDidChange = Notification.Name("WallpaperContentDidChange")
}

// MARK: - NSScreen 帮助函数
extension NSScreen {

    /// 屏幕本地化名称；macOS 14 及以上系统自带，以下版本回退到“屏幕 n”
    var dv_localizedName: String {
        if #available(macOS 14, *) {
            return localizedName
        }
        if let idx = NSScreen.screens.firstIndex(of: self) {
            return "屏幕 \(idx + 1)"
        }
        return "未知屏幕"
    }

    /// 唯一 displayID（CGDirectDisplayID）
    var dv_displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func screen(forDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.dv_displayID == id }
    }
}

// MARK: - Security‑Scoped Bookmark 持久化
struct BookmarkStore {

    /// 生成统一 key，如 “bookmark‑12345678”
    private static func key(_ prefix: String, id: CGDirectDisplayID) -> String {
        "\(prefix)-\(id)"
    }

    /// 保存/更新
    static func set<T>(_ value: T?, prefix: String, id: CGDirectDisplayID) {
        UserDefaults.standard.set(value, forKey: key(prefix, id: id))
    }

    /// 读取
    static func get<T>(prefix: String, id: CGDirectDisplayID) -> T? {
        UserDefaults.standard.object(forKey: key(prefix, id: id)) as? T
    }

    /// 删除指定显示器的所有数据
    static func purge(id: CGDirectDisplayID) {
        ["bookmark", "stretch", "volume", "savedAt"].forEach {
            UserDefaults.standard.removeObject(forKey: key($0, id: id))
        }
    }
}

// MARK: - 时间戳辅助
/// 生成用于日志的时间戳字符串
func dvTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

// MARK: - 日志辅助函数
/// 日志级别定义
enum DVLogLevel: String {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
}

/// 调试日志，仅在 DEBUG 构建输出
func dlog(_ message: String, level: DVLogLevel = .debug, function: String = #function) {
#if DEBUG
    print("[\(dvTimestamp())][\(level.rawValue)] \(function): \(message)")
#endif
}

/// 错误日志辅助，会写入 ~/Library/Logs/desktop-video.log
/// 在 DEBUG 模式下同时输出到控制台
func errorLog(_ message: String, function: String = #function) {
    let entry = "[\(dvTimestamp())] \(function): \(message)\n"
#if DEBUG
    print(entry, terminator: "")
#endif
    if let logDir = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("Logs", isDirectory: true) {
        let logURL = logDir.appendingPathComponent("desktop-video.log")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
        }
    }
}

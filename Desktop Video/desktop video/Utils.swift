//
//  Utils.swift
//  desktop video
//
//  Created by ChatGPT on 2025-05-11.
//

import AppKit
import Foundation
import CoreGraphics

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

    /// 稳定的屏幕标识，优先使用 CGDisplay 的 UUID
    var dv_displayUUID: String {
        if let id = dv_displayID,
           let uuidRef = CGDisplayCreateUUIDFromDisplayID(id) {
            let cfuuid = uuidRef.takeRetainedValue()
            let uuid = CFUUIDCreateString(nil, cfuuid) as String
            return uuid
        }
        let res = "\(Int(frame.width))x\(Int(frame.height))"
        return "\(dv_localizedName)-\(res)"
    }

    static func screen(forDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.dv_displayID == id }
    }

    static func screen(forUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { $0.dv_displayUUID == uuid }
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
func dlog(_ message: String,
          level: DVLogLevel = .debug,
          function: String = #function)
{
    // 1) 保留 Debug 模式下的控制台打印
    #if DEBUG
    print("[\(dvTimestamp())][\(level.rawValue)] \(function): \(message)")
    #endif

    // 2) 委托给 LogFile 单例写入文件
    LogFile.shared.write("[\(dvTimestamp())][\(level.rawValue)] \(function): \(message)")
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

final class LogFile {
    static let shared = LogFile()

    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.yourapp.logfile")

    private init() {
        // 2.1 构造日志文件的绝对路径：~/Library/Logs/desktop-video.log
        let logURL = FileManager.default
            .homeDirectoryForCurrentUser           // 获取当前用户主目录路径 :contentReference[oaicite:2]{index=2}
            .appendingPathComponent("Library/Logs")
            .appendingPathComponent("desktop-video.log")

        let fm = FileManager.default
        // 2.2 确保 Logs 目录存在，否则创建（支持多级创建） :contentReference[oaicite:3]{index=3}
        try? fm.createDirectory(at: logURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true,
                                attributes: nil)

        // 2.3 如果日志文件不存在，则创建一个空文件 :contentReference[oaicite:4]{index=4}
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path,
                          contents: nil,
                          attributes: nil)
        }

        // 2.4 打开文件句柄并定位到末尾，准备以追加模式写入 :contentReference[oaicite:5]{index=5}
        fileHandle = try? FileHandle(forWritingTo: logURL)
        fileHandle?.seekToEndOfFile()            // 定位到文件末尾 :contentReference[oaicite:6]{index=6}
    }

    func write(_ message: String) {
        guard let handle = fileHandle,
              let data = (message + "\n").data(using: .utf8) else { return }
        // 异步写入，避免阻塞主线程 :contentReference[oaicite:7]{index=7}
        queue.async {
            handle.write(data)
        }
    }

    deinit {
        try? fileHandle?.close()                // 关闭句柄 :contentReference[oaicite:8]{index=8}
    }
}

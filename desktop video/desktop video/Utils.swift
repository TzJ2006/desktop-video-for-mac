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

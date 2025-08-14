//
//  LanguageManager.swift
//  desktop video
//
//  Created by 汤子嘉 on 5/29/25.
//

import Foundation
import SwiftUI

/// 支持的语言
enum SupportedLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"
    case traditional = "zh-Hant"
    case french      = "fr"
    case spanish     = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
            case .system: return "系统默认"
            case .english: return "English"
            case .chinese: return "简体中文"
            case .traditional: return "繁體中文"
            case .french:      return "Français"
            case .spanish:     return "Español"
        }
    }
}

/// 全局语言管理器
class LanguageManager: ObservableObject {
    /// 单例实例，方便在整个应用中调用
    static let shared = LanguageManager()

    /// 当前用户选择的语言，`system` 表示跟随系统语言
    @AppStorage("selectedLanguage") var selectedLanguage: String = "system"

    /// 根据 `selectedLanguage` 返回对应的 `Bundle`
    /// - 如果选择跟随系统，则直接返回 `Bundle.main`
    /// - 如果指定了其它语言，则从 `.lproj` 目录构造 Bundle
    var bundle: Bundle {
        guard selectedLanguage != "system" else {
            return .main
        }

        if let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj"),
           let customBundle = Bundle(path: path) {
            return customBundle
        }
        return .main
    }

    /// 根据当前语言获取本地化字符串
    /// - Parameter key: 本地化键值
    /// - Returns: 对应语言的字符串，若不存在则返回原键值
    func localizedString(forKey key: String) -> String {
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

/// 语法糖：快速访问当前语言的本地化字符串
func L(_ key: String) -> String {
    return LanguageManager.shared.localizedString(forKey: key)
}

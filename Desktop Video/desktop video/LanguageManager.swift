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
    static let shared = LanguageManager()

    @AppStorage("selectedLanguage") var selectedLanguage: String = "system"

    /// 返回当前语言的 Bundle（默认为 main）
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

    /// 根据当前语言加载字符串
    func localizedString(forKey key: String) -> String {
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

/// 语法糖辅助：本地化 key
func L(_ key: String) -> String {
    return LanguageManager.shared.localizedString(forKey: key)
}

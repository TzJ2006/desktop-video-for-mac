//
//  ThemeManager.swift
//  Desktop Video
//
//  全局外观管理器。仿照 LanguageManager / AppState 的模式：
//  单例 + @Published + UserDefaults 持久化。
//  与语言切换不同，外观切换实时生效，无需重启。
//

import Foundation
import SwiftUI

/// 全局外观管理器（单例）。
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    /// 当前选中的外观；变化时写入 UserDefaults 持久化。
    @Published var current: AppTheme {
        didSet {
            guard oldValue != current else { return }
            dlog("ThemeManager.current = \(current.rawValue)")
            UserDefaults.standard.set(current.rawValue, forKey: Self.storageKey)
        }
    }

    /// 当前外观的设计 token，供注入 `\.theme` 环境使用。
    var tokens: ThemeTokens { current.tokens }

    private static let storageKey = "selectedTheme"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        self.current = Self.resolve(raw)
    }

    /// 解析持久化值，并兼容早期「经典 / 玻璃深色」两套主题的旧值：
    /// classic → 跟随系统；glassDark → 深色。
    private static func resolve(_ raw: String?) -> AppTheme {
        if let raw, let mode = AppTheme(rawValue: raw) { return mode }
        switch raw {
        case "classic":   return .system
        case "glassDark": return .dark
        default:          return .system
        }
    }
}

extension View {
    /// 在视图根部应用当前主题：注入 token 环境 + 设定明暗外观。
    /// 调用方需以 `@ObservedObject` 持有该 manager，主题切换才能实时刷新。
    func applyTheme(_ manager: ThemeManager) -> some View {
        self
            .environment(\.theme, manager.tokens)
            .preferredColorScheme(manager.tokens.colorScheme)
    }
}

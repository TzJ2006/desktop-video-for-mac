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
import AppKit

/// 全局外观管理器（单例）。
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    /// 当前选中的外观；变化时写入 UserDefaults 持久化。
    @Published var current: AppTheme {
        didSet {
            guard oldValue != current else { return }
            dlog("ThemeManager.current = \(current.rawValue)")
            UserDefaults.standard.set(current.rawValue, forKey: "selectedTheme")
            applyWindowAppearance()
        }
    }

    /// 系统实际明暗（仅在「跟随系统」时用于驱动 SwiftUI 刷新）。
    @Published private(set) var systemColorScheme: ColorScheme

    /// 当前生效的明暗（跟随系统时取系统值，否则取用户指定值）。
    var resolvedColorScheme: ColorScheme {
        switch current {
        case .system: return systemColorScheme
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// 当前外观的设计 token，供注入 `\.theme` 环境使用。
    var tokens: ThemeTokens { tokens(for: current) }

    private static let storageKey = "selectedTheme"
    private var appearanceObserver: NSObjectProtocol?

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        self.current = Self.resolve(raw)
        self.systemColorScheme = Self.readSystemColorScheme()
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemAppearanceChange()
        }
    }

    deinit {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }

    func tokens(for theme: AppTheme) -> ThemeTokens {
        switch theme {
        case .system: return .glass(systemColorScheme)
        case .light:  return .glass(.light)
        case .dark:   return .glass(.dark)
        }
    }

    /// 将当前外观同步到所有已跟踪的主窗口（NSAppearance + 标题栏材质）。
    func applyWindowAppearance() {
        DispatchQueue.main.async {
            AppDelegate.shared?.syncMainWindowAppearance()
        }
    }

    private func handleSystemAppearanceChange() {
        let newScheme = Self.readSystemColorScheme()
        guard systemColorScheme != newScheme else { return }
        dlog("ThemeManager systemColorScheme = \(newScheme == .dark ? "dark" : "light")")
        systemColorScheme = newScheme
        if current == .system {
            applyWindowAppearance()
        }
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

    private static func readSystemColorScheme() -> ColorScheme {
        let match = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }
}

extension View {
    /// 在视图根部应用当前主题：注入 token 环境 + 设定明暗外观。
    /// 调用方需以 `@ObservedObject` 持有该 manager，主题切换才能实时刷新。
    func applyTheme(_ manager: ThemeManager) -> some View {
        self
            .environment(\.theme, manager.tokens)
            .preferredColorScheme(manager.resolvedColorScheme)
            .id("\(manager.current.rawValue)-\(manager.resolvedColorScheme)")
    }
}


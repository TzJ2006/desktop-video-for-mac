//
//  Theme.swift
//  Desktop Video
//
//  应用外观系统：把颜色 / 材质 / 圆角等抽象成一组「设计 token」，
//  组件通过 `@Environment(\.theme)` 读取，从而与具体配色解耦。
//
//  与早期「经典 / 玻璃深色」两套独立主题不同，现在全 App 统一一套
//  「liquid glass」设计——半透明磨砂玻璃 + 整窗模糊透出桌面，
//  仅由「外观」（跟随系统 / 浅色 / 深色）驱动明暗。主界面采用 macOS 26
//  原生 Liquid Glass（`.glassEffect` / `GlassEffectContainer`）。
//

import SwiftUI

// MARK: - 设计 Token

/// 一套外观的全部「设计 token」。
/// 作用范围仅限 App 的设置 / 主界面 UI，不影响壁纸窗口、屏保时钟等独立外观。
struct ThemeTokens {
    // MARK: 外观
    /// 驱动 `.preferredColorScheme`；`nil` 表示跟随系统明暗。
    var colorScheme: ColorScheme?

    // MARK: 表面（材质或纯色，统一用 AnyShapeStyle 承载）
    /// 主内容滚动区背景。玻璃设计下为透明——直接透出整窗玻璃底层。
    var windowBackground: AnyShapeStyle
    /// 侧边栏背景。
    var sidebarBackground: AnyShapeStyle
    /// 卡片（CardSection / 分组设置框）背景。
    var cardBackground: AnyShapeStyle
    /// 控件/缩略图底板背景（预览框、添加磁贴、分组检查器等）。
    var controlBackground: AnyShapeStyle
    /// 内容类型徽标后面的胶囊材质。
    var badgeBackground: AnyShapeStyle
    /// 整窗玻璃上的色彩校正层。
    var windowTint: Color
    /// 侧边栏玻璃上的色彩校正层。
    var sidebarTint: Color

    // MARK: 文字与强调色
    var primaryText: Color
    var secondaryText: Color
    var accent: Color
    var errorText: Color

    // MARK: 内容类型色（网页 / 视频 / 图片）
    var contentTypeWeb: Color
    var contentTypeVideo: Color
    var contentTypeImage: Color

    // MARK: 线条 / 边框 / 选中
    var cardBorder: Color
    var tileBorder: Color
    var selectionFill: Color

    // MARK: 圆角
    var cardCornerRadius: CGFloat
    var tileCornerRadius: CGFloat
    var previewCornerRadius: CGFloat

    /// 内容类型前景色。
    func contentTypeColor(isWeb: Bool, isVideo: Bool) -> Color {
        isWeb ? contentTypeWeb : (isVideo ? contentTypeVideo : contentTypeImage)
    }

    /// 内容类型徽标背景色（前景色的低透明度版本）。
    func contentTypeBadgeBackground(isWeb: Bool, isVideo: Bool) -> Color {
        contentTypeColor(isWeb: isWeb, isVideo: isVideo).opacity(0.15)
    }
}

// MARK: - 外观注册表

/// 可选外观。代码内置注册表：三档外观共用同一套玻璃设计，仅明暗不同。
enum AppTheme: String, CaseIterable, Identifiable {
    /// 跟随系统明暗。
    case system
    /// 强制浅色。
    case light
    /// 强制深色。
    case dark

    var id: String { rawValue }

    /// 本地化显示名（用于设置里的 Picker）。
    var displayName: String {
        switch self {
        case .system: return L("AppearanceSystem")
        case .light:  return L("AppearanceLight")
        case .dark:   return L("AppearanceDark")
        }
    }

    /// 该外观对应的设计 token：统一玻璃设计 + 对应明暗。
    var tokens: ThemeTokens {
        switch self {
        case .system: return .glass(nil)
        case .light:  return .glass(.light)
        case .dark:   return .glass(.dark)
        }
    }
}

// MARK: - 玻璃预设

extension ThemeTokens {
    /// 统一的 Liquid Glass 设计 token。三档外观共用，仅 `colorScheme` 不同。
    ///
    /// 卡片/侧栏等表面由 `.glassEffect` 渲染，再用轻 tint 把浅色外观提亮。
    static func glass(_ scheme: ColorScheme?) -> ThemeTokens {
        let isDark = scheme == .dark
        let groupedSurface = isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.54)

        return ThemeTokens(
            colorScheme: scheme,
            windowBackground: AnyShapeStyle(Color.clear),
            sidebarBackground: AnyShapeStyle(Color.clear),
            cardBackground: AnyShapeStyle(groupedSurface),
            controlBackground: AnyShapeStyle(groupedSurface),
            badgeBackground: AnyShapeStyle(isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.48)),
            windowTint: isDark ? Color.black.opacity(0.18) : Color.white.opacity(0.42),
            sidebarTint: isDark ? Color.black.opacity(0.14) : Color.white.opacity(0.34),
            primaryText: .primary,
            secondaryText: .secondary,
            accent: .accentColor,
            errorText: .red,
            contentTypeWeb: .purple,
            contentTypeVideo: .blue,
            contentTypeImage: .green,
            cardBorder: Color.primary.opacity(0.10),
            tileBorder: Color.primary.opacity(0.12),
            selectionFill: Color.accentColor.opacity(0.18),
            cardCornerRadius: 16,
            tileCornerRadius: 10,
            previewCornerRadius: 14
        )
    }
}

// MARK: - Environment 注入

private struct ThemeTokensKey: EnvironmentKey {
    static let defaultValue: ThemeTokens = .glass(nil)
}

extension EnvironmentValues {
    /// 当前外观的设计 token。组件用 `@Environment(\.theme) private var theme` 读取。
    var theme: ThemeTokens {
        get { self[ThemeTokensKey.self] }
        set { self[ThemeTokensKey.self] = newValue }
    }
}

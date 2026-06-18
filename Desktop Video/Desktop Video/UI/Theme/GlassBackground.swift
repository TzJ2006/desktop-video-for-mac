//
//  GlassBackground.swift
//  Desktop Video
//
//  macOS 26+ 原生 Liquid Glass：使用同一层整窗玻璃，内容区自行延伸至标题栏安全区。
//

import SwiftUI
import AppKit

/// 整窗统一 Liquid Glass 底层；浅色外观叠加白色 tint，避免背景透出后发灰。
private struct WindowGlassBackground: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Rectangle()
            .glassEffect(.regular, in: Rectangle())
            .overlay(themeManager.tokens.windowTint)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

extension View {
    /// 整窗 Liquid Glass 底层。
    func glassWindowBackground() -> some View {
        background {
            WindowGlassBackground()
        }
    }
}

extension NSWindow {
    /// 应用整窗 Liquid Glass 外观：半透明 + 透明标题栏。
    func applyGlassWindowStyle() {
        styleMask.insert(.fullSizeContentView)
        isOpaque = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        syncAppearance(with: ThemeManager.shared)
    }

    /// 将窗口 NSAppearance 与「外观」设置对齐。
    func syncAppearance(with themeManager: ThemeManager) {
        switch themeManager.current {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
    }
}

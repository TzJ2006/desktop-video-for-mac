//
//  PageHeader.swift
//  Desktop Video
//
//  页面级标题区（Image #3 风格）：左对齐大标题 + 副标题，
//  右上角放「恢复默认设置 / 帮助」等动作按钮。
//

import SwiftUI

/// 页面顶部标题区：左侧大标题 + 副标题，右侧可放动作按钮。
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: () -> Trailing

    @Environment(\.theme) private var theme

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 标题区动作按钮（玻璃胶囊）：图标 + 文案，如「恢复默认设置」。
struct HeaderActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(theme.controlBackground))
            .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 标题区帮助按钮（圆形「?」），点按弹出说明。
struct HeaderHelpButton: View {
    let help: LocalizedStringKey
    @State private var show = false
    @Environment(\.theme) private var theme

    init(_ help: LocalizedStringKey) { self.help = help }

    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .frame(width: 32, height: 32)
                .background(Circle().fill(theme.controlBackground))
                .overlay(Circle().strokeBorder(theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L("help")))
        .popover(isPresented: $show) { Text(help).padding().frame(width: 240) }
    }
}

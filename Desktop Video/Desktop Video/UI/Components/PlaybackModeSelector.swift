//
//  PlaybackModeSelector.swift
//  Desktop Video
//
//  播放模式选择器（Image #3 风格的分段控件）。保留全部 5 个模式，
//  选中段以玻璃高亮 + 强调色描边突出；模式说明在选择器下方显示。
//

import SwiftUI

struct PlaybackModeSelector: View {
    @Binding var selection: AppState.PlaybackMode

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppState.PlaybackMode.allCases) { mode in
                segment(mode)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(theme.controlBackground)
        )
    }

    private func segment(_ mode: AppState.PlaybackMode) -> some View {
        let isSelected = selection == mode
        return Button {
            selection = mode
        } label: {
            Text(mode.description)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.accent : theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(theme.cardBackground) : AnyShapeStyle(Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? theme.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

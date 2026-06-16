//
//  CenteredMenuPicker.swift
//  Desktop Video
//
//  文字居中的下拉选择框（自定义 Menu label），用于「外观 / 壁纸库排序 / 语言」等设置行。
//  原生 Picker(.menu)（NSPopUpButton）的选中文本只能左对齐；此组件把文本在 chevron 左侧区域居中、
//  右侧放自绘的上下箭头，并用固定宽度保证多个下拉框大小一致、右对齐。
//  菜单内容用内联 Picker，保留原生的「选中项打勾」与选择语义。
//

import SwiftUI

struct MenuOption<T: Hashable>: Identifiable {
    let value: T
    let title: String
    var id: T { value }
}

struct CenteredMenuPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [MenuOption<T>]
    var width: CGFloat = 200

    @Environment(\.theme) private var theme

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? ""
    }

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options) { opt in
                    Text(opt.title).tag(opt.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 0) {
                Text(selectedTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity)            // 文本在 chevron 左侧区域居中
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 16, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.cardBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

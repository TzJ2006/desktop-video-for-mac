import SwiftUI

/// 卡片分区。左对齐的「图标徽章 + 标题 + 可选配件」头部 + Liquid Glass 磨砂卡面。
struct CardSection<Content: View, Trailing: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: LocalizedStringKey?
    let trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(\.theme) private var theme

    init(title: LocalizedStringKey,
         systemImage: String,
         help: LocalizedStringKey? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.trailing = trailing
        self.content = content
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: cardShape)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.accent.opacity(0.15))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            .frame(width: 30, height: 30)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            trailing()

            if let help {
                HelpButton(help)
            }
        }
    }
}

extension CardSection where Trailing == EmptyView {
    init(title: LocalizedStringKey,
         systemImage: String,
         help: LocalizedStringKey? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, systemImage: systemImage, help: help,
                  trailing: { EmptyView() }, content: content)
    }
}

private struct HelpButton: View {
    let key: LocalizedStringKey
    @State private var show = false
    @Environment(\.theme) private var theme
    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme.controlBackground))
                .overlay(Circle().strokeBorder(theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L("help")))
        .popover(isPresented: $show) { Text(key).padding().frame(width: 220) }
    }
    init(_ key: LocalizedStringKey) { self.key = key }
}

import SwiftUI

struct CardSection<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: LocalizedStringKey?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                if let help {
                    HelpButton(help)
                }
            }
            Divider()
            content()
        }
        .padding()
        .background(cardBackground)
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.regularMaterial)
    }
}

private struct HelpButton: View {
    let key: LocalizedStringKey
    @State private var show = false
    var body: some View {
        Button("?") { show.toggle() }
            .accessibilityLabel(Text("help"))
            .popover(isPresented: $show) { Text(key).padding().frame(width: 200) }
    }
    init(_ key: LocalizedStringKey) { self.key = key }
}

import SwiftUI

struct CardSection<Content: View>: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let helpKey: LocalizedStringKey?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(titleKey, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                if let helpKey {
                    HelpButton(helpKey)
                }
            }
            Divider()
            content()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HelpButton: View {
    let key: LocalizedStringKey
    @State private var show = false
    var body: some View {
        Button("?", action: { show.toggle() })
            .accessibilityLabel(Text("help"))
            .popover(isPresented: $show) {
                Text(key)
                    .padding()
                    .frame(width: 200)
            }
    }
    init(_ key: LocalizedStringKey) { self.key = key }
}

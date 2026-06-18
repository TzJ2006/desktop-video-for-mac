import SwiftUI

struct SidebarItem: View {
    let icon: String
    let name: LocalizedStringKey
    let selection: SidebarSelection
    @Binding var current: SidebarSelection

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: {
            let previous = current
            current = selection
            dlog("sidebar button tapped: target=\(selection), previous=\(previous), changed=\(previous != selection)", level: .info)
        }) {
            Label(name, systemImage: icon)
                .font(.system(size: 16))
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(current == selection ? theme.selectionFill : .clear)
        )
    }
}

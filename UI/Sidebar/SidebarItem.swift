import SwiftUI

struct SidebarItem: View {
    let icon: String
    let nameKey: LocalizedStringKey
    let selection: SidebarSelection
    @Binding var current: SidebarSelection

    var body: some View {
        Button(action: { current = selection }) {
            Label(nameKey, systemImage: icon)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(current == selection ? Color.accentColor.opacity(0.2) : .clear)
        )
    }
}

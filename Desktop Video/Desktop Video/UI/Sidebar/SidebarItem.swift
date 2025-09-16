import SwiftUI

struct SidebarItem: View {
    let icon: String
    let name: LocalizedStringKey
    let selection: SidebarSelection
    @Binding var current: SidebarSelection

    var body: some View {
        Button(action: { current = selection }) {
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
                .fill(current == selection ? Color.accentColor.opacity(0.2) : .clear)
        )
    }
}

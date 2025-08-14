
import SwiftUI
import AppKit

struct SidebarView: View {
    @Binding var selection: SidebarSelection
    var body: some View {
        VStack(spacing: 8) {
            VStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                Text("Desktop Video")
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            ForEach(SidebarSelection.allCases, id: \.self) { item in
                switch item {
                case .wallpaper:
                    SidebarItem(icon: "sparkles", name: "Wallpaper", selection: item, current: $selection)
                case .playback:
                    SidebarItem(icon: "bolt.circle", name: "Playback", selection: item, current: $selection)
                case .general:
                    SidebarItem(icon: "gearshape", name: "General", selection: item, current: $selection)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

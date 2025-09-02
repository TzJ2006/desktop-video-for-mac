
import SwiftUI
import AppKit

struct SidebarView: View {
    @Binding var selection: SidebarSelection
    @ObservedObject private var languageManager = LanguageManager.shared
    var body: some View {
        VStack(spacing: 8) {
            VStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                Text(L("Desktop Video"))
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            ForEach(SidebarSelection.allCases, id: \.self) { item in
                switch item {
                case .wallpaper:
                    SidebarItem(icon: "sparkles", name: LocalizedStringKey(L("Wallpaper")), selection: item, current: $selection)
                case .playback:
                    SidebarItem(icon: "bolt.circle", name: LocalizedStringKey(L("Playback")), selection: item, current: $selection)
                case .general:
                    SidebarItem(icon: "gearshape", name: LocalizedStringKey(L("General")), selection: item, current: $selection)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}


import SwiftUI

/// Main window using a sidebar + card content layout.
struct AppMainWindow: View {
    static let sidebarWidth: CGFloat = 220
    static let dividerWidth: CGFloat = 1
    static let contentMinWidth: CGFloat = 620
    static let minWidth: CGFloat = sidebarWidth + dividerWidth + contentMinWidth
    static let minHeight: CGFloat = 600

    @StateObject private var vm = AppViewModel()
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $vm.selection)
                .frame(width: Self.sidebarWidth)
                .background(theme.sidebarBackground)

            Divider()

            ScrollView {
                VStack(alignment: .center, spacing: 16) {
                    switch vm.selection {
                    case .wallpaper: WallpaperView()
                    case .playback: PlaybackSettingsView()
                    case .history:  HistoryView()
                    case .general:  GeneralSettingsView()
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity) // Ensure content centers/expands
            }
            .background(theme.windowBackground)
        }
        .frame(minWidth: Self.minWidth, minHeight: Self.minHeight)
    }
}

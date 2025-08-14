
import SwiftUI

/// Main window using a sidebar + card content layout.
struct AppMainWindow: View {
    @StateObject private var vm = AppViewModel()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $vm.selection)
                .frame(width: 220)
                .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .center, spacing: 16) {
                    switch vm.selection {
                    case .wallpaper: WallpaperView()
                    case .playback: PlaybackSettingsView()
                    case .general:  GeneralSettingsView()
                    }
                }
                .padding(20)
            }
        }
    }
}

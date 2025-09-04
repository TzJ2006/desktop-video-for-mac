
import SwiftUI

/// Main window using a sidebar + card content layout.
struct AppMainWindow: View {
    @StateObject private var vm = AppViewModel()
    private let baseWidth: CGFloat = 800

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / baseWidth, 1.0)
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
            .scaleEffect(scale, anchor: .topLeading)
            .frame(
                width: proxy.size.width / scale,
                height: proxy.size.height / scale,
                alignment: .topLeading
            )
        }
    }
}

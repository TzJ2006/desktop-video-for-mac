
import SwiftUI

/// Main window using a sidebar + card content layout.
struct AppMainWindow: View {
    @StateObject private var vm = AppViewModel()
    @State private var sidebarWidth: CGFloat = 220
    @State private var dragStartWidth: CGFloat = 220
    private let minSidebarWidth: CGFloat = 160
    private let maxSidebarWidth: CGFloat = 400

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $vm.selection)
                .frame(width: sidebarWidth)
                .background(.ultraThinMaterial)

            Divider()
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let proposed = dragStartWidth + value.translation.width
                            updateSidebarWidth(proposed)
                        }
                        .onEnded { _ in
                            dragStartWidth = sidebarWidth
                        }
                )

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

    private func updateSidebarWidth(_ newWidth: CGFloat) {
        let clamped = min(max(newWidth, minSidebarWidth), maxSidebarWidth)
        if clamped != sidebarWidth {
            dlog("Sidebar width adjusted to \(clamped)")
            sidebarWidth = clamped
        }
    }
}

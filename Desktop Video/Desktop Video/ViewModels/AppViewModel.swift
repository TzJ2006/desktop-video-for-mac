
import SwiftUI

/// Global application view model.
final class AppViewModel: ObservableObject {
    @Published var selection: SidebarSelection = .wallpaper
}

/// Sidebar items.
enum SidebarSelection: Hashable, CaseIterable {
    case wallpaper
    case playback
    case general
}

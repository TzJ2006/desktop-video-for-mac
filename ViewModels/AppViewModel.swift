import SwiftUI

/// Global application view model.
final class AppViewModel: ObservableObject {
    /// Currently selected sidebar item.
    @Published var selection: SidebarSelection = .startup
}

/// Sidebar navigation items.
enum SidebarSelection: Hashable, CaseIterable {
    case startup
    case custom
    case battery
}

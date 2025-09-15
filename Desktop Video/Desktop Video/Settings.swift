import Foundation
import Combine

/// Centralised user settings that need to be observed outside of SwiftUI.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var showInMenuBar: Bool {
        didSet {
            dlog("Settings.showInMenuBar updated to \(showInMenuBar)")
            UserDefaults.standard.set(showInMenuBar, forKey: Self.showInMenuBarKey)
        }
    }

    private static let showInMenuBarKey = "showInMenuBar"
    private static let legacyKey = "showMenuBarVideo"

    private init() {
        if UserDefaults.standard.object(forKey: Self.showInMenuBarKey) != nil {
            showInMenuBar = UserDefaults.standard.bool(forKey: Self.showInMenuBarKey)
        } else if UserDefaults.standard.object(forKey: Self.legacyKey) != nil {
            let migrated = UserDefaults.standard.bool(forKey: Self.legacyKey)
            showInMenuBar = migrated
            UserDefaults.standard.set(migrated, forKey: Self.showInMenuBarKey)
            dlog("Settings migrated legacy showMenuBarVideo -> showInMenuBar = \(migrated)")
        } else {
            showInMenuBar = false
        }
        dlog("Settings initialized showInMenuBar=\(showInMenuBar)")
    }
}

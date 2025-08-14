
import SwiftUI
import AppKit

/// Stub observer for screen changes – extend with your real logic.
final class ScreenObserver: ObservableObject {
    @Published var screens: [NSScreen] = NSScreen.screens
    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            self.screens = NSScreen.screens
        }
    }
}

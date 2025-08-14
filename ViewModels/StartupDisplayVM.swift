import SwiftUI

/// View model for the Startup & Display section.
final class StartupDisplayVM: ObservableObject {
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("language") var language: String = "en"
    @AppStorage("statusBarStyle") var statusBarStyle: Int = 0
}


import SwiftUI
import AppKit

struct WallpaperView: View {
    @StateObject private var screenObserver = ScreenObserver()
    @State private var menuBarOnly = UserDefaults.standard.bool(forKey: "isMenuBarOnly")
    var body: some View {
        CardSection(title: "Wallpaper", systemImage: "sparkles", help: "Manage video wallpapers per display.") {
            ForEach(screenObserver.screens, id: \.dv_displayUUID) { screen in
                SingleScreenView(screen: screen)
            }
            ToggleRow(title: "Show only in menu bar", value: Binding(
                get: { menuBarOnly },
                set: { UserDefaults.standard.set($0, forKey: "isMenuBarOnly"); menuBarOnly = $0 }
            ))
        }
    }
}

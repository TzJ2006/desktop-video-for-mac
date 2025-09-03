
import SwiftUI
import AppKit

struct WallpaperView: View {
    @StateObject private var screenObserver = ScreenObserver()
    @State private var menuBarOnly = UserDefaults.standard.bool(forKey: "isMenuBarOnly")
    var body: some View {
        CardSection(title: LocalizedStringKey(L("Wallpaper")), systemImage: "sparkles", help: LocalizedStringKey(L("Manage video wallpapers per display."))) {
            ForEach(screenObserver.screens, id: \.dv_displayUUID) { screen in
                SingleScreenView(screen: screen)
            }
            ToggleRow(title: LocalizedStringKey(L("Show only in menu bar")), value: Binding(
                get: { menuBarOnly },
                set: {
                    menuBarOnly = $0
                    AppDelegate.shared.setDockIconVisible(!$0)
                }
            ))
        }
    }
}

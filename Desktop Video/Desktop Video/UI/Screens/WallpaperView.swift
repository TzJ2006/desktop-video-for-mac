import SwiftUI
import AppKit

struct WallpaperView: View {
    @StateObject private var screenObserver = ScreenObserver()
    @State private var menuBarOnly = UserDefaults.standard.bool(forKey: "isMenuBarOnly")
    // 记住上次选择的屏幕，使用 BookmarkStore 持久化
    @State private var selectedScreenID: String = {
        BookmarkStore.get(prefix: "lastScreen", id: 0) ?? (NSScreen.main?.dv_displayUUID ?? "")
    }()

    var body: some View {
        CardSection(title: LocalizedStringKey(L("Wallpaper")), systemImage: "sparkles", help: LocalizedStringKey(L("Manage video wallpapers per display."))) {
            if screenObserver.screens.count > 1 {
                Picker(LocalizedStringKey(L("Screen")), selection: $selectedScreenID) {
                    ForEach(screenObserver.screens, id: \.dv_displayUUID) { screen in
                        Text(screen.dv_localizedName).tag(screen.dv_displayUUID)
                    }
                }
                .pickerStyle(.menu)

                if let screen = screenObserver.screens.first(where: { $0.dv_displayUUID == selectedScreenID }) {
                    SingleScreenView(screen: screen)
                }
            } else if let screen = screenObserver.screens.first {
                SingleScreenView(screen: screen)
            }

            MenuBarVideoToggle()

            ToggleRow(title: LocalizedStringKey(L("Show only in menu bar")), value: Binding(
                get: { menuBarOnly },
                set: {
                    menuBarOnly = $0
                    AppDelegate.shared.setDockIconVisible(!$0)
                }
            ))
        }
        .onChange(of: screenObserver.screens) { screens in
            if !screens.contains(where: { $0.dv_displayUUID == selectedScreenID }) {
                selectedScreenID = screens.first?.dv_displayUUID ?? ""
            }
        }
        .onChange(of: selectedScreenID) { newID in
            BookmarkStore.set(newID, prefix: "lastScreen", id: 0)
            if let screen = screenObserver.screens.first(where: { $0.dv_displayUUID == newID }) {
                dlog("selected screen changed to \(screen.dv_localizedName)")
            } else {
                dlog("selected screen changed to \(newID)")
            }
        }
    }
}

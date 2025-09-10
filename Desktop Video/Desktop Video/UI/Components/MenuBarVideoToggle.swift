import SwiftUI

struct MenuBarVideoToggle: View {
    @AppStorage("showMenuBarVideo") private var showMenuBarVideo: Bool = false

    var body: some View {
        ToggleRow(title: LocalizedStringKey(L("ShowVideoInMenuBar")), value: $showMenuBarVideo)
            .onChange(of: showMenuBarVideo) { newValue in
                dlog("showMenuBarVideo changed to \(newValue)")
                SharedWallpaperWindowManager.shared.updateStatusBarVideoForAllScreens()
            }
    }
}

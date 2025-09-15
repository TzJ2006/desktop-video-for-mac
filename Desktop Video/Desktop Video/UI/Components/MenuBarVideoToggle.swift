import SwiftUI

struct MenuBarVideoToggle: View {
    @AppStorage("showInMenuBar") private var showMenuBarVideo: Bool = false

    var body: some View {
        ToggleRow(title: LocalizedStringKey(L("ShowVideoInMenuBar")), value: $showMenuBarVideo)
            .onChange(of: showMenuBarVideo) { newValue in
                dlog("showMenuBarVideo changed to \(newValue)")
                Settings.shared.showInMenuBar = newValue
                Task { @MainActor in
                    WindowManager.shared.startForAllScreens()
                }
            }
            .onAppear {
                Settings.shared.showInMenuBar = showMenuBarVideo
            }
    }
}

import SwiftUI

struct AppMainWindow: View {
    @StateObject var appVM = AppViewModel()
    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $appVM.selection)
                .background(.regularMaterial)
            ScrollView {
                VStack(spacing: 16) {
                    switch appVM.selection {
                    case .startup:
                        StartupDisplayView()
                    case .custom:
                        CustomControlsView()
                    case .battery:
                        BatteryChargingView()
                    }
                }
                .padding(24)
            }
        }
    }
}

#if DEBUG
struct AppMainWindow_Previews: PreviewProvider {
    static var previews: some View {
        AppMainWindow()
            .frame(width: 900, height: 600)
    }
}
#endif

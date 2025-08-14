import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection
    var body: some View {
        VStack(spacing: 16) {
            VStack {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                Text("v1.0")
                    .font(.footnote)
            }
            .padding(.top, 24)
            ForEach(SidebarSelection.allCases, id: \.self) { item in
                switch item {
                case .startup:
                    SidebarItem(icon: "bolt.circle", nameKey: "startup_display", selection: item, current: $selection)
                case .custom:
                    SidebarItem(icon: "slider.horizontal.3", nameKey: "custom_controls", selection: item, current: $selection)
                case .battery:
                    SidebarItem(icon: "battery.100", nameKey: "battery_charging", selection: item, current: $selection)
                }
            }
            Spacer()
        }
        .frame(width: 220)
        .padding(.vertical, 24)
    }
}

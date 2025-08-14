import SwiftUI

struct StartupDisplayView: View {
    @StateObject var vm = StartupDisplayVM()
    var body: some View {
        CardSection(titleKey: "startup_display", systemImage: "bolt.circle", helpKey: "startup_help") {
            ToggleRow(titleKey: "launch_at_login", value: $vm.launchAtLogin)
            PickerRow("language", selection: $vm.language.intBinding) {
                Text("English").tag(0)
                Text("中文").tag(1)
            }
            PickerRow("status_bar_style", selection: $vm.statusBarStyle) {
                Text("battery").tag(0)
                Text("battery_percent").tag(1)
            }
        }
    }
}

#if DEBUG
struct StartupDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        StartupDisplayView()
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif

private extension Binding where Value == String {
    var intBinding: Binding<Int> {
        Binding<Int>(
            get: { Int(self.wrappedValue) ?? 0 },
            set: { self.wrappedValue = String($0) }
        )
    }
}

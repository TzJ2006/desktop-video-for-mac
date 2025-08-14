import SwiftUI

struct CustomControlsView: View {
    @StateObject var vm = CustomControlsVM()
    var body: some View {
        CardSection(titleKey: "custom_controls", systemImage: "slider.horizontal.3", helpKey: "custom_help") {
            ToggleRow(titleKey: "thermal_protection", value: $vm.thermalProtection)
            StepperRow(titleKey: "max_temperature", value: $vm.maxTemperature)
            PickerRow("sleep_action", selection: $vm.sleepAction) {
                Text("stop_charging").tag(0)
                Text("keep_unchanged").tag(1)
            }
            PickerRow("exceed_action", selection: $vm.exceedAction) {
                Text("stop_charging").tag(0)
                Text("keep_unchanged").tag(1)
            }
        }
    }
}

#if DEBUG
struct CustomControlsView_Previews: PreviewProvider {
    static var previews: some View {
        CustomControlsView()
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif

import SwiftUI

struct BatteryChargingView: View {
    @StateObject var vm = BatteryChargingVM()
    var body: some View {
        CardSection(titleKey: "battery_charging", systemImage: "battery.100", helpKey: "battery_help") {
            SliderRow(titleKey: "charge_limit", value: $vm.chargeLimit, range: 0...1)
            MetricRow(titleKey: "current_capacity", value: vm.currentCapacity, footnote: nil)
            MetricRow(titleKey: "design_capacity", value: vm.designCapacity, footnote: nil)
        }
    }
}

#if DEBUG
struct BatteryChargingView_Previews: PreviewProvider {
    static var previews: some View {
        BatteryChargingView()
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif

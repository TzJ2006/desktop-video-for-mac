import SwiftUI

/// View model for the Battery & Charging section.
final class BatteryChargingVM: ObservableObject {
    @AppStorage("chargeLimit") var chargeLimit: Double = 0.8
    // Example read-only metrics; in real app these would come from system APIs.
    @Published var currentCapacity: String = "--"
    @Published var designCapacity: String = "--"
}

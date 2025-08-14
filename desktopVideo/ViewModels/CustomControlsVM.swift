import SwiftUI

/// View model for the Custom Controls section.
final class CustomControlsVM: ObservableObject {
    @AppStorage("thermalProtection") var thermalProtection: Bool = false
    @AppStorage("maxTemperature") var maxTemperature: Int = 60
    @AppStorage("sleepAction") var sleepAction: Int = 0
    @AppStorage("exceedAction") var exceedAction: Int = 0
}

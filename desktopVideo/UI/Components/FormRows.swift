import SwiftUI

struct ToggleRow: View {
    let titleKey: LocalizedStringKey
    @Binding var value: Bool
    var body: some View {
        Toggle(titleKey, isOn: $value)
    }
}

struct SliderRow: View {
    let titleKey: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double>
    var body: some View {
        VStack(alignment: .leading) {
            Text(titleKey)
            Slider(value: $value, in: range)
        }
    }
}

struct StepperRow: View {
    let titleKey: LocalizedStringKey
    @Binding var value: Int
    var body: some View {
        Stepper(value: $value) {
            Text(titleKey)
        }
    }
}

struct PickerRow<Content: View>: View {
    let titleKey: LocalizedStringKey
    @Binding var selection: Int
    let content: Content
    init(_ titleKey: LocalizedStringKey, selection: Binding<Int>, @ViewBuilder content: () -> Content) {
        self.titleKey = titleKey
        self._selection = selection
        self.content = content()
    }
    var body: some View {
        Picker(titleKey, selection: $selection) {
            content
        }
    }
}

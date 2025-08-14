
import SwiftUI

struct ToggleRow: View {
    let title: LocalizedStringKey
    @Binding var value: Bool
    var body: some View { Toggle(title, isOn: $value) }
}

struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double>
    var body: some View {
        VStack(alignment: .center) {
            Text(title)
            Slider(value: $value, in: range)
        }
    }
}

struct StepperRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    var body: some View {
        Stepper(value: $value) { Text(title) }
    }
}

struct PickerRow<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Int
    let content: Content
    init(_ title: LocalizedStringKey, selection: Binding<Int>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content()
    }
    var body: some View { Picker(title, selection: $selection) { content } }
}

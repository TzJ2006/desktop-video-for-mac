// periphery:ignore:all - parked for future use

import SwiftUI

struct ToggleRow: View {
    let title: LocalizedStringKey
    @Binding var value: Bool
    var body: some View {
        Toggle(title, isOn: $value)
            .font(.system(size: 15))
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double>
    var body: some View {
        VStack(alignment: .center) {
            Text(title).font(.system(size: 15))
            Slider(value: $value, in: range)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SliderInputRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double>

    private let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 0
        f.maximum = 100
        return f
    }()

    var body: some View {
        VStack(alignment: .center) {
            HStack {
                Text(title).font(.system(size: 15))
                Slider(value: $value, in: range).font(.system(size: 15))
                TextField("", value: $value, formatter: numberFormatter)
                    .frame(width: 40)
                    .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct StepperRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    var body: some View {
        Stepper(value: $value) { Text(title).font(.system(size: 15)) }
            .frame(maxWidth: .infinity, alignment: .center)
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
    var body: some View {
        Picker(title, selection: $selection) { content }
            .font(.system(size: 15))
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

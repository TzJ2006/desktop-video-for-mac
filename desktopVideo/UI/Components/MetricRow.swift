import SwiftUI

struct MetricRow: View {
    let titleKey: LocalizedStringKey
    let value: String
    let footnote: String?
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(titleKey)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
            }
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

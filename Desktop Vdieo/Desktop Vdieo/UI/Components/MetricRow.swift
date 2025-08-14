
import SwiftUI

struct MetricRow: View {
    let title: LocalizedStringKey
    let value: String
    let footnote: String?
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                if #available(macOS 12.0, *) {
                    Text(value).foregroundStyle(.secondary)
                } else {
                    // Fallback on earlier versions
                }
            }
            if let footnote {
                if #available(macOS 12.0, *) {
                    Text(footnote).font(.footnote).foregroundStyle(.secondary)
                } else {
                    // Fallback on earlier versions
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

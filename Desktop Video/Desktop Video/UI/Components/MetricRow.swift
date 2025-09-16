// periphery:ignore:all - parked for future use

import SwiftUI

struct MetricRow: View {
    let title: LocalizedStringKey
    let value: String
    let footnote: String?
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title).font(.system(size: 15))
                Spacer()
                Text(value).font(.system(size: 15)).foregroundStyle(.secondary)
            }
            if let footnote {
                Text(footnote).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

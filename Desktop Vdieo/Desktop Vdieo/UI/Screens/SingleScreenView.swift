
import SwiftUI

/// Placeholder - wire this up to your actual wallpaper window manager.
struct SingleScreenView: View {
    @State private var volume: Double = 1.0
    @State private var stretchToFill: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Choose Video…") { /* open panel */ }
                Button("Clear") { /* clear */ }
            }
            SliderRow(title: "Volume", value: $volume, range: 0...1)
            ToggleRow(title: "Stretch to fill", value: $stretchToFill)
        }
    }
}

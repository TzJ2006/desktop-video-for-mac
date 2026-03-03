import SwiftUI
import AppKit

/// White text on transparent background — used to generate a CGImage mask for the blur layer.
struct ScreensaverClockMask: View {
    var dateText: String
    var timeText: String

    var body: some View {
        VStack(spacing: 8) {
            Text(timeText)
                .font(.system(size: 96, weight: .regular, design: .rounded).monospacedDigit())
            Text(dateText)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// Gradient highlight text overlay — no blur, purely decorative specular highlight.
struct ScreensaverClockHighlight: View {
    var dateText: String
    var timeText: String

    var body: some View {
        VStack(spacing: 8) {
            highlightText(timeText, font: .system(size: 96, weight: .regular, design: .rounded).monospacedDigit())
            highlightText(dateText, font: .system(size: 28, weight: .semibold, design: .rounded))
        }
        .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 12)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func highlightText(_ text: String, font: Font) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(
                LinearGradient(
                    colors: [.white.opacity(0.85), .white.opacity(0.85), .white.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
    }
}

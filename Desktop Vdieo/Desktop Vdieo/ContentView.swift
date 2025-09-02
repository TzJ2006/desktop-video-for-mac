
import SwiftUI

/// Root view for the app. Hosts the new sidebar-based preferences window.
struct ContentView: View {
    var body: some View {
        AppMainWindow()
            // Set a more balanced default window size (about 30% smaller)
            .frame(minWidth: 630, minHeight: 420)
    }
}

#Preview { ContentView() }

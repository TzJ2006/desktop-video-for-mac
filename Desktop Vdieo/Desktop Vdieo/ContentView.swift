
import SwiftUI

/// Root view for the app. Hosts the new sidebar-based preferences window.
struct ContentView: View {
    var body: some View {
        AppMainWindow()
            // Set a more balanced default window size
            .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview { ContentView() }

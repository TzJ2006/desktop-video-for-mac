
import SwiftUI

/// Root view for the app. Hosts the new sidebar-based preferences window.
struct ContentView: View {
    var body: some View {
        AppMainWindow()
            .frame(minWidth: 820, minHeight: 520)
    }
}

#Preview { ContentView() }

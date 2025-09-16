
import SwiftUI
import AppKit

/// Root view for the app. Hosts the new sidebar-based preferences window.
struct ContentView: View {
    var body: some View {
        AppMainWindow()
            .frame(minWidth: 720, minHeight: 480)
            .background(MainWindowBridge())
    }
}

#Preview { ContentView() }

private struct MainWindowBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        dlog("MainWindowBridge makeNSView")
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            self.register(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        dlog("MainWindowBridge updateNSView")
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            self.register(window: window)
        }
    }

    private func register(window: NSWindow) {
        dlog("MainWindowBridge register windowIdentifier=\(window.identifier?.rawValue ?? "nil")")
        if window.identifier?.rawValue != "MainWindow" {
            window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        }
        AppDelegate.shared?.adoptMainWindowIfNeeded(window)
    }
}

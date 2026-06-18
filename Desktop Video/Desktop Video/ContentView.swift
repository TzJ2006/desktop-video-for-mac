import SwiftUI
import AppKit

/// Root view for the app. Hosts the new sidebar-based preferences window.
struct ContentView: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        GlassEffectContainer {
            AppMainWindow()
                .frame(minWidth: AppMainWindow.minWidth, minHeight: AppMainWindow.minHeight)
        }
        .glassWindowBackground()
        .background(MainWindowBridge())
        .applyTheme(themeManager)
    }
}

#Preview { ContentView() }

private struct MainWindowBridge: NSViewRepresentable {
    @ObservedObject private var themeManager = ThemeManager.shared

    func makeNSView(context: Context) -> NSView {
        dlog("MainWindowBridge makeNSView")
        return GlassWindowConfigurator()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? GlassWindowConfigurator)?.applyIfPossible(themeManager: themeManager)
    }
}

/// 一旦加入窗口层级即「同步」配置主窗口：设置标识符 + 应用整窗 liquid glass 外观。
/// 用 `viewDidMoveToWindow`（首帧前触发）而非 `DispatchQueue.main.async`（下一 runloop），
/// 避免窗口先以不透明背景显示再变半透明的首帧闪烁。
private final class GlassWindowConfigurator: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyIfPossible()
    }

    func applyIfPossible(themeManager: ThemeManager = .shared) {
        guard let window else { return }
        if window.identifier?.rawValue != "MainWindow" {
            window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        }
        window.applyGlassWindowStyle()
        AppDelegate.shared?.adoptMainWindowIfNeeded(window)
    }
}

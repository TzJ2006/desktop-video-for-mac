import Cocoa
import ScreenCaptureKit

@MainActor
final class WallpaperWindowController: NSWindowController {
    var observations: [NSKeyValueObservation] = []
    var stream: SCStream?
    var displayLink: CVDisplayLink?
    var timers: [Timer] = []

    init(window: WallpaperWindow) {
        super.init(window: window)
        window.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func start(on screen: NSScreen) {
        guard let window = window as? WallpaperWindow else { return }
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
    }

    func stop() {
        if let stream {
            try? stream.stopCapture()
            self.stream = nil
        }
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        NotificationCenter.default.removeObserver(self)
        if let window = window as? WallpaperWindow {
            window.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            window.orderOut(nil)
        }
        window = nil
    }

    deinit {
        assertMainThread()
    }
}

import AppKit

/// Mirrors a foreign menu bar overlay window (e.g. Ice) and renders our
/// content above it while staying click-through.
///
/// Apple Developer Documentation references:
/// - NSWindow.Level: https://developer.apple.com/documentation/appkit/nswindow/level
/// - NSWindow.orderFrontRegardless(): https://developer.apple.com/documentation/appkit/nswindow/1419654-orderfrontregardless
@MainActor
final class ForeignMenuBarMirrorController {
    enum Style {
        case full
        case split
    }

    private let screen: NSScreen
    private var panel: NSPanel?
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var currentOverlayFrame: CGRect?

    var style: Style = .split {
        didSet {
            dlog("ForeignMenuBarMirrorController style changed to \(style)")
            overlayView?.style = style
        }
    }

    var drawBackground: ((CGContext, CGRect) -> Void)? {
        didSet {
            dlog("ForeignMenuBarMirrorController drawBackground updated != nil? \(drawBackground != nil)")
            overlayView?.drawBackground = drawBackground
        }
    }

    var onGeometryChange: ((CGRect) -> Void)?

    var mirroredScreen: NSScreen { screen }

    init(screen: NSScreen) {
        self.screen = screen
        dlog("ForeignMenuBarMirrorController init for \(screen.dv_localizedName)")
    }

    func start() {
        dlog("ForeignMenuBarMirrorController.start on \(screen.dv_localizedName)")
        guard Settings.shared.showInMenuBar else {
            dlog("ForeignMenuBarMirrorController.start aborted because showInMenuBar is disabled", level: .warn)
            return
        }
        ensurePanel()
        installObserversIfNeeded()
        scheduleRefreshTimer()
        refresh()
    }

    func stop() {
        dlog("ForeignMenuBarMirrorController.stop on \(screen.dv_localizedName)")
        refreshTimer?.invalidate()
        refreshTimer = nil
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
        if let panel {
            panel.orderOut(nil)
            panel.close()
        }
        panel = nil
        currentOverlayFrame = nil
    }

    func refresh() {
        dlog("ForeignMenuBarMirrorController.refresh on \(screen.dv_localizedName)")
        guard Settings.shared.showInMenuBar else {
            dlog("ForeignMenuBarMirrorController.refresh detected disabled setting; stopping")
            stop()
            return
        }
        guard let target = CGWindowScanner.findForeignMenuBarOverlay(on: screen) else {
            dlog("ForeignMenuBarMirrorController.refresh no target overlay", level: .warn)
            currentOverlayFrame = nil
            panel?.orderOut(nil)
            overlayView?.alphaValue = 0
            return
        }
        ensurePanel()
        currentOverlayFrame = target.bounds
        let appFrame = MenuBarGeometry.appMenuFrame(on: screen)
        let statusFrame = MenuBarGeometry.statusItemsFrame(on: screen)
        overlayView?.alphaValue = 1
        overlayView?.isInsetForNotch = screen.hasNotch
        overlayView?.updateGeometry(
            overlayFrame: target.bounds,
            appFrame: appFrame,
            statusFrame: statusFrame,
            screen: screen,
            style: style
        )
        panel?.setFrame(target.bounds, display: false)
        panel?.ignoresMouseEvents = true
        panel?.orderFrontRegardless()
        onGeometryChange?(target.bounds)
    }

    func setHostedView(_ view: NSView) {
        dlog("ForeignMenuBarMirrorController.setHostedView on \(screen.dv_localizedName)")
        ensurePanel()
        overlayView?.setHostedView(view)
    }

    func removeHostedView() {
        dlog("ForeignMenuBarMirrorController.removeHostedView on \(screen.dv_localizedName)")
        overlayView?.removeHostedView()
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        dlog("ForeignMenuBarMirrorController.ensurePanel for \(screen.dv_localizedName)")
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .stationary]
        panel.isReleasedWhenClosed = false
        let view = MirrorOverlayView(frame: .zero)
        view.drawBackground = drawBackground
        view.style = style
        view.isInsetForNotch = screen.hasNotch
        panel.contentView = view
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        dlog("ForeignMenuBarMirrorController.installObserversIfNeeded for \(screen.dv_localizedName)")
        let workspace = NSWorkspace.shared
        observers.append(workspace.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.throttledRefresh() }
        })
        observers.append(workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.throttledRefresh() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeEffectiveAppearanceNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.throttledRefresh() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.throttledRefresh() }
        })
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        dlog("ForeignMenuBarMirrorController.scheduleRefreshTimer for \(screen.dv_localizedName)")
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func throttledRefresh() {
        dlog("ForeignMenuBarMirrorController.throttledRefresh for \(screen.dv_localizedName)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private var overlayView: MirrorOverlayView? {
        panel?.contentView as? MirrorOverlayView
    }
}

// MARK: - Overlay View

@MainActor
private final class MirrorOverlayView: NSView {
    var style: ForeignMenuBarMirrorController.Style = .split {
        didSet {
            dlog("MirrorOverlayView.style didSet -> \(style)")
            rebuildMask()
        }
    }

    var drawBackground: ((CGContext, CGRect) -> Void)? {
        didSet { setNeedsDisplay(bounds) }
    }

    var isInsetForNotch: Bool = true {
        didSet {
            dlog("MirrorOverlayView.isInsetForNotch didSet -> \(isInsetForNotch)")
            rebuildMask()
        }
    }

    private var overlayFrame: CGRect = .zero
    private var globalAppFrame: CGRect = .zero
    private var globalStatusFrame: CGRect = .zero
    private weak var screen: NSScreen?
    private let maskLayer = CAShapeLayer()
    private weak var hostedView: NSView?
    private var cachedPath: NSBezierPath?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        layer?.mask = maskLayer
        dlog("MirrorOverlayView.init")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateGeometry(
        overlayFrame: CGRect,
        appFrame: CGRect,
        statusFrame: CGRect,
        screen: NSScreen,
        style: ForeignMenuBarMirrorController.Style
    ) {
        dlog("MirrorOverlayView.updateGeometry overlay=\(NSStringFromRect(NSRectFromCGRect(overlayFrame)))")
        self.overlayFrame = overlayFrame
        self.globalAppFrame = appFrame
        self.globalStatusFrame = statusFrame
        self.screen = screen
        if self.style != style {
            self.style = style
        }
        setFrameOrigin(.zero)
        setFrameSize(overlayFrame.size)
        rebuildMask()
        needsDisplay = true
        needsLayout = true
    }

    func setHostedView(_ view: NSView) {
        dlog("MirrorOverlayView.setHostedView \(view)")
        if hostedView !== view {
            hostedView?.removeFromSuperview()
            hostedView = view
            addSubview(view, positioned: .below, relativeTo: nil)
        }
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
    }

    func removeHostedView() {
        dlog("MirrorOverlayView.removeHostedView")
        hostedView?.removeFromSuperview()
        hostedView = nil
    }

    override func layout() {
        super.layout()
        hostedView?.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard let path = cachedPath else { return }
        context.saveGState()
        context.addPath(path.cgPath)
        context.clip(using: .evenOdd)
        drawBackground?(context, bounds)
        context.restoreGState()
    }

    private func rebuildMask() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let screen else { return }
        let localApp = convertToLocal(globalAppFrame)
        let localStatus = convertToLocal(globalStatusFrame)
        let notchInsets = resolveNotchInsets(for: screen)
        let info = MenuBarShapeBuilder.ShapeInfo(
            bandRect: bounds,
            applicationMenuRect: localApp,
            statusItemsRect: localStatus,
            notchInsets: notchInsets
        )
        let path: NSBezierPath
        switch style {
        case .full:
            path = MenuBarShapeBuilder.fullPath(in: bounds, info: info, isInset: isInsetForNotch, screen: screen)
        case .split:
            path = MenuBarShapeBuilder.splitPath(in: bounds, info: info, isInset: isInsetForNotch, screen: screen)
        }
        cachedPath = path
        maskLayer.frame = bounds
        maskLayer.path = path.cgPath
        needsDisplay = true
    }

    private func convertToLocal(_ rect: CGRect) -> CGRect {
        guard overlayFrame.width > 0, overlayFrame.height > 0 else { return .zero }
        var local = rect
        local.origin.x -= overlayFrame.minX
        local.origin.y -= overlayFrame.minY
        local.origin.x = max(local.origin.x, bounds.minX)
        local.origin.y = max(local.origin.y, bounds.minY)
        let maxWidth = bounds.maxX - local.origin.x
        let maxHeight = bounds.maxY - local.origin.y
        local.size.width = min(max(local.size.width, 0), maxWidth)
        local.size.height = min(max(local.size.height, 0), maxHeight)
        if local.isNull || local.isEmpty { return .zero }
        return local
    }

    private func resolveNotchInsets(for screen: NSScreen) -> NSEdgeInsets {
        guard isInsetForNotch else { return NSEdgeInsets() }
        guard screen.hasNotch else { return NSEdgeInsets() }
        if #available(macOS 12.0, *) {
            let frame = screen.frame
            let safe = screen.safeAreaRect
            let left = max(safe.minX - frame.minX, 0)
            let right = max(frame.maxX - safe.maxX, 0)
            return NSEdgeInsets(top: 0, left: left, bottom: 0, right: right)
        } else {
            return NSEdgeInsets()
        }
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            let type = element(at: index, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }
}

private extension NSScreen {
    var hasNotch: Bool {
        if #available(macOS 12.0, *) {
            let frame = frame
            let safe = safeAreaRect
            return safe.width < frame.width - 1 || safe.minY > frame.minY
        } else {
            return false
        }
    }
}

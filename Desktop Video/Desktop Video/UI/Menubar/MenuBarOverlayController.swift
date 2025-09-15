// periphery:ignore:all - parked for future use
import AppKit

/// Controls a transparent overlay panel that sits above Ice's menu bar
/// background while leaving the system menu items untouched.
@MainActor
final class MenuBarOverlayController {
    enum Style {
        case full
        case split
    }

    let screen: NSScreen
    private let panel: NSPanel
    private let overlayView: OverlayContentView

    /// Closure invoked when the overlay needs to paint its background.
    /// The context is already clipped to the carved path.
    var drawBackground: ((CGContext, CGRect) -> Void)? {
        didSet { overlayView.drawBackground = drawBackground }
    }

    var style: Style {
        didSet {
            dlog("MenuBarOverlayController style changed to \(style)")
            overlayView.style = style
            overlayView.needsDisplay = true
        }
    }

    var contentView: NSView { overlayView }

    init(screen: NSScreen, style: Style = .full) {
        self.screen = screen
        self.style = style
        let band = MenuBarGeometry.menuBarBandFrame(on: screen)
        dlog("init MenuBarOverlayController for \(screen.dv_localizedName) band=\(NSStringFromRect(band)) style=\(style)")
        self.panel = MenuBarOverlayController.makePanel(frame: band)
        self.overlayView = OverlayContentView(frame: CGRect(origin: .zero, size: band.size))
        self.overlayView.style = style
        self.overlayView.drawBackground = drawBackground
        self.panel.contentView = overlayView
        updateGeometry()
    }

    func show() {
        dlog("show overlay for \(screen.dv_localizedName)")
        panel.orderFrontRegardless()
    }

    func hide() {
        dlog("hide overlay for \(screen.dv_localizedName)")
        panel.orderOut(nil)
    }

    func updateGeometry() {
        let band = MenuBarGeometry.menuBarBandFrame(on: screen)
        let appRect = MenuBarGeometry.appMenuFrame(on: screen)
        let statusRect = MenuBarGeometry.statusItemsFrame(on: screen)
        dlog(
            "updateGeometry for \(screen.dv_localizedName) band=\(NSStringFromRect(band)) app=\(NSStringFromRect(appRect)) status=\(NSStringFromRect(statusRect))"
        )
        panel.setFrame(band, display: false)
        overlayView.updateGeometry(band: band, appRect: appRect, statusRect: statusRect)
        overlayView.drawBackground = drawBackground
    }

    private static func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
//        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

// MARK: - Overlay view

private final class OverlayContentView: NSView {
    var style: MenuBarOverlayController.Style = .full {
        didSet { rebuildMaskPath() }
    }

    var drawBackground: ((CGContext, CGRect) -> Void)?

    private let maskLayer = CAShapeLayer()
    private var bandFrame: CGRect = .zero
    private var appFrame: CGRect = .zero
    private var statusFrame: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        layer?.mask = maskLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateGeometry(band: CGRect, appRect: CGRect, statusRect: CGRect) {
        dlog("OverlayContentView.updateGeometry band=\(NSStringFromRect(band))")
        bandFrame = band
        appFrame = appRect
        statusFrame = statusRect
        setFrameOrigin(.zero)
        setFrameSize(band.size)
        rebuildMaskPath()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard let maskPath = maskLayer.path else { return }
        context.saveGState()
        context.addPath(maskPath)
        context.clip(using: .evenOdd)
        drawBackground?(context, bounds)
        context.restoreGState()
    }

    private func rebuildMaskPath() {
        guard let layer else { return }
        let localApp = convertToLocal(appFrame)
        let localStatus = convertToLocal(statusFrame)
        dlog(
            "rebuildMaskPath style=\(style) localApp=\(NSStringFromRect(localApp)) localStatus=\(NSStringFromRect(localStatus))"
        )
        let path = CGMutablePath()
        let boundsRect = bounds
        let radius = boundsRect.height / 2
        switch style {
        case .full:
            let capsule = NSBezierPath(roundedRect: boundsRect, xRadius: radius, yRadius: radius)
            path.addPath(capsule.cgPath)
        case .split:
            let leftWidth = max(localApp.width + 24, boundsRect.height)
            let rightWidth = max(localStatus.width + 24, boundsRect.height)
            let leftRect = CGRect(x: boundsRect.minX, y: boundsRect.minY, width: min(leftWidth, boundsRect.width), height: boundsRect.height)
            let rightRect = CGRect(
                x: max(boundsRect.maxX - rightWidth, boundsRect.minX),
                y: boundsRect.minY,
                width: min(rightWidth, boundsRect.width),
                height: boundsRect.height
            )
            path.addPath(NSBezierPath(roundedRect: leftRect, xRadius: radius, yRadius: radius).cgPath)
            if rightRect.width > 0 {
                path.addPath(NSBezierPath(roundedRect: rightRect, xRadius: radius, yRadius: radius).cgPath)
            }
        }
        if !localApp.isEmpty && !localApp.isNull {
            path.addRect(localApp)
        }
        if !localStatus.isEmpty && !localStatus.isNull {
            path.addRect(localStatus)
        }
        maskLayer.frame = boundsRect
        maskLayer.path = path
        layer.mask = maskLayer
        needsDisplay = true
    }

    private func convertToLocal(_ rect: CGRect) -> CGRect {
        guard !bandFrame.isEmpty else { return .zero }
        var local = rect
        local.origin.x -= bandFrame.minX
        local.origin.y -= bandFrame.minY
        local.origin.x = max(local.origin.x, bounds.minX)
        local.origin.y = max(local.origin.y, bounds.minY)
        local.size.width = min(local.size.width, bounds.width - local.origin.x)
        local.size.height = min(local.size.height, bounds.height - local.origin.y)
        return local
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

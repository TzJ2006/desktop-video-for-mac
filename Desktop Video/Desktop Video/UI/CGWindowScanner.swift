import AppKit
import CoreGraphics

public struct ForeignOverlay {
    public let windowID: CGWindowID
    public let ownerName: String
    public let bounds: CGRect
    public let layer: Int
}

@MainActor
public enum CGWindowScanner {
    private static let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    private static let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))

    /// Enumerates visible windows using `CGWindowListCopyWindowInfo`.
    /// See Apple Developer Documentation: https://developer.apple.com/documentation/coregraphics/1454737-cgwindowlistcopywindowinfo
    public static func onScreenWindows() -> [ForeignOverlay] {
        dlog("CGWindowScanner.onScreenWindows begin")
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            dlog("CGWindowScanner.onScreenWindows no window info", level: .warn)
            return []
        }
        var overlays: [ForeignOverlay] = []
        overlays.reserveCapacity(list.count)
        for entry in list {
            guard
                let windowID = entry[kCGWindowNumber as String] as? UInt32,
                let ownerName = entry[kCGWindowOwnerName as String] as? String,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let bounds = rect(from: entry[kCGWindowBounds as String])
            else {
                continue
            }
            overlays.append(ForeignOverlay(windowID: windowID, ownerName: ownerName, bounds: bounds, layer: layer))
        }
        dlog("CGWindowScanner.onScreenWindows count=\(overlays.count)")
        return overlays
    }

    /// Returns the menu bar band rect for a given screen. Uses `NSStatusBar.system.thickness`
    /// as the base height and refines it using the actual main menu CGWindow if available.
    /// Apple Developer Documentation references:
    /// - NSStatusBar.system.thickness: https://developer.apple.com/documentation/appkit/nsstatusbar/1532651-system
    /// - CGWindowLevelForKey: https://developer.apple.com/documentation/coregraphics/1418284-cgwindowlevelforkey
    public static func menuBarBand(on screen: NSScreen) -> CGRect {
        let baseThickness = NSStatusBar.system.thickness
        var height = baseThickness
        let screenFrame = screen.frame
        let probingBand = CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - baseThickness * 2,
            width: screenFrame.width,
            height: baseThickness * 2
        )
        let candidates = onScreenWindows().filter { overlay in
            overlay.layer == mainMenuLevel && overlay.bounds.intersects(probingBand)
        }
        if let measuredHeight = candidates.map({ $0.bounds.height }).max(), measuredHeight > 0 {
            height = max(height, measuredHeight)
        }
        let resolved = CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - height,
            width: screenFrame.width,
            height: height
        )
        dlog("CGWindowScanner.menuBarBand for \(screen.dv_localizedName) -> \(NSStringFromRect(resolved))")
        return resolved
    }

    /// Attempts to locate a third-party menu bar overlay (such as Ice) that intersects the
    /// computed menu bar band on the supplied screen. Prefers the Ice window if present,
    /// otherwise selects the candidate with the largest intersection area.
    public static func findForeignMenuBarOverlay(on screen: NSScreen) -> ForeignOverlay? {
        dlog("CGWindowScanner.findForeignMenuBarOverlay on \(screen.dv_localizedName)")
        let band = menuBarBand(on: screen)
        let midPoint = CGPoint(x: band.midX, y: band.midY)
        let minLayer = mainMenuLevel
        let candidates = onScreenWindows().filter { overlay in
            guard overlay.layer >= minLayer else { return false }
            guard overlay.bounds.intersects(band) else { return false }
            return overlay.bounds.contains(midPoint)
        }
        if let ice = candidates.first(where: { $0.ownerName == "Ice" }) {
            dlog("CGWindowScanner.findForeignMenuBarOverlay picked Ice windowID=\(ice.windowID)")
            return ice
        }
        let best = candidates.max { lhs, rhs in
            let lhsArea = lhs.bounds.intersection(band).area
            let rhsArea = rhs.bounds.intersection(band).area
            return lhsArea < rhsArea
        }
        if let best {
            dlog("CGWindowScanner.findForeignMenuBarOverlay picked best windowID=\(best.windowID) owner=\(best.ownerName)")
        } else {
            dlog("CGWindowScanner.findForeignMenuBarOverlay no candidate", level: .warn)
        }
        return best
    }

    private static func rect(from dictionary: [String: Any]?) -> CGRect? {
        guard let dict = dictionary else { return nil }
        guard
            let x = cgFloat(from: dict["X"]),
            let y = cgFloat(from: dict["Y"]),
            let width = cgFloat(from: dict["Width"]),
            let height = cgFloat(from: dict["Height"])
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private extension CGRect {
    var area: CGFloat { size.width * size.height }
}

private extension CGWindowScanner {
    static func cgFloat(from value: Any?) -> CGFloat? {
        if let cg = value as? CGFloat { return cg }
        if let double = value as? Double { return CGFloat(double) }
        if let int = value as? Int { return CGFloat(int) }
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        return nil
    }
}

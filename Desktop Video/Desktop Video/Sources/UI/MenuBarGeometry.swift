import AppKit
import ApplicationServices

/// Helpers for obtaining menu bar geometry on a given display.
///
/// The functions in this namespace run on the main actor because they need to
/// talk to AppKit and query the live window list.
@MainActor
enum MenuBarGeometry {
    private static let selfPID: pid_t = pid_t(ProcessInfo.processInfo.processIdentifier)
    private static let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
    private static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    private static let carveInset: CGFloat = 4

    /// Returns the best-guess menu bar height for a screen.
    static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        let baseHeight = NSStatusBar.system.thickness
        let backgroundHeight = collectMenuWindows(on: screen)
            .filter { $0.frame.width >= screen.frame.width * 0.6 }
            .map { $0.frame.height }
            .max() ?? 0
        let resolved = max(baseHeight, backgroundHeight)
        dlog(
            "menuBarHeight for \(screen.dv_localizedName) base=\(baseHeight) fallback=\(backgroundHeight) result=\(resolved)"
        )
        return resolved
    }

    /// Returns the full band rectangle of the menu bar on the target screen.
    static func menuBarBandFrame(on screen: NSScreen) -> CGRect {
        let height = menuBarHeight(for: screen)
        let frame = screen.frame
        let band = CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        dlog("menuBarBandFrame for \(screen.dv_localizedName) -> \(NSStringFromRect(band))")
        return band
    }

    /// Returns the bounding frame that covers the left-hand app menu titles.
    static func appMenuFrame(on screen: NSScreen) -> CGRect {
        let band = menuBarBandFrame(on: screen)
        let windows = collectMenuWindows(on: screen)
        let screenFrame = screen.frame
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName

        let candidates = windows.filter { info in
            guard info.frame.width < screenFrame.width * 0.9 else { return false }
            if let frontApp, info.ownerName == frontApp { return true }
            return info.frame.midX <= screenFrame.midX
        }

        var unionRect = union(of: candidates)
        if unionRect.isNull || unionRect.isEmpty {
            let fallbackWidth = min(240, band.width * 0.5)
            unionRect = CGRect(
                x: band.minX,
                y: band.minY,
                width: fallbackWidth,
                height: band.height
            )
        } else {
            unionRect.origin.y = band.minY
            unionRect.size.height = band.height
            unionRect.origin.x = max(unionRect.origin.x - carveInset, band.minX)
            unionRect.size.width = min(
                unionRect.width + carveInset * 2,
                band.maxX - unionRect.minX
            )
        }

        dlog(
            "appMenuFrame for \(screen.dv_localizedName) -> \(NSStringFromRect(unionRect)) candidates=\(candidates.count)"
        )
        return unionRect
    }

    /// Returns the bounding frame that covers the right-hand status items.
    static func statusItemsFrame(on screen: NSScreen) -> CGRect {
        let band = menuBarBandFrame(on: screen)
        let windows = collectMenuWindows(on: screen)
        let screenFrame = screen.frame

        let candidates = windows.filter { info in
            guard info.frame.width < screenFrame.width * 0.9 else { return false }
            return info.frame.midX >= screenFrame.midX
        }

        var unionRect = union(of: candidates)
        if unionRect.isNull || unionRect.isEmpty {
            let fallbackWidth = min(260, band.width * 0.5)
            unionRect = CGRect(
                x: band.maxX - fallbackWidth,
                y: band.minY,
                width: fallbackWidth,
                height: band.height
            )
        } else {
            unionRect.origin.y = band.minY
            unionRect.size.height = band.height
            let adjustedMinX = max(unionRect.minX - carveInset, band.minX)
            let adjustedMaxX = min(unionRect.maxX + carveInset, band.maxX)
            unionRect.origin.x = adjustedMinX
            unionRect.size.width = adjustedMaxX - adjustedMinX
        }

        dlog(
            "statusItemsFrame for \(screen.dv_localizedName) -> \(NSStringFromRect(unionRect)) candidates=\(candidates.count)"
        )
        return unionRect
    }

    // MARK: - Private helpers

    private static func collectMenuWindows(on screen: NSScreen) -> [MenuWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            dlog("collectMenuWindows -> no window info", level: .warn)
            return []
        }

        let frame = screen.frame
        var windows: [MenuWindowInfo] = []
        for rawInfo in infoList {
            guard let layer = rawInfo[kCGWindowLayer as String] as? Int else { continue }
            if layer < menuLevel || layer > statusLevel + 2 { continue }
            if let ownerPID = rawInfo[kCGWindowOwnerPID as String] as? pid_t, ownerPID == selfPID {
                continue
            }
            guard let rect = rect(from: rawInfo), rect.intersects(frame) else { continue }
            let owner = rawInfo[kCGWindowOwnerName as String] as? String ?? ""
            let name = rawInfo[kCGWindowName as String] as? String
            let alpha = rawInfo[kCGWindowAlpha as String] as? Double ?? 1.0
            windows.append(MenuWindowInfo(frame: rect, ownerName: owner, windowName: name, layer: layer, alpha: alpha))
        }
        dlog(
            "collectMenuWindows for \(screen.dv_localizedName) -> count=\(windows.count)"
        )
        return windows
    }

    private static func rect(from info: [String: Any]) -> CGRect? {
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        guard
            let x = cgFloat(bounds["X"]),
            let y = cgFloat(bounds["Y"]),
            let width = cgFloat(bounds["Width"]),
            let height = cgFloat(bounds["Height"])
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let cg = value as? CGFloat { return cg }
        if let double = value as? Double { return CGFloat(double) }
        if let int = value as? Int { return CGFloat(int) }
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        return nil
    }

    private static func union(of windows: [MenuWindowInfo]) -> CGRect {
        windows.reduce(into: CGRect.null) { result, info in
            if result.isNull {
                result = info.frame
            } else {
                result = result.union(info.frame)
            }
        }
    }

    private struct MenuWindowInfo {
        let frame: CGRect
        let ownerName: String
        let windowName: String?
        let layer: Int
        let alpha: Double
    }
}

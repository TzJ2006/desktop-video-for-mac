import AppKit

/// Recreates the geometric mask used by Ice's menu bar overlay so that our
/// mirrored panel visually matches the foreign window. We cannot read the
/// other process's mask directly, so the path is reconstructed locally.
@MainActor
enum MenuBarShapeBuilder {
    struct ShapeInfo {
        let bandRect: CGRect
        let applicationMenuRect: CGRect
        let statusItemsRect: CGRect
        let notchInsets: NSEdgeInsets
    }

    static func fullPath(in rect: CGRect, info: ShapeInfo, isInset: Bool, screen: NSScreen) -> NSBezierPath {
        dlog(
            "MenuBarShapeBuilder.fullPath screen=\(screen.dv_localizedName) rect=\(NSStringFromRect(NSRectFromCGRect(rect)))"
        )
        let workingRect = inset(rect: rect, with: info.notchInsets, applyInset: isInset)
        let radius = workingRect.height / 2
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.append(NSBezierPath(roundedRect: workingRect, xRadius: radius, yRadius: radius))
        if info.applicationMenuRect.width > 1 { path.append(NSBezierPath(rect: info.applicationMenuRect)) }
        if info.statusItemsRect.width > 1 { path.append(NSBezierPath(rect: info.statusItemsRect)) }
        return path
    }

    static func splitPath(in rect: CGRect, info: ShapeInfo, isInset: Bool, screen: NSScreen) -> NSBezierPath {
        dlog(
            "MenuBarShapeBuilder.splitPath screen=\(screen.dv_localizedName) rect=\(NSStringFromRect(NSRectFromCGRect(rect)))"
        )
        let workingRect = inset(rect: rect, with: info.notchInsets, applyInset: isInset)
        let radius = workingRect.height / 2
        let minimumWidth = max(workingRect.height, 1)

        var leftWidth = max(info.applicationMenuRect.width, minimumWidth)
        leftWidth = min(leftWidth, workingRect.width)
        let leftRect = CGRect(
            x: workingRect.minX,
            y: workingRect.minY,
            width: leftWidth,
            height: workingRect.height
        )

        var rightWidth = max(info.statusItemsRect.width, minimumWidth)
        rightWidth = min(rightWidth, workingRect.width)
        var rightOriginX = workingRect.maxX - info.statusItemsRect.width
        if rightWidth > info.statusItemsRect.width { rightOriginX = workingRect.maxX - rightWidth }
        rightOriginX = max(rightOriginX, workingRect.minX)
        let rightRect = CGRect(
            x: rightOriginX,
            y: workingRect.minY,
            width: rightWidth,
            height: workingRect.height
        )

        if leftRect.maxX > rightRect.minX {
            let merged = fullPath(in: rect, info: info, isInset: isInset, screen: screen)
            dlog("MenuBarShapeBuilder.splitPath fallback to fullPath due to overlap", level: .warn)
            return merged
        }

        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.append(NSBezierPath(roundedRect: leftRect, xRadius: radius, yRadius: radius))
        path.append(NSBezierPath(roundedRect: rightRect, xRadius: radius, yRadius: radius))
        if info.applicationMenuRect.width > 1 { path.append(NSBezierPath(rect: info.applicationMenuRect)) }
        if info.statusItemsRect.width > 1 { path.append(NSBezierPath(rect: info.statusItemsRect)) }
        return path
    }

    private static func inset(rect: CGRect, with insets: NSEdgeInsets, applyInset: Bool) -> CGRect {
        guard applyInset else { return rect }
        var adjusted = rect
        adjusted.origin.x += insets.left
        adjusted.size.width -= (insets.left + insets.right)
        adjusted.size.width = max(adjusted.size.width, rect.height)
        return adjusted
    }
}

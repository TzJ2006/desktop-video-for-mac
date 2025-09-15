import Cocoa
import AVFoundation

/// 在菜单栏展示视频内容的窗口，并支持 Split 形状遮罩
class StatusBarVideoWindow: NSWindow {
    private var playerLayer: AVPlayerLayer?

    init(frame: CGRect, player: AVPlayer) {
        dlog("init StatusBarVideoWindow")
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        contentView = NSView(frame: frame)
        setupPlayer(player)
    }

    private func setupPlayer(_ player: AVPlayer) {
        let layer = AVPlayerLayer(player: player)
        layer.frame = contentView?.bounds ?? .zero
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.videoGravity = .resizeAspectFill
        contentView?.wantsLayer = true
        contentView?.layer?.addSublayer(layer)
        playerLayer = layer
        dlog("setup player layer for StatusBarVideoWindow")
    }

    /// 应用 Split 形状遮罩，使菜单栏中部透明
    func applySplitMask(gap: CGFloat, cornerRadius: CGFloat = 6) {
        dlog("apply split mask gap=\(gap) cornerRadius=\(cornerRadius)")
        let totalWidth = frame.width
        let height = frame.height
        let leftWidth = max(0, (totalWidth - gap) / 2)
        let rightX = leftWidth + gap
        let rightWidth = max(0, totalWidth - rightX)

        let path = NSBezierPath()
        if leftWidth > 0 {
            path.appendRoundedRect(NSRect(x: 0, y: 0, width: leftWidth, height: height), xRadius: cornerRadius, yRadius: cornerRadius)
        }
        if rightWidth > 0 {
            path.appendRoundedRect(NSRect(x: rightX, y: 0, width: rightWidth, height: height), xRadius: cornerRadius, yRadius: cornerRadius)
        }

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        mask.frame = CGRect(origin: .zero, size: CGSize(width: totalWidth, height: height))
        contentView?.layer?.mask = mask
    }
}

private extension NSBezierPath {
    /// 将 NSBezierPath 转换为 CGPath
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
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


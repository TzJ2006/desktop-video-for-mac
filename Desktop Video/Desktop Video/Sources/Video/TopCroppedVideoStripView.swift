import AppKit
import AVFoundation

/// Hosts a video layer that only reveals the top strip corresponding to the
/// menu bar height on a given screen.
@MainActor
final class TopCroppedVideoStripView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var naturalVideoSize: CGSize = .zero
    private var cachedBand: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        dlog("init TopCroppedVideoStripView")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(player: AVPlayer) {
        naturalVideoSize = resolvedNaturalSize(for: player)
        playerLayer.player = player
        dlog(
            "attach player to TopCroppedVideoStripView naturalSize=\(naturalVideoSize) itemDuration=\(String(describing: player.currentItem?.duration))"
        )
        updateLayerGeometry()
    }

    func updateLayout(for screen: NSScreen) {
        let band = MenuBarGeometry.menuBarBandFrame(on: screen)
        cachedBand = band
        dlog(
            "updateLayout for \(screen.dv_localizedName) band=\(NSStringFromRect(band)) naturalSize=\(naturalVideoSize)"
        )
        setFrameOrigin(.zero)
        setFrameSize(band.size)
        layer?.masksToBounds = true
        layer?.cornerRadius = band.height / 2
        updateLayerGeometry()
        playerLayer.contentsScale = screen.backingScaleFactor
    }

    private func updateLayerGeometry() {
        guard cachedBand.width > 0 else { return }
        let width = cachedBand.width
        var videoSize = naturalVideoSize
        if videoSize == .zero {
            videoSize = CGSize(width: width, height: cachedBand.height)
        }
        let clampedWidth = max(videoSize.width, 1)
        let scale = width / clampedWidth
        let scaledHeight = videoSize.height * scale
        playerLayer.videoGravity = .resizeAspect
        playerLayer.bounds = CGRect(x: 0, y: 0, width: width, height: scaledHeight)
        playerLayer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        playerLayer.position = CGPoint(x: width / 2, y: cachedBand.height)
        dlog(
            "updateLayerGeometry width=\(width) scale=\(scale) scaledHeight=\(scaledHeight) anchor=\(playerLayer.anchorPoint)"
        )
    }

    private func resolvedNaturalSize(for player: AVPlayer) -> CGSize {
        guard let item = player.currentItem else {
            dlog("resolvedNaturalSize fallback because currentItem is nil", level: .warn)
            return naturalVideoSize
        }
        let presentation = item.presentationSize
        if presentation != .zero {
            return presentation
        }
        if let track = item.asset.tracks(withMediaType: .video).first {
            var size = track.naturalSize
            let transform = track.preferredTransform
            size = CGSize(width: abs(size.applying(transform).width), height: abs(size.applying(transform).height))
            return size
        }
        dlog("resolvedNaturalSize fallback to previous size", level: .warn)
        return naturalVideoSize
    }
}

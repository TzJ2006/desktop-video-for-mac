import AppKit
import AVFoundation

enum ThumbnailGenerator {
    static func generate(for url: URL, isVideo: Bool, size: NSSize = NSSize(width: 128, height: 96)) async -> NSImage? {
        if isVideo {
            return await generateVideoThumbnail(url: url, size: size)
        } else {
            return generateImageThumbnail(url: url, size: size)
        }
    }

    private static func generateVideoThumbnail(url: URL, size: NSSize) async -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        do {
            let cgImage: CGImage
            if #available(macOS 13, *) {
                let result = try await generator.image(at: time)
                cgImage = result.image
            } else {
                var actualTime = CMTime.zero
                cgImage = try generator.copyCGImage(at: time, actualTime: &actualTime)
            }
            // Create an NSImage from the CGImage and set its size to the requested thumbnail size
            let nsImage = NSImage(cgImage: cgImage, size: size)
            return nsImage
        } catch {
            return nil
        }
    }

    private static func generateImageThumbnail(url: URL, size: NSSize) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail
    }
}

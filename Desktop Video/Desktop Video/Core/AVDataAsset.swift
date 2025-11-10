//
//  AVDataAsset.swift
//  Desktop Video
//
//  Created by Desktop Video Refactoring
//

import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Custom AVDataAsset class for creating video assets from in-memory data.
/// Writes in-memory video data to a temporary file with correct extension for playback.
class AVDataAsset: AVURLAsset, @unchecked Sendable {
    private let tempURL: URL

    init(data: Data, contentType: UTType) {
        let ext = contentType.preferredFilenameExtension ?? "mov"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try? data.write(to: tempURL)
        dlog("create AVDataAsset temp file \(tempURL.lastPathComponent)")
        self.tempURL = tempURL
        super.init(url: tempURL, options: nil)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempURL)
    }
}

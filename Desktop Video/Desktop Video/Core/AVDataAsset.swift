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

    init(data: Data, contentType: UTType) throws {
        let ext = contentType.preferredFilenameExtension ?? "mov"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        // 写盘失败不再静默吞掉：记录并向上抛出，避免后续以缺失/空文件初始化导致黑屏。
        do {
            try data.write(to: tempURL)
        } catch {
            errorLog("AVDataAsset failed to write temp file \(tempURL.lastPathComponent): \(error.localizedDescription)")
            throw error
        }
        dlog("create AVDataAsset temp file \(tempURL.lastPathComponent)")
        self.tempURL = tempURL
        super.init(url: tempURL, options: nil)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempURL)
    }
}

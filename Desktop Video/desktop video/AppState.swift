//
//  AppState.swift
//  Desktop Video
//
//  Created by 汤子嘉 on 7/1/25.
//

import Foundation
import Combine

// MARK: - Global Application State
class AppState: ObservableObject {
    static let shared = AppState()

    // Last selected media information
    @Published var lastMediaURL: URL?
    @Published var lastVolume: Float = 1.0
    @Published var lastStretchToFill: Bool = true
    @Published var currentMediaURL: String?

    // MARK: Playback Mode
    enum PlaybackMode: Int, CaseIterable, Identifiable {
        case alwaysPlay = 0      // 总是播放
        case automatic  = 1      // 自动（空闲暂停）
        case powerSave  = 2      // 省电（全部遮挡暂停）
        case powerSavePlus = 3   // 省电+（任意遮挡暂停）

        var id: Int { rawValue }

        var description: String {
            switch self {
            case .alwaysPlay:    return L("PlaybackAlways")
            case .automatic:     return L("PlaybackAuto")
            case .powerSave:     return L("PlaybackPowerSave")
            case .powerSavePlus: return L("PlaybackPowerSavePlus")
            }
        }
    }

    /// 用户选定的播放模式（默认 automatic）；写入 UserDefaults 以便持久化
    @Published var playbackMode: PlaybackMode {
        didSet {
            UserDefaults.standard.set(playbackMode.rawValue, forKey: "playbackMode")
        }
    }

    private init() {
        let raw = UserDefaults.standard.integer(forKey: "playbackMode")
        self.playbackMode = PlaybackMode(rawValue: raw) ?? .automatic
    }
}

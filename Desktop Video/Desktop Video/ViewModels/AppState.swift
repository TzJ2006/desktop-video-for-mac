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
    // periphery:ignore - reserved for future
    @Published var lastMediaURL: URL?
    // periphery:ignore - reserved for future
    @Published var lastVolume: Float = 1.0
    // periphery:ignore - reserved for future
    @Published var lastStretchToFill: Bool = true
    @Published var currentMediaURL: String?

    /// Global mute switch shared across all players and UI bindings
    @Published var isGlobalMuted: Bool {
        didSet {
            guard oldValue != isGlobalMuted else { return }
            dlog("AppState.isGlobalMuted updated to \(isGlobalMuted)")
            UserDefaults.standard.set(isGlobalMuted, forKey: globalMuteKey)
            let enabled = isGlobalMuted
            Task { @MainActor in
                if enabled {
                    SharedWallpaperWindowManager.shared.muteAllScreens()
                } else {
                    SharedWallpaperWindowManager.shared.restoreAllScreens()
                }
                NotificationCenter.default.post(
                    name: Notification.Name("WallpaperContentDidChange"),
                    object: nil
                )
            }
        }
    }

    // MARK: Playback Mode
    enum PlaybackMode: Int, CaseIterable, Identifiable {
        case alwaysPlay = 0      // 总是播放
        case automatic  = 1      // 自动（空闲暂停）
        case powerSave  = 2      // 省电（全部遮挡暂停）
        case powerSavePlus = 3   // 省电+（任意遮挡暂停）
        case stationary = 4 // 暂停播放

        var id: Int { rawValue }

        var description: String {
            switch self {
            case .alwaysPlay:    return L("PlaybackAlways")
            case .automatic:     return L("PlaybackAuto")
            case .powerSave:     return L("PlaybackPowerSave")
            case .powerSavePlus: return L("PlaybackPowerSavePlus")
            case .stationary: return L("PlaybackStatic")
            }
        }

        /// Detailed description for UI display
        var detail: String {
            switch self {
            case .alwaysPlay:    return L("PlaybackAlwaysDesc")
            case .automatic:     return L("PlaybackAutoDesc")
            case .powerSave:     return L("PlaybackPowerSaveDesc")
            case .powerSavePlus: return L("PlaybackPowerSavePlusDesc")
            case .stationary:    return L("PlaybackStaticDesc")
            }
        }
    }

    /// 用户选定的播放模式（默认 automatic）；写入 UserDefaults 以便持久化
    @Published var playbackMode: PlaybackMode {
        didSet {
            UserDefaults.standard.set(playbackMode.rawValue, forKey: "playbackMode")
        }
    }

    /// 空闲暂停灵敏度 (0~100)，写入 UserDefaults 以便持久化
    @Published var idlePauseSensitivity: Double {
        didSet {
            UserDefaults.standard.set(idlePauseSensitivity, forKey: idlePauseSensitivityKey)
        }
    }

    private let idlePauseSensitivityKey = "idlePauseSensitivity"
    private let globalMuteKey = "globalMute"
    private var userDefaultsCancellable: AnyCancellable?

    private init() {
        let raw = UserDefaults.standard.integer(forKey: "playbackMode")
        self.playbackMode = PlaybackMode(rawValue: raw) ?? .automatic
        self.idlePauseSensitivity = UserDefaults.standard.object(forKey: idlePauseSensitivityKey) as? Double ?? 40.0
        self.isGlobalMuted = UserDefaults.standard.object(forKey: globalMuteKey) as? Bool ?? false
        bindUserDefaults()
    }

    private func bindUserDefaults() {
        userDefaultsCancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { [weak self] _ -> Bool in
                guard let self else { return false }
                return UserDefaults.standard.object(forKey: self.globalMuteKey) as? Bool ?? false
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                if self.isGlobalMuted != newValue {
                    dlog("AppState observed external global mute change = \(newValue)")
                    self.isGlobalMuted = newValue
                }
            }
    }
}

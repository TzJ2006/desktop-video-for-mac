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
            guard oldValue != playbackMode else { return }
            UserDefaults.standard.set(playbackMode.rawValue, forKey: "playbackMode")
            Task { @MainActor in
                AppDelegate.shared?.updatePlaybackStateForAllScreens()
            }
        }
    }

    /// 空闲暂停灵敏度 (0~100)，写入 UserDefaults 以便持久化
    @Published var idlePauseSensitivity: Double {
        didSet {
            UserDefaults.standard.set(idlePauseSensitivity, forKey: idlePauseSensitivityKey)
        }
    }

    // MARK: - 自动连播（幻灯片）

    /// 是否开启自动连播
    @Published var slideshowEnabled: Bool {
        didSet {
            guard oldValue != slideshowEnabled else { return }
            UserDefaults.standard.set(slideshowEnabled, forKey: slideshowEnabledKey)
            Task { @MainActor in SlideshowController.shared.apply() }
        }
    }

    /// 连播顺序：true = 随机，false = 顺序
    @Published var slideshowRandom: Bool {
        didSet {
            guard oldValue != slideshowRandom else { return }
            UserDefaults.standard.set(slideshowRandom, forKey: slideshowRandomKey)
            Task { @MainActor in SlideshowController.shared.apply() }
        }
    }

    /// 播放到列表末尾后是否循环
    @Published var slideshowLoop: Bool {
        didSet {
            guard oldValue != slideshowLoop else { return }
            UserDefaults.standard.set(slideshowLoop, forKey: slideshowLoopKey)
        }
    }

    /// 图片停留时长（秒），到点切换下一项
    @Published var slideshowImageInterval: Double {
        didSet {
            guard oldValue != slideshowImageInterval else { return }
            UserDefaults.standard.set(slideshowImageInterval, forKey: slideshowImageIntervalKey)
        }
    }

    // MARK: - 壁纸库排序

    enum LibrarySortOrder: Int, CaseIterable, Identifiable {
        case nameAsc = 0
        case nameDesc = 1
        case recentAdd = 2
        case recentUse = 3

        var id: Int { rawValue }

        var description: String {
            switch self {
            case .nameAsc:    return L("LibrarySortNameAsc")
            case .nameDesc:   return L("LibrarySortNameDesc")
            case .recentAdd:  return L("LibrarySortRecentAdd")
            case .recentUse:  return L("LibrarySortRecentUse")
            }
        }
    }

    /// 壁纸画廊排序方式
    @Published var librarySortOrder: LibrarySortOrder {
        didSet {
            guard oldValue != librarySortOrder else { return }
            UserDefaults.standard.set(librarySortOrder.rawValue, forKey: librarySortOrderKey)
        }
    }

    private let idlePauseSensitivityKey = "idlePauseSensitivity"
    private let globalMuteKey = "globalMute"
    private let slideshowEnabledKey = "slideshowEnabled"
    private let slideshowRandomKey = "slideshowRandom"
    private let slideshowLoopKey = "slideshowLoop"
    private let slideshowImageIntervalKey = "slideshowImageInterval"
    private let librarySortOrderKey = "librarySortOrder"
    private var userDefaultsCancellable: AnyCancellable?

    private init() {
        let raw = UserDefaults.standard.integer(forKey: "playbackMode")
        self.playbackMode = PlaybackMode(rawValue: raw) ?? .automatic
        self.idlePauseSensitivity = UserDefaults.standard.object(forKey: idlePauseSensitivityKey) as? Double ?? 50.0
        self.isGlobalMuted = UserDefaults.standard.object(forKey: globalMuteKey) as? Bool ?? false
        self.slideshowEnabled = UserDefaults.standard.object(forKey: slideshowEnabledKey) as? Bool ?? false
        self.slideshowRandom = UserDefaults.standard.object(forKey: slideshowRandomKey) as? Bool ?? false
        self.slideshowLoop = UserDefaults.standard.object(forKey: slideshowLoopKey) as? Bool ?? true
        self.slideshowImageInterval = UserDefaults.standard.object(forKey: slideshowImageIntervalKey) as? Double ?? 60.0
        let sortRaw = UserDefaults.standard.integer(forKey: librarySortOrderKey)
        self.librarySortOrder = LibrarySortOrder(rawValue: sortRaw) ?? .recentAdd
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

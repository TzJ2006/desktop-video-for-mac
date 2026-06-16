import SwiftUI
import AppKit
import Combine
import WebKit

/// 单块屏幕的壁纸「预览 + 控件检查器」块（Apple「墙纸」面板风格）。
/// 左侧为当前壁纸大预览，右侧为名称、填充模式、播放控制、音量与网页浏览开关。
/// 添加壁纸的入口已移至下方的 WallpaperGallery。
struct SingleScreenView: View {
    let screen: NSScreen
    var isMultiScreen: Bool = false
    @Binding var menuBarOnly: Bool
    @ObservedObject private var appState = AppState.shared
    @Environment(\.theme) private var theme

    @State private var volume: Double = 100
    @State private var stretchToFill: Bool = true
    @State private var isLocallyMuted: Bool = false
    @State private var lastVolumeBeforeMute: Double = 100
    @State private var currentFileName: String = ""
    /// 当前是否处于播放状态：驱动单一播放/暂停切换按钮的图标与行为。
    @State private var isPlaying: Bool = true
    /// 预览刷新令牌：壁纸内容变化时自增，驱动 WallpaperPreview 重载缩略图。
    @State private var refreshToken: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            WallpaperPreview(screen: screen, refreshToken: refreshToken)

            VStack(alignment: .leading, spacing: 16) {
                // Grouped Settings Box
                VStack(spacing: 0) {
                    // Row 1: Filename and Display Mode
                    HStack {
                        Text(currentFileName.isEmpty ? L("No wallpaper") : currentFileName)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        if hasContent && !isWebContent {
                            Picker("", selection: Binding(
                                get: { stretchToFill },
                                set: { stretchToFill = $0; updateStretch($0) }
                            )) {
                                Text(LocalizedStringKey(L("Fill Screen"))).tag(true)
                                Text(LocalizedStringKey(L("Fit to Screen"))).tag(false)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 14)

                    // Row 2: Show only in menu bar
                    HStack {
                        Text(LocalizedStringKey(L("Show only in menu bar")))
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { menuBarOnly },
                            set: {
                                menuBarOnly = $0
                                AppDelegate.shared.setDockIconVisible(!$0)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    // Playback & Volume
                    if hasContent {
                        Divider().padding(.leading, 14)
                        
                        HStack(spacing: 12) {
                            // 单一播放/暂停切换：播放中显示「暂停」、暂停中显示「播放」
                            Button(action: togglePlayPause) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(.borderless)
                            .help(isPlaying ? L("Pause") : L("Play"))
                            Button(action: clear) { Image(systemName: "trash") }.buttonStyle(.borderless)
                            if isMultiScreen {
                                Button(action: syncAll) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }.buttonStyle(.borderless)
                                .help(L("Sync same videos"))
                            }
                            
                            Spacer()
                            
                            Image(systemName: isMuteEffective ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Slider(value: $volume, in: 0...100)
                                .frame(width: 80)
                                .disabled(isMuteEffective)
                                .onChange(of: volume) { newValue in
                                    let clamped = min(max(newValue, 0), 100)
                                    if clamped != newValue { volume = clamped }
                                    guard !isMuteEffective else { return }
                                    let target = Float(clamped / 100.0)
                                    let sid = screen.dv_displayUUID
                                    let current = SharedWallpaperWindowManager.shared.players[sid]?.volume
                                        ?? SharedWallpaperWindowManager.shared.screenContent[sid]?.volume
                                    if let current, abs(current - target) < 0.001 { return }
                                    SharedWallpaperWindowManager.shared.setVolume(target, for: screen)
                                }
                            Toggle("", isOn: Binding(
                                get: { isMuteEffective },
                                set: { handleMuteToggle($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    // Web Mode
                    if isWebContent {
                        Divider().padding(.leading, 14)
                        HStack {
                            Text(LocalizedStringKey(L("Web Mode")))
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: toggleBrowseMode) {
                                Label(isBrowseMode ? L("ExitBrowse") : L("Browse"),
                                      systemImage: isBrowseMode ? "xmark.circle" : "hand.point.up.left")
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
                .background(theme.controlBackground)
                .cornerRadius(theme.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.cardBorder, lineWidth: 1)
                )

                if !hasContent {
                    Text(LocalizedStringKey(L("Pick a wallpaper below")))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: syncInitialState)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WallpaperContentDidChange"))) { _ in
            refreshStateFromManager()
        }
        .onChange(of: screen.dv_displayUUID) { _ in
            dlog("screen changed; sync controls for \(screen.dv_localizedName)")
            syncInitialState()
        }
        .onChange(of: appState.isGlobalMuted) { enabled in
            dlog("observed global mute change = \(enabled) for \(screen.dv_localizedName)")
            if enabled {
                lastVolumeBeforeMute = max(volume, 0)
            } else {
                refreshStateFromManager()
            }
        }
    }

    // 清除当前屏幕的壁纸
    private func clear() {
        dlog("clear wallpaper for \(screen.dv_localizedName)")
        SharedWallpaperWindowManager.shared.clear(for: screen)
    }

    // 切换当前屏幕壁纸的播放 / 暂停（单一按钮）
    private func togglePlayPause() {
        if isPlaying { pause() } else { play() }
        isPlaying.toggle()
    }

    // 播放当前屏幕的壁纸
    private func play() {
        let sid = screen.dv_displayUUID
        dlog("play wallpaper for \(screen.dv_localizedName)")
        if let webView = SharedWallpaperWindowManager.shared.webViews[sid] {
            webView.dv_evaluateJS(WKWebView.jsPlayAll)
        } else {
            SharedWallpaperWindowManager.shared.players[sid]?.play()
        }
    }

    // 暂停当前屏幕的壁纸
    private func pause() {
        let sid = screen.dv_displayUUID
        dlog("pause wallpaper for \(screen.dv_localizedName)")
        if let webView = SharedWallpaperWindowManager.shared.webViews[sid] {
            webView.dv_evaluateJS(WKWebView.jsPauseAll)
        } else {
            SharedWallpaperWindowManager.shared.players[sid]?.pause()
        }
    }

    // 将当前屏幕的视频同步到所有屏幕
    private func syncAll() {
        dlog("sync same-name videos across screens")
        SharedWallpaperWindowManager.shared.syncSameNamedVideos()
    }

    private func updateStretch(_ stretch: Bool) {
        let sid = screen.dv_displayUUID
        if let entry = SharedWallpaperWindowManager.shared.screenContent[sid] {
            switch entry.type {
            case .image:
                SharedWallpaperWindowManager.shared.showImage(for: screen, url: entry.url, stretch: stretch)
            case .video:
                SharedWallpaperWindowManager.shared.showVideo(
                    for: screen,
                    url: entry.url,
                    stretch: stretch,
                    volume: isMuteEffective ? 0 : Float(volume / 100)
                )
            case .web:
                break
            }
        }
        dlog("update stretch \(stretch) for \(screen.dv_localizedName)")
    }

    private func syncInitialState() {
        refreshStateFromManager()
        dlog("sync controls for \(screen.dv_localizedName)")
    }

    private func refreshStateFromManager() {
        let sid = screen.dv_displayUUID
        if let player = SharedWallpaperWindowManager.shared.players[sid] {
            let newVolume = Double(player.volume * 100)
            volume = newVolume
            if newVolume > 0 {
                lastVolumeBeforeMute = newVolume
            }
            if !appState.isGlobalMuted {
                isLocallyMuted = player.volume == 0
            }
        } else if let entry = SharedWallpaperWindowManager.shared.screenContent[sid], entry.type == .web {
            let webVol = Double((entry.volume ?? 1.0) * 100)
            volume = webVol
            if webVol > 0 {
                lastVolumeBeforeMute = webVol
            }
            if !appState.isGlobalMuted {
                isLocallyMuted = (entry.volume ?? 1.0) == 0
            }
        }
        if let entry = SharedWallpaperWindowManager.shared.screenContent[sid] {
            stretchToFill = entry.stretch
            if entry.type == .web {
                currentFileName = entry.url.host ?? entry.url.absoluteString
            } else {
                currentFileName = entry.url.lastPathComponent
            }
        } else {
            currentFileName = ""
        }
        // 同步播放/暂停按钮状态：视频按实际播放状态，网页/图片视为播放中
        if let player = SharedWallpaperWindowManager.shared.players[sid] {
            isPlaying = player.timeControlStatus != .paused
        } else {
            isPlaying = true
        }
        refreshToken &+= 1
        dlog("refresh state for \(screen.dv_localizedName) file=\(currentFileName) volume=\(Int(volume)) mute=\(isMuteEffective)")
    }

    private func handleMuteToggle(_ newValue: Bool) {
        if appState.isGlobalMuted {
            if !newValue {
                dlog("toggle off per-screen mute while global mute active on \(screen.dv_localizedName)")
                desktop_videoApp.applyGlobalMute(false)
                isLocallyMuted = false
            }
            return
        }

        if newValue {
            lastVolumeBeforeMute = volume
            isLocallyMuted = true
            SharedWallpaperWindowManager.shared.setVolume(0, for: screen)
            dlog("muted volume for \(screen.dv_localizedName)")
        } else {
            let clamped = min(max(lastVolumeBeforeMute, 0), 100)
            volume = clamped
            isLocallyMuted = false
            SharedWallpaperWindowManager.shared.setVolume(Float(clamped / 100.0), for: screen)
            dlog("unmuted; restore volume \(clamped) for \(screen.dv_localizedName)")
        }
    }

    private var isMuteEffective: Bool {
        appState.isGlobalMuted || isLocallyMuted
    }

    private var hasContent: Bool {
        SharedWallpaperWindowManager.shared.screenContent[screen.dv_displayUUID] != nil
    }

    private var isWebContent: Bool {
        let sid = screen.dv_displayUUID
        return SharedWallpaperWindowManager.shared.screenContent[sid]?.type == .web
    }

    private var isBrowseMode: Bool {
        let sid = screen.dv_displayUUID
        return SharedWallpaperWindowManager.shared.browseMode[sid] == true
    }

    private func toggleBrowseMode() {
        let mgr = SharedWallpaperWindowManager.shared
        if isBrowseMode {
            mgr.exitBrowseMode(for: screen)
        } else {
            mgr.enterBrowseMode(for: screen)
        }
    }
}

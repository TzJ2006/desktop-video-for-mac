import AppKit
import AVFoundation

/// 壁纸自动连播（幻灯片）控制器。
/// 每块屏幕**各自独立**地遍历播放列表：视频播完自动切下一个，图片按设定间隔切换；
/// 顺序或随机由设置决定，到列表末尾时按「循环」开关决定重头开始或停止。
@MainActor
final class SlideshowController {
    static let shared = SlideshowController()

    /// 单块屏幕的连播状态
    private final class ScreenState {
        var order: [Int] = []                 // 播放顺序（顺序模式为 0..<n；随机模式为洗牌后的索引）
        var position: Int = 0                 // 当前在 order 中的位置
        var imageTimer: Timer?
        var endObserver: NSObjectProtocol?
    }

    private var states: [String: ScreenState] = [:]
    private var media: [(url: URL, isVideo: Bool)] = []

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private var isEnabled: Bool { AppState.shared.slideshowEnabled }

    // MARK: - 外部入口

    /// 依据当前开关状态启动或停止连播。开关/顺序设置变更时调用。
    func apply() {
        if isEnabled { restart() } else { stopAll() }
    }

    /// 播放列表变更：若正在连播则用新列表重启。
    func playlistDidChange() {
        if isEnabled { restart() }
    }

    @objc private func handleScreenParamsChanged() {
        guard isEnabled else { return }
        // 给系统一点时间重建窗口，再为新接入的屏幕补启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor [weak self] in self?.syncScreens() }
        }
    }

    // MARK: - 启停

    private func restart() {
        stopAll()
        media = PlaylistStore.shared.resolvedMedia()
        guard !media.isEmpty else {
            dlog("slideshow: playlist empty, nothing to play")
            return
        }
        for screen in NSScreen.screens { startScreen(screen) }
    }

    private func syncScreens() {
        guard !media.isEmpty else { return }
        for screen in NSScreen.screens where states[screen.dv_displayUUID] == nil {
            startScreen(screen)
        }
    }

    func stopAll() {
        for sid in states.keys { clearTimers(for: sid) }
        states.removeAll()
    }

    private func startScreen(_ screen: NSScreen) {
        guard !media.isEmpty else { return }
        let sid = screen.dv_displayUUID
        let state = ScreenState()
        state.order = makeOrder()
        state.position = 0
        states[sid] = state
        showCurrent(on: screen)
    }

    private func makeOrder() -> [Int] {
        var indices = Array(0..<media.count)
        if AppState.shared.slideshowRandom { indices.shuffle() }
        return indices
    }

    // MARK: - 切换

    /// 显示 order[position] 指向的媒体；不可访问的项自动跳过（最多遍历一轮）。
    private func showCurrent(on screen: NSScreen) {
        let sid = screen.dv_displayUUID
        guard let state = states[sid], !state.order.isEmpty else { return }

        var attempts = 0
        while attempts < state.order.count {
            let entry = media[state.order[state.position]]
            if MediaAccess.isAccessible(entry.url) {
                clearTimers(for: sid)
                applyMedia(entry, on: screen)
                return
            }
            dlog("slideshow: \(entry.url.lastPathComponent) not accessible, skipping")
            attempts += 1
            guard advancePosition(state) else { return }   // 无循环且到末尾则结束
        }
        dlog("slideshow: no accessible media on \(screen.dv_localizedName)")
        clearTimers(for: sid)
    }

    /// 推进 position；到末尾时按循环开关决定重头或结束。返回 false 表示连播在该屏结束。
    private func advancePosition(_ state: ScreenState) -> Bool {
        state.position += 1
        if state.position >= state.order.count {
            guard AppState.shared.slideshowLoop else { return false }
            state.position = 0
            if AppState.shared.slideshowRandom { state.order = makeOrder() }
        }
        return true
    }

    private func applyMedia(_ entry: (url: URL, isVideo: Bool), on screen: NSScreen) {
        let manager = SharedWallpaperWindowManager.shared
        if entry.isVideo {
            let volume: Float = AppState.shared.isGlobalMuted ? 0 : 1.0
            // loop:false 让视频只播放一遍，播完触发 AVPlayerItemDidPlayToEndTime 后切换；
            // record:false 避免连播把整张列表灌进历史记录。
            manager.showVideo(
                for: screen, url: entry.url, stretch: true, volume: volume,
                allowReuse: false, loop: false, record: false
            ) { [weak self] in
                Task { @MainActor [weak self] in self?.observeVideoEnd(on: screen) }
            }
        } else {
            manager.showImage(for: screen, url: entry.url, stretch: true, record: false)
            scheduleImageTimer(on: screen)
        }
    }

    /// 由计时器（图片）或播放结束通知（视频）触发，按屏幕 UUID 切到下一项。
    /// 用 sid（String，Sendable）跨闭包传递并经单例重解析，避免在 @Sendable 闭包中捕获 self / NSScreen。
    private func advance(sid: String) {
        guard let screen = NSScreen.screen(forUUID: sid) else { return }
        advance(on: screen)
    }

    private func advance(on screen: NSScreen) {
        let sid = screen.dv_displayUUID
        guard let state = states[sid] else { return }
        clearTimers(for: sid)
        guard advancePosition(state) else {
            dlog("slideshow finished on \(screen.dv_localizedName)")
            return
        }
        showCurrent(on: screen)
    }

    // MARK: - 触发器

    private func scheduleImageTimer(on screen: NSScreen) {
        let sid = screen.dv_displayUUID
        guard let state = states[sid] else { return }
        let interval = max(2.0, AppState.shared.slideshowImageInterval)
        state.imageTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in SlideshowController.shared.advance(sid: sid) }
        }
    }

    private func observeVideoEnd(on screen: NSScreen) {
        let sid = screen.dv_displayUUID
        guard let state = states[sid],
              let item = SharedWallpaperWindowManager.shared.players[sid]?.currentItem else { return }
        state.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in SlideshowController.shared.advance(sid: sid) }
        }
    }

    private func clearTimers(for sid: String) {
        guard let state = states[sid] else { return }
        state.imageTimer?.invalidate()
        state.imageTimer = nil
        if let observer = state.endObserver {
            NotificationCenter.default.removeObserver(observer)
            state.endObserver = nil
        }
    }
}

//
//  WallpaperWindow 2.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/25/25.
//

import AVFoundation
import AVKit
import Cocoa
import CoreGraphics  // for CGWindowListCopyWindowInfo
import Foundation
import UniformTypeIdentifiers
import Combine

@MainActor
class SharedWallpaperWindowManager {
  static let shared = SharedWallpaperWindowManager()

  /// 屏幕暂停状态集合
  private var pausedScreens: Set<String> = []

  private var debounceWorkItem: DispatchWorkItem?
  private var blackScreensWorkItem: DispatchWorkItem?
  private var windowScreenChangeWorkItem: DispatchWorkItem?

  private var playbackMode: AppState.PlaybackMode {
    AppState.shared.playbackMode
  }

  init() {
    let wsnc = NSWorkspace.shared.notificationCenter
    wsnc.addObserver(
      self,
      selector: #selector(handleWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
    wsnc.addObserver(
      self,
      selector: #selector(handleScreensDidWake),
      name: NSWorkspace.screensDidWakeNotification,
      object: nil
    )
    wsnc.addObserver(
      self,
      selector: #selector(handleScreensDidSleep),
      name: NSWorkspace.screensDidSleepNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )

  }

  private func id(for screen: NSScreen) -> String {
    screen.dv_displayUUID
  }

  /// Ensure the wallpaper, overlay and screensaver overlay windows for the
  /// given screen are still located on that physical display.
  /// If the system has moved any of them, dispose of them so they can be
  /// recreated on the correct screen.
  private func ensureWindowOnCorrectScreen(for screen: NSScreen) {
    let sid = id(for: screen)

    // Wallpaper window
    if let win = windowControllers[sid]?.window, win.screen !== screen {
      clear(for: screen, purgeBookmark: false, keepContent: true)
    }

    // Overlay window
    if let overlay = overlayWindows[sid], overlay.screen !== screen {
      overlay.orderOut(nil)
      overlayWindows.removeValue(forKey: sid)
      dlog("overlay level = \(overlay.level.rawValue)")
    }

    if let mirror = menuBarMirrors[sid], mirror.mirroredScreen !== screen {
      dlog("menu bar mirror moved off \(screen.dv_localizedName); tearing down")
      tearDownMenuBarMirror(for: screen)
    }

    // Screensaver‑overlay window
    if let saverOverlay = screensaverOverlayWindows[sid], saverOverlay.screen !== screen {
      saverOverlay.orderOut(nil)
      screensaverOverlayWindows.removeValue(forKey: sid)
    }
  }

  @objc private func handleWake() {
    dlog("handling wake")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      for (_, player) in self.players {
        // 检查是否为暂停状态的屏幕
        let sid = self.id(
          for: NSScreen.screens.first(where: { self.players[$0.dv_displayUUID] == player })
            ?? NSScreen.main!)
        if self.pausedScreens.contains(sid) {
          continue
        }
        if let currentItem = player.currentItem {
          // 如果播放已经暂停但应该播放
          if player.timeControlStatus != .playing {
            player.seek(
              to: currentItem.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero
            ) { _ in
              player.play()
            }
          }
        }
      }
    }
  }

  @objc private func handleScreensDidWake() {
    dlog("screens did wake")
    handleWake()
    handleScreenChange()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.checkBlackScreens()
      self?.reassignAllWindows()
    }
  }

  @objc private func handleScreensDidSleep() {
    dlog("screens did sleep")
    for (_, player) in players {
      player.pause()
    }
    cleanupDisconnectedScreens()
  }

  /// Sync playback time for videos that share the same file name across screens.
  /// 同步所有屏幕上相同文件名视频的播放进度。
  func syncSameNamedVideos() {
    dlog("syncSameNamedVideos invoked")
    // Group screen IDs by video file name
    var groups: [String: [String]] = [:]
    for (sid, entry) in screenContent where entry.type == .video {
      let name = entry.url.lastPathComponent
      groups[name, default: []].append(sid)
    }
    // Align playback for groups with more than one screen
    for (name, sids) in groups where sids.count > 1 {
      guard let firstID = sids.first,
            let referencePlayer = players[firstID],
            let time = referencePlayer.currentItem?.currentTime() else { continue }
      let shouldPlay = referencePlayer.rate != 0
      dlog("syncing \(name) across \(sids.count) screens")
      for sid in sids.dropFirst() {
        if let player = players[sid] {
          player.pause()
          player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if shouldPlay { player.play() }
          }
        }
      }
    }
  }

  private var cancellables: Set<AnyCancellable> = []

  /// 全局静音前记录各屏幕的音量
  private var savedVolumes: [String: Float] = [:]
  private var currentViews: [String: NSView] = [:]
  private var loopers: [String: AVPlayerLooper] = [:]
  var windowControllers: [String: WallpaperWindowController] = [:]
  /// 用于检测遮挡状态的小窗口（每个屏幕四个）
  var overlayWindows: [String: NSWindow] = [:]
  /// 全屏覆盖窗口，用于屏保启动前的遮挡检测
  var screensaverOverlayWindows: [String: NSWindow] = [:]
  /// 菜单栏镜像控制器
  var menuBarMirrors: [String: ForeignMenuBarMirrorController] = [:]
  /// 菜单栏顶部裁剪视频视图
  var menuBarVideoViews: [String: TopCroppedVideoStripView] = [:]
  var players: [String: AVQueuePlayer] = [:]
  private let videoDataCache = NSCache<NSURL, NSData>()
  var screenContent: [String: (type: ContentType, url: URL, stretch: Bool, volume: Float?)] = [:]

  enum ContentType {
    case image
    case video
  }

  private func videoData(for url: URL) throws -> Data {
    if let cached = videoDataCache.object(forKey: url as NSURL) {
      dlog("reuse cached data for \(url.lastPathComponent)")
      return cached as Data
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    videoDataCache.setObject(data as NSData, forKey: url as NSURL)
    dlog("cache video data for \(url.lastPathComponent)")
    return data
  }

  @discardableResult
  func ensureWallpaperController(for screen: NSScreen) -> WallpaperWindowController {
    dlog("ensure window for \(screen.dv_localizedName)")
    ensureWindowOnCorrectScreen(for: screen)
    let sid = id(for: screen)
    if let existing = windowControllers[sid] {
      existing.start(on: screen)
      return existing
    }

    // Remove old overlay occlusion observer before creating new overlay
    if let oldOverlay = overlayWindows[sid] {
      NotificationCenter.default.removeObserver(
        AppDelegate.shared as Any,
        name: NSWindow.didChangeOcclusionStateNotification,
        object: oldOverlay
      )
    }

    let screenFrame = screen.frame
    let win = WallpaperWindow(
      contentRect: screenFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    win.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
//    win.level = NSWindow.Level(Int(CGWindowLevelForKey(.cursorWindow)))
//    win.level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)))
      
    win.isOpaque = false
    win.backgroundColor = .clear
    win.ignoresMouseEvents = true
    win.collectionBehavior = [.canJoinAllSpaces, .stationary]
    win.contentView = NSView(frame: screenFrame)
    win.orderFrontRegardless()

    // 创建一个用于检测遮挡状态的透明窗口
    let rawSensitivity = AppState.shared.idlePauseSensitivity
    let portionSize = 1 - rawSensitivity / 200.0

    let overlaySize = CGSize(
      width: screenFrame.width * portionSize, height: screenFrame.height * portionSize)

    let position: CGPoint =
      CGPoint(
        x: screenFrame.midX - overlaySize.width / 2,
        y: screenFrame.midY - overlaySize.height / 2)

    let overlay = NSWindow(
      contentRect: CGRect(origin: position, size: overlaySize),
      styleMask: .borderless,
      backing: .buffered,
      defer: false)
    // overlay 必须高于 screensaverOverlay，但仍低于普通窗口
    overlay.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow))) + 2
    overlay.isOpaque = false
    overlay.backgroundColor = .clear  // keep fully transparent for occlusion checks
    overlay.ignoresMouseEvents = true
    overlay.alphaValue = 0.0001  // barely visible but participates in occlusion
    overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
    overlay.orderFrontRegardless()
    dlog("overlay level = \(overlay.level.rawValue)")

    // Ensure occlusion observer is not duplicated
    NotificationCenter.default.removeObserver(
      AppDelegate.shared as Any,
      name: NSWindow.didChangeOcclusionStateNotification,
      object: overlay
    )
    NotificationCenter.default.addObserver(
      AppDelegate.shared as Any,
      selector: #selector(AppDelegate.wallpaperWindowOcclusionDidChange(_:)),
      name: NSWindow.didChangeOcclusionStateNotification,
      object: overlay
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowScreenDidChange(_:)),
      name: NSWindow.didChangeScreenNotification,
      object: nil
    )

    // 创建用于屏保检测的全屏透明窗口
    let screensaverOverlay = NSWindow(
      contentRect: screenFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false)
    // screensaverOverlay 位于 overlay 之下、壁纸窗口之上
    screensaverOverlay.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow))) + 1
    screensaverOverlay.isOpaque = false
    screensaverOverlay.backgroundColor = .clear
    screensaverOverlay.ignoresMouseEvents = true
    screensaverOverlay.alphaValue = 0.0
    screensaverOverlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
    screensaverOverlay.orderFrontRegardless()

    let controller = WallpaperWindowController(window: win)
    controller.start(on: screen)
    self.windowControllers[sid] = controller
    self.overlayWindows[sid] = overlay
    self.screensaverOverlayWindows[sid] = screensaverOverlay

    // 创建 / 恢复窗口后立即根据遮挡状态调整播放
    updatePlayState(for: screen)
    return controller
  }

  private func tearDownWindow(for screen: NSScreen) {
    let sid = id(for: screen)
    if let controller = windowControllers.removeValue(forKey: sid) {
      controller.stop()
    }
  }

  func showImage(for screen: NSScreen, url: URL, stretch: Bool) {
    dlog("show image \(url.lastPathComponent) on \(screen.dv_localizedName) stretch=\(stretch)")
    ensureWindowOnCorrectScreen(for: screen)
    let sid = id(for: screen)
    let controller = ensureWallpaperController(for: screen)
    stopVideoIfNeeded(for: screen)

    guard let image = NSImage(contentsOf: url),
      let contentView = controller.window?.contentView
    else { return }

    let imageView = NSImageView(frame: contentView.bounds)
    imageView.image = image
    imageView.imageScaling = stretch ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
    imageView.autoresizingMask = [.width, .height]

    self.screenContent[sid] = (.image, url, stretch, nil)
    AppState.shared.currentMediaURL = url.absoluteString
    dlog("saveBookmark in showImage for \(screen.dv_localizedName) url=\(url.lastPathComponent)")
    saveBookmark(for: url, stretch: stretch, volume: nil, screen: screen)

    switchContent(to: imageView, for: screen)
    DispatchQueue.main.async { [weak self] in
      self?.updatePlayState(for: screen)
    }
    NotificationCenter.default.post(
      name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
    AppDelegate.shared?.startScreensaverTimer()
  }

  /// 为指定屏幕播放视频，使用内存映射以减少磁盘读写。
  func showVideo(
    for screen: NSScreen, url: URL, stretch: Bool, volume: Float, allowReuse: Bool = true,
    onReady: (() -> Void)? = nil
  ) {
    ensureWindowOnCorrectScreen(for: screen)
    let sid = id(for: screen)
    dlog(
      "show video \(url.lastPathComponent) on \(screen.dv_localizedName) stretch=\(stretch) volume=\(volume) UID=\(sid)"
    )

    // Fast path: reuse existing player on the same screen
    if allowReuse,
       let existingContent = screenContent[sid],
       existingContent.type == .video,
       existingContent.url == url,
       let existingPlayer = players[sid] {
      dlog("reuse existing video player on same screen \(sid)")
      existingPlayer.volume = desktop_videoApp.shared!.globalMute ? 0.0 : volume
      if let playerView = currentViews[sid] as? AVPlayerView {
        playerView.videoGravity = stretch ? .resize : .resizeAspect
      }
      if existingPlayer.timeControlStatus != .playing {
        existingPlayer.play()
      }
      screenContent[sid] = (.video, url, stretch, volume)
      NotificationCenter.default.post(
        name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
      onReady?()
      return
    }

    // Stop existing playback before loading new data to avoid memory spikes
    if let existing = screenContent[sid], existing.type == .video {
      stopVideoIfNeeded(for: screen)
      if existing.url != url {
        let stillUsed = screenContent.contains { $0.key != sid && $0.value.url == existing.url }
        if !stillUsed {
          videoDataCache.removeObject(forKey: existing.url as NSURL)
          dlog("purge cached data for \(existing.url.lastPathComponent)")
        }
      }
      if let pv = currentViews[sid] as? AVPlayerView {
        dlog("detach old player view for \(screen.dv_localizedName)")
        pv.player = nil
      }
    } else {
      stopVideoIfNeeded(for: screen)
    }

    do {
      let data = try videoData(for: url)
      guard let contentType = UTType(filenameExtension: url.pathExtension),
            contentType.conforms(to: .movie) else {
        errorLog("Unsupported video type")
        return
      }

      let controller = ensureWallpaperController(for: screen)
      guard let contentView = controller.window?.contentView else { return }

      let asset = AVDataAsset(data: data, contentType: contentType)
      let item = AVPlayerItem(asset: asset)
      let queuePlayer = AVQueuePlayer(playerItem: item)
      queuePlayer.automaticallyWaitsToMinimizeStalling = false
      let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

      queuePlayer.volume = desktop_videoApp.shared!.globalMute ? 0.0 : volume

      let playerView = AVPlayerView(frame: contentView.bounds)
      playerView.player = queuePlayer
      playerView.controlsStyle = .none
      playerView.videoGravity = stretch ? .resize : .resizeAspect
      playerView.autoresizingMask = [.width, .height]

      players[sid] = queuePlayer
      loopers[sid] = looper
      screenContent[sid] = (.video, url, stretch, volume)
      saveBookmark(for: url, stretch: stretch, volume: volume, screen: screen)
      AppState.shared.currentMediaURL = url.absoluteString
      AppDelegate.shared?.startScreensaverTimer()
      switchContent(to: playerView, for: screen)
      queuePlayer.play()
      DispatchQueue.main.async { [weak self] in
        self?.updatePlayState(for: screen)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        dlog("delayed play state check for \(screen.dv_localizedName)")
        self?.updatePlayState(for: screen)
      }
      pausedScreens.remove(sid)
      NotificationCenter.default.post(
        name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
      onReady?()
    } catch {
      errorLog("Failed to load video data: \(error)")
    }
  }

  /// 使用与单屏静音相同的逻辑静音所有屏幕，
  /// 会在静音前保存各屏幕最后一次非零音量。
  func muteAllScreens() {
    dlog("mute all screens")
    // 先记录音量再静音
    for sid in screenContent.keys {
      let currentVol = screenContent[sid]?.volume ?? 0
      if currentVol > 0 { savedVolumes[sid] = currentVol }
      if let screen = NSScreen.screen(forUUID: sid) {
        setVolume(0, for: screen)
      }
    }
  }

  /// 恢复所有屏幕在上次全局静音前的音量，
  /// 已经为 0 的屏幕保持静音。
  func restoreAllScreens() {
    dlog("restore all screens")
    for sid in screenContent.keys {
      let newVol = savedVolumes[sid] ?? (screenContent[sid]?.volume ?? 0)
      if let screen = NSScreen.screen(forUUID: sid) {
        setVolume(newVol, for: screen)
      }
    }
    savedVolumes.removeAll()

    // 通知界面刷新音量滑块
    NotificationCenter.default.post(
      name: Notification.Name("WallpaperContentDidChange"),
      object: nil
    )
  }

  // 更新设置后视频不再从内存播放，
  // 处理超大文件时会遇到此问题。
  func updateVideoSettings(for screen: NSScreen, stretch: Bool, volume: Float) {
    dlog("update video settings on \(screen.dv_localizedName) stretch=\(stretch) volume=\(volume)")
    let sid = id(for: screen)
    players[sid]?.volume = desktop_videoApp.shared!.globalMute ? 0.0 : volume
    if let playerView = currentViews[sid] as? AVPlayerView {
      playerView.videoGravity = stretch ? .resize : .resizeAspect
    }
    updateBookmark(stretch: stretch, volume: volume, screen: screen)
  }

  // periphery:ignore - reserved for future
  func updateImageStretch(for screen: NSScreen, stretch: Bool) {
    dlog("update image stretch on \(screen.dv_localizedName) stretch=\(stretch)")
    let sid = id(for: screen)
    if let imageView = currentViews[sid] as? NSImageView {
      imageView.imageScaling = stretch ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
    }
  }

  func clear(for screen: NSScreen, purgeBookmark: Bool = true, keepContent: Bool = false) {
    dlog(
      "clear content for \(screen.dv_localizedName) purge=\(purgeBookmark) keepContent=\(keepContent)"
    )
    let sid = id(for: screen)
    if purgeBookmark {
      BookmarkStore.purge(id: sid)
    }

    // 移除播放器引用
    stopVideoIfNeeded(for: screen)

    if let pv = currentViews[sid] as? AVPlayerView {
      dlog("detach player view for \(screen.dv_localizedName)")
      pv.player = nil
    }
    currentViews[sid]?.removeFromSuperview()
    currentViews.removeValue(forKey: sid)
    if let overlay = overlayWindows[sid] {
      NotificationCenter.default.removeObserver(
        AppDelegate.shared as Any,
        name: NSWindow.didChangeOcclusionStateNotification,
        object: overlay)
      overlay.orderOut(nil)
      overlayWindows.removeValue(forKey: sid)
    }
    if let overlay = screensaverOverlayWindows[sid] {
      overlay.orderOut(nil)
      screensaverOverlayWindows.removeValue(forKey: sid)
    }
    tearDownWindow(for: screen)
    if let entry = screenContent[sid], entry.type == .video {
      let stillUsed = screenContent.contains { $0.key != sid && $0.value.url == entry.url }
      if !stillUsed {
        videoDataCache.removeObject(forKey: entry.url as NSURL)
        dlog("purge cached data for \(entry.url.lastPathComponent)")
      }
    }
    if !keepContent {
      screenContent.removeValue(forKey: sid)
      if screenContent.isEmpty {
        AppState.shared.currentMediaURL = nil
      }
    }
    tearDownMenuBarMirror(for: screen)
    NotificationCenter.default.post(
      name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
    AppDelegate.shared?.startScreensaverTimer()

    // 清除暂停状态
    pausedScreens.remove(sid)

    // 状态栏视频已移除
  }

  // periphery:ignore - reserved for future
  func restoreContent(for screen: NSScreen) {
    dlog("restore content for \(screen.dv_localizedName)")
    let sid = id(for: screen)
    guard let entry = screenContent[sid] else { return }
    switch entry.type {
    case .image:
      showImage(for: screen, url: entry.url, stretch: entry.stretch)
    case .video:
      showVideo(for: screen, url: entry.url, stretch: entry.stretch, volume: entry.volume ?? 1.0)
    }
  }

  private func stopVideoIfNeeded(for screen: NSScreen) {
    dlog("stop video for \(screen.dv_localizedName)")
    let sid = id(for: screen)
    if let looper = loopers[sid] {
      looper.disableLooping()
      loopers.removeValue(forKey: sid)
    }
    if let player = players[sid] {
      player.pause()
      player.replaceCurrentItem(with: nil)
      players.removeValue(forKey: sid)
    }
  }

  private func switchContent(to newView: NSView, for screen: NSScreen) {
    dlog("switch content on \(screen.dv_localizedName)")
    let sid = id(for: screen)
    guard let contentView = windowControllers[sid]?.window?.contentView else { return }
    currentViews[sid]?.removeFromSuperview()
    contentView.addSubview(newView)
    currentViews[sid] = newView
    // 根据设置更新状态栏视频
    updateStatusBarVideo(for: screen)
  }

  /// 根据 overlay 遮挡状态立即决定播放或暂停该屏幕的视频
  /// - Important: 该方法**只**影响当前屏幕，不会重建 playerItem，
  ///   避免 “恢复 B 导致 A 被唤醒” 的副作用。
  private func updatePlayState(for screen: NSScreen) {
    let sid = id(for: screen)
    guard let player = players[sid] else { return }

    switch playbackMode {

    case .alwaysPlay:
      if player.timeControlStatus != .playing { player.play() }

    case .automatic:
      // Delegate to existing global logic
      AppDelegate.shared.updatePlaybackStateForAllScreens()

    case .powerSave:
      if allOverlaysCompletelyCovered() {
        if player.timeControlStatus != .paused { player.pause() }
      } else {
        if player.timeControlStatus != .playing { player.play() }
      }

    case .powerSavePlus:
      if anyOverlayCompletelyCovered() {
        if player.timeControlStatus != .paused { player.pause() }
      } else {
        if player.timeControlStatus != .playing { player.play() }
      }

    case .stationary:
      player.pause()

    }
  }

  /// 供外部在遮挡状态变更时调用，确保每屏独立刷新
  // periphery:ignore - reserved for future
  func refreshPlayState(for screen: NSScreen) {
    updatePlayState(for: screen)
  }

  /// 根据用户设置在菜单栏显示或移除动态着色
  @discardableResult
  func updateStatusBarVideo(for screen: NSScreen) -> ForeignMenuBarMirrorController? {
    let sid = id(for: screen)
    let enabled = Settings.shared.showInMenuBar
    dlog("updateStatusBarVideo (mirror) enabled=\(enabled) for \(screen.dv_localizedName)")
    guard enabled else {
      tearDownMenuBarMirror(for: screen)
      return nil
    }
    guard let player = players[sid] else {
      dlog("updateStatusBarVideo missing player for \(screen.dv_localizedName)", level: .warn)
      tearDownMenuBarMirror(for: screen)
      return nil
    }

    let controller: ForeignMenuBarMirrorController
    if let existing = menuBarMirrors[sid] {
      controller = existing
    } else {
      controller = makeMenuBarMirror(for: screen)
      menuBarMirrors[sid] = controller
    }

    controller.drawBackground = { [weak self] context, rect in
      self?.drawMenuBarBackground(in: context, rect: rect, screen: screen)
    }

    controller.onGeometryChange = { [weak self] newFrame in
      guard let self else { return }
      if let view = self.menuBarVideoViews[sid] {
        view.updateLayout(for: screen, band: newFrame)
      }
    }

    let videoView: TopCroppedVideoStripView
    if let existingView = menuBarVideoViews[sid] {
      videoView = existingView
    } else {
      videoView = TopCroppedVideoStripView(frame: .zero)
      menuBarVideoViews[sid] = videoView
    }
    controller.setHostedView(videoView)
    videoView.attach(player: player)
    if let frame = controller.currentOverlayFrame {
      videoView.updateLayout(for: screen, band: frame)
    } else {
      videoView.updateLayout(for: screen)
    }
    controller.start()
    controller.refresh()
    return controller
  }

  /// 更新所有屏幕的状态栏视频
  // periphery:ignore - reserved for future
  func updateStatusBarVideoForAllScreens() {
    dlog("update status bar mirror for all screens")
    for screen in NSScreen.screens {
      _ = updateStatusBarVideo(for: screen)
    }
  }

  private func makeMenuBarMirror(for screen: NSScreen) -> ForeignMenuBarMirrorController {
    dlog("makeMenuBarMirror for \(screen.dv_localizedName)")
    let controller = ForeignMenuBarMirrorController(screen: screen)
    controller.drawBackground = { [weak self] context, rect in
      self?.drawMenuBarBackground(in: context, rect: rect, screen: screen)
    }
    return controller
  }

  private func drawMenuBarBackground(in context: CGContext, rect: CGRect, screen: NSScreen) {
    dlog(
      "drawMenuBarBackground for \(screen.dv_localizedName) rect=\(NSStringFromRect(NSRectFromCGRect(rect)))"
    )
    context.setFillColor(NSColor.clear.cgColor)
    context.fill(rect)
  }

  func tearDownMenuBarMirror(for screen: NSScreen) {
    let sid = id(for: screen)
    if let strip = menuBarVideoViews.removeValue(forKey: sid) {
      dlog("tearDownMenuBarMirror remove strip for \(screen.dv_localizedName)")
      strip.removeFromSuperview()
    }
    if let controller = menuBarMirrors.removeValue(forKey: sid) {
      dlog("tearDownMenuBarMirror stop controller for \(screen.dv_localizedName)")
      controller.removeHostedView()
      controller.stop()
    }
  }

  func tearDownAllMenuBarMirrors() {
    dlog("tearDownAllMenuBarMirrors")
    for (sid, controller) in menuBarMirrors {
      dlog("tearDownAllMenuBarMirrors stop controller id=\(sid)")
      controller.removeHostedView()
      controller.stop()
    }
    menuBarMirrors.removeAll()
    for (sid, view) in menuBarVideoViews {
      dlog("tearDownAllMenuBarMirrors remove strip id=\(sid)")
      view.removeFromSuperview()
    }
    menuBarVideoViews.removeAll()
  }

  func tearDownMenuBarMirror(forID id: String) {
    if let screen = NSScreen.screen(forUUID: id) {
      tearDownMenuBarMirror(for: screen)
      return
    }
    if let controller = menuBarMirrors.removeValue(forKey: id) {
      dlog("tearDownMenuBarMirror stop controller for missing screen id=\(id)")
      controller.removeHostedView()
      controller.stop()
    }
    if let strip = menuBarVideoViews.removeValue(forKey: id) {
      dlog("tearDownMenuBarMirror remove strip for missing screen id=\(id)")
      strip.removeFromSuperview()
    }
  }

  func updateBookmark(stretch: Bool, volume: Float?, screen: NSScreen) {
    dlog(
      "update bookmark for \(screen.dv_localizedName) stretch=\(stretch) volume=\(String(describing: volume))"
    )
    let uuid = screen.dv_displayUUID
    BookmarkStore.set(stretch, prefix: "stretch", id: uuid)
    BookmarkStore.set(volume, prefix: "volume", id: uuid)
  }

  private func saveBookmark(for url: URL, stretch: Bool, volume: Float?, screen: NSScreen) {
    dlog(
      "save bookmark for \(screen.dv_localizedName) url=\(url.lastPathComponent) stretch=\(stretch) volume=\(String(describing: volume))"
    )
    let uuid = screen.dv_displayUUID
    do {
      guard url.startAccessingSecurityScopedResource() else {
        errorLog("Failed to access security scoped resource for saving bookmark: \(url)")
        return
      }
      let bookmarkData = try url.bookmarkData(
        options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
      BookmarkStore.set(bookmarkData, prefix: "bookmark", id: uuid)
      BookmarkStore.set(stretch, prefix: "stretch", id: uuid)
      BookmarkStore.set(volume, prefix: "volume", id: uuid)
      // 保存当前时间戳
      BookmarkStore.set(Date().timeIntervalSince1970, prefix: "savedAt", id: uuid)
      url.stopAccessingSecurityScopedResource()
    } catch {
      errorLog("Failed to save bookmark for \(url): \(error)")
    }
  }

  func restoreFromBookmark() {
    dlog("restore from bookmark")
    for screen in NSScreen.screens {
      dlog("Check screen: \(screen.dv_localizedName)")
      let uuid = screen.dv_displayUUID
      guard let bookmarkData: Data = BookmarkStore.get(prefix: "bookmark", id: uuid) else {
        continue
      }

      var isStale = false
      do {
        let url = try URL(
          resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil,
          bookmarkDataIsStale: &isStale)
        guard url.startAccessingSecurityScopedResource() else {
          url.stopAccessingSecurityScopedResource()
          errorLog("Failed to startAccessing for \(url.lastPathComponent)")
          continue
        }
        let ext = url.pathExtension.lowercased()
        let stretch: Bool = BookmarkStore.get(prefix: "stretch", id: uuid) ?? false
        let volume: Float = BookmarkStore.get(prefix: "volume", id: uuid) ?? 1.0

        if ["mp4", "mov", "m4v"].contains(ext) {
          dlog("restoring video \(url.lastPathComponent) on \(screen.dv_localizedName)")
          showVideo(for: screen, url: url, stretch: stretch, volume: volume)
        } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
          dlog("restoring image \(url.lastPathComponent) on \(screen.dv_localizedName)")
          showImage(for: screen, url: url, stretch: stretch)
        }
        url.stopAccessingSecurityScopedResource()
      } catch {
        errorLog("Failed to restore bookmark for screen \(uuid): \(error)")
      }

      if let savedAt: Double = BookmarkStore.get(prefix: "savedAt", id: uuid),
        Date().timeIntervalSince1970 - savedAt > 86400
      {
        // 超过 24 小时，删除记录
        dlog("Outdated bookmark for screen \(uuid), removing...")
        BookmarkStore.purge(id: uuid)
        continue
      }
    }
  }

  /// 仅恢复指定屏幕的书签内容
  func restoreFromBookmark(for screen: NSScreen) {
    dlog("restoreFromBookmark \(screen.dv_localizedName)")
    let uuid = screen.dv_displayUUID
    guard let bookmarkData: Data = BookmarkStore.get(prefix: "bookmark", id: uuid) else {
      return
    }
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil,
        bookmarkDataIsStale: &isStale)
      guard url.startAccessingSecurityScopedResource() else {
        url.stopAccessingSecurityScopedResource()
        errorLog("Failed to startAccessing for \(url.lastPathComponent)")
        return
      }
      let ext = url.pathExtension.lowercased()
      let stretch: Bool = BookmarkStore.get(prefix: "stretch", id: uuid) ?? false
      let volume: Float = BookmarkStore.get(prefix: "volume", id: uuid) ?? 1.0

      if ["mp4", "mov", "m4v"].contains(ext) {
        dlog("restoring video \(url.lastPathComponent) on \(screen.dv_localizedName)")
        showVideo(for: screen, url: url, stretch: stretch, volume: volume)
      } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
        dlog("restoring image \(url.lastPathComponent) on \(screen.dv_localizedName)")
        showImage(for: screen, url: url, stretch: stretch)
      }
      url.stopAccessingSecurityScopedResource()
    } catch {
      errorLog("Failed to restore bookmark for screen \(uuid): \(error)")
    }
  }

  func setVolume(_ volume: Float, for screen: NSScreen) {
    dlog("set volume for \(screen.dv_localizedName) volume=\(volume)")
    let sid = id(for: screen)
    if let entry = screenContent[sid], entry.type == .video {
      // 手动调整音量会取消全局静音
      if volume > 0 {
        desktop_videoApp.shared!.globalMute = false
      }

      // 应用到播放器并持久化
      updateVideoSettings(for: screen, stretch: entry.stretch, volume: volume)
      screenContent[sid] = (.video, entry.url, entry.stretch, volume)
    }

    // 通知所有界面立即刷新滑块和标签
    NotificationCenter.default.post(
      name: Notification.Name("WallpaperContentDidChange"),
      object: nil
    )
  }

  private func cleanupDisconnectedScreens() {
    dlog("cleanup disconnected screens")
    let activeIDs = Set(NSScreen.screens.map { $0.dv_displayUUID })
    for sid in Array(windowControllers.keys) {
      if !activeIDs.contains(sid) {
        if let savedAt: Double = BookmarkStore.get(prefix: "savedAt", id: sid),
          Date().timeIntervalSince1970 - savedAt > 86400
        {
          BookmarkStore.purge(id: sid)
        }
        if let screen = NSScreen.screen(forUUID: sid) {
          clear(for: screen, purgeBookmark: false)
        } else {
          // 无对应屏幕对象时直接移除记录
          players.removeValue(forKey: sid)
          loopers.removeValue(forKey: sid)
          currentViews.removeValue(forKey: sid)
          windowControllers.removeValue(forKey: sid)?.stop()
          screenContent.removeValue(forKey: sid)
          if let mirror = menuBarMirrors.removeValue(forKey: sid) {
            dlog("cleanupDisconnectedScreens stop mirror for id=\(sid)")
            mirror.stop()
          }
          if let strip = menuBarVideoViews.removeValue(forKey: sid) {
            dlog("cleanupDisconnectedScreens remove strip for id=\(sid)")
            strip.removeFromSuperview()
          }
        }
      }
    }
  }

  // MARK: - Missing Methods and Stubs

  // Debounced entry‑point: calls performBlackScreensCheck() once the work item executes
  private func checkBlackScreens() {
    blackScreensWorkItem?.cancel()
    blackScreensWorkItem = DispatchWorkItem { [weak self] in
      self?.performBlackScreensCheck()
    }
    DispatchQueue.main.asyncAfter(
      deadline: .now() + 1,
      execute: blackScreensWorkItem!)
  }

  /// Actual black‑screen detection logic (formerly the body of checkBlackScreens).
  private func performBlackScreensCheck() {
    dlog("check black screens")
    for screen in NSScreen.screens {
      let sid = id(for: screen)
      let hasBookmark = (BookmarkStore.get(prefix: "bookmark", id: sid) as Data?) != nil
      let viewMissing = currentViews[sid] == nil
      let playerMissing = screenContent[sid]?.type == .video && players[sid] == nil
      guard hasBookmark && (viewMissing || playerMissing) else { continue }
      dlog(
        "black screen detected on \(screen.dv_localizedName) viewMissing=\(viewMissing) playerMissing=\(playerMissing)"
      )
      if playerMissing && !viewMissing {
        AppDelegate.shared.reloadAndPlayVideo(displayUUID: sid)
      } else {
        restoreFromBookmark(for: screen)
      }
    }
  }

  @objc private func handleScreenChange() {
    dlog("handling screen change")
    debounceWorkItem?.cancel()
    debounceWorkItem = DispatchWorkItem { [weak self] in
      self?.reloadScreens()
      self?.reassignAllWindows()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: debounceWorkItem!)
  }

  private func reloadScreens() {
    dlog("reload screens")
    let activeIDs = Set(NSScreen.screens.map { $0.dv_displayUUID })
    let knownIDs = Set(windowControllers.keys)

    // Remove disconnected screen windows
    for sid in knownIDs.subtracting(activeIDs) {
      dlog("removing UUID \(sid)")
      
      if let screen = NSScreen.screen(forUUID: sid) {
        clear(for: screen, purgeBookmark: false)
      } else {
        // Direct cleanup when no screen object exists
        if let overlay = overlayWindows[sid] {
          NotificationCenter.default.removeObserver(
            AppDelegate.shared as Any,
            name: NSWindow.didChangeOcclusionStateNotification,
            object: overlay)
          overlay.orderOut(nil)
          overlayWindows.removeValue(forKey: sid)
        }
        if let overlay = screensaverOverlayWindows[sid] {
          overlay.orderOut(nil)
          screensaverOverlayWindows.removeValue(forKey: sid)
        }
        windowControllers.removeValue(forKey: sid)?.stop()
        currentViews[sid]?.removeFromSuperview()
        currentViews.removeValue(forKey: sid)
        players[sid]?.pause()
        players[sid]?.replaceCurrentItem(with: nil)
        players.removeValue(forKey: sid)
        loopers.removeValue(forKey: sid)
        screenContent.removeValue(forKey: sid)
      }
    }

    // Add windows for newly connected screens
    for screen in NSScreen.screens {
      let sid = screen.dv_displayUUID
      guard !knownIDs.contains(sid) else { continue }
      dlog("add window for \(screen.dv_localizedName)")
      
      // Restore content if available
      if let entry = screenContent[sid] {
        switch entry.type {
        case .image:
          showImage(for: screen, url: entry.url, stretch: entry.stretch)
        case .video:
          showVideo(for: screen, url: entry.url, stretch: entry.stretch, volume: entry.volume ?? 1.0)
        }
      } else if BookmarkStore.get(prefix: "bookmark", id: sid) != nil {
        restoreFromBookmark(for: screen)
      }
    }
  }

  // Placeholder for missing method: reassignAllWindows
  @objc func reassignAllWindows() {
    // TODO: Implement window reassignment logic if needed
    dlog("reassignAllWindows called (stub)")
  }

  // Placeholder for missing selector method: windowScreenDidChange
  @objc func windowScreenDidChange(_: Notification) {
    // TODO: Implement window screen change handling if needed
    dlog("windowScreenDidChange called (stub)")
  }

  // Placeholder for missing function: allOverlaysCompletelyCovered
  func allOverlaysCompletelyCovered() -> Bool {
    // TODO: Implement actual overlay coverage check
    return false
  }

  // Placeholder for missing function: anyOverlayCompletelyCovered
  func anyOverlayCompletelyCovered() -> Bool {
    // TODO: Implement actual overlay coverage check
    return false
  }

  // MARK: - AVDataAsset
  // 将内存中的视频数据写入带扩展名的临时文件以供播放
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
}

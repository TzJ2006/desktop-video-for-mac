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
  
  /// 防止全局静音状态循环更新的标志
  private var isUpdatingGlobalMute = false

  private var debounceWorkItem: DispatchWorkItem?
  private var blackScreensWorkItem: DispatchWorkItem?
//  private var windowScreenChangeWorkItem: DispatchWorkItem?

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

    // Screensaver‑overlay window
    if let saverOverlay = screensaverOverlayWindows[sid], saverOverlay.screen !== screen {
      saverOverlay.orderOut(nil)
      screensaverOverlayWindows.removeValue(forKey: sid)
    }
  }

  @objc private func handleWake() {
    dlog("handling wake")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      // 唤醒后统一判断当前播放策略
      AppDelegate.shared?.updatePlaybackStateForAllScreens()
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

//  private var cancellables: Set<AnyCancellable> = []

  /// 全局静音前记录各屏幕的音量
  private var savedVolumes: [String: Float] = [:]
  private var currentViews: [String: NSView] = [:]
  private var loopers: [String: AVPlayerLooper] = [:]
  var windowControllers: [String: WallpaperWindowController] = [:]
  /// 用于检测遮挡状态的小窗口（每个屏幕四个）
  var overlayWindows: [String: NSWindow] = [:]
  /// 全屏覆盖窗口，用于屏保启动前的遮挡检测
  var screensaverOverlayWindows: [String: NSWindow] = [:]
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
      existingPlayer.volume = AppState.shared.isGlobalMuted ? 0.0 : volume
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

      queuePlayer.volume = AppState.shared.isGlobalMuted ? 0.0 : volume

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
    isUpdatingGlobalMute = true // 设置标志，防止死循环
    // 先记录音量再静音
    for sid in screenContent.keys {
      let currentVol = screenContent[sid]?.volume ?? 0
      if currentVol > 0 { savedVolumes[sid] = currentVol }
      if let screen = NSScreen.screen(forUUID: sid) {
        setVolume(0, for: screen)
      }
    }
    isUpdatingGlobalMute = false // 重置标志
  }

  /// 恢复所有屏幕在上次全局静音前的音量，
  /// 已经为 0 的屏幕保持静音。
  func restoreAllScreens() {
    dlog("restore all screens")
    isUpdatingGlobalMute = true // 设置标志，防止死循环
    for sid in screenContent.keys {
      let newVol = savedVolumes[sid] ?? (screenContent[sid]?.volume ?? 0)
      if let screen = NSScreen.screen(forUUID: sid) {
        setVolume(newVol, for: screen)
      }
    }
    savedVolumes.removeAll()
    isUpdatingGlobalMute = false // 重置标志

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
    players[sid]?.volume = AppState.shared.isGlobalMuted ? 0.0 : volume
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
      "save bookmark for \(screen.dv_displayUUID) url=\(url.lastPathComponent) stretch=\(stretch) volume=\(String(describing: volume))"
    )
    let uuid = screen.dv_displayUUID

    func persist(_ data: Data) {
      BookmarkStore.set(data, prefix: "bookmark", id: uuid)
      BookmarkStore.set(stretch, prefix: "stretch", id: uuid)
      BookmarkStore.set(volume, prefix: "volume", id: uuid)
      BookmarkStore.set(Date().timeIntervalSince1970, prefix: "savedAt", id: uuid)
    }

    do {
      // Prefer a security-scoped bookmark. This does not require calling startAccessing here.
      let scoped = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
      persist(scoped)
      dlog("saved security-scoped bookmark for \(url.lastPathComponent)")

      // Save raw URL and guessed type for fallback restore
      saveBookmarkFallbackData(for: url, uuid: uuid)

      return
    } catch {
      errorLog("Failed to create security-scoped bookmark: \(error.localizedDescription). Will attempt non-scoped bookmark.")
    }

    do {
      // Fallback: non–security-scoped bookmark. This still helps re-open within same sandbox permissions.
      let nonScoped = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      persist(nonScoped)
      dlog("saved non-scoped bookmark for \(url.lastPathComponent)")

      // Save raw URL and guessed type for fallback restore
      saveBookmarkFallbackData(for: url, uuid: uuid)

    } catch {
      errorLog("Failed to save bookmark for \(url): \(error)")
    }
  }

  /// Save URL and type information for fallback restoration when bookmark fails
  private func saveBookmarkFallbackData(for url: URL, uuid: String) {
    BookmarkStore.set(url.absoluteString, prefix: "lastURL", id: uuid)
    // Guess type by extension for fallback restore
    let ext = url.pathExtension.lowercased()
    let lastType: String
    if ["mp4", "mov", "m4v"].contains(ext) {
      lastType = "video"
    } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
      lastType = "image"
    } else {
      lastType = "unknown"
    }
    BookmarkStore.set(lastType, prefix: "lastType", id: uuid)
  }

  /// Attempt to restore content using fallback URL and type when bookmark fails
  private func restoreFromFallback(uuid: String, screen: NSScreen) {
    guard let lastURLString: String = BookmarkStore.get(prefix: "lastURL", id: uuid),
          let lastType: String = BookmarkStore.get(prefix: "lastType", id: uuid),
          let fallbackURL = URL(string: lastURLString) else { return }
    
    let stretch: Bool = BookmarkStore.get(prefix: "stretch", id: uuid) ?? false
    let volume: Float = BookmarkStore.get(prefix: "volume", id: uuid) ?? 1.0
    
    if lastType == "video" {
      dlog("fallback restore video \(fallbackURL.lastPathComponent) on \(screen.dv_localizedName)")
      showVideo(for: screen, url: fallbackURL, stretch: stretch, volume: volume)
    } else if lastType == "image" {
      dlog("fallback restore image \(fallbackURL.lastPathComponent) on \(screen.dv_localizedName)")
      showImage(for: screen, url: fallbackURL, stretch: stretch)
    } else {
      dlog("fallback restore unknown type for URL: \(fallbackURL)")
    }
  }

  func restoreFromBookmark() {
    dlog("restore from bookmark")
    for screen in NSScreen.screens {
      dlog("Check screen: \(screen.dv_localizedName)")
      let uuid = screen.dv_displayUUID
      
      guard let bookmarkData: Data = BookmarkStore.get(prefix: "bookmark", id: uuid) else {
        // Fallback: try lastURL/lastType if bookmark missing or unusable
        restoreFromFallback(uuid: uuid, screen: screen)
        continue
      }

      var isStale = false
      do {
        let url = try URL(
          resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil,
          bookmarkDataIsStale: &isStale)
        let didStart = url.startAccessingSecurityScopedResource()
        if !didStart {
          dlog("bookmark restore: not security-scoped or startAccessing failed for \(url.lastPathComponent); proceeding anyway")
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
        // Fallback: try lastURL/lastType if bookmark unusable
        restoreFromFallback(uuid: uuid, screen: screen)
      }
    }
  }

  /// 仅恢复指定屏幕的书签内容
  func restoreFromBookmark(for screen: NSScreen) {
    dlog("restoreFromBookmark \(screen.dv_localizedName)")
    let uuid = screen.dv_displayUUID
    
    guard let bookmarkData: Data = BookmarkStore.get(prefix: "bookmark", id: uuid) else {
      // Fallback: try lastURL/lastType if bookmark missing or unusable
      restoreFromFallback(uuid: uuid, screen: screen)
      return
    }
    
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil,
        bookmarkDataIsStale: &isStale)
      let didStart = url.startAccessingSecurityScopedResource()
      if !didStart {
        dlog("bookmark restore: not security-scoped or startAccessing failed for \(url.lastPathComponent); proceeding anyway")
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
      // Fallback: try lastURL/lastType if bookmark unusable
      restoreFromFallback(uuid: uuid, screen: screen)
    }
  }

  func setVolume(_ volume: Float, for screen: NSScreen) {
    dlog("set volume for \(screen.dv_localizedName) volume=\(volume)")
    let sid = id(for: screen)
    if let entry = screenContent[sid], entry.type == .video {
      // 防止死循环：只有在不是程序内部更新全局静音状态时才取消全局静音
      if volume > 0 && !isUpdatingGlobalMute {
        AppState.shared.isGlobalMuted = false
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
        cleanupScreenResources(forUUID: sid, purgeBookmark: false)
      }
    }
  }

  /// Clean up all resources associated with a screen UUID
  private func cleanupScreenResources(forUUID sid: String, purgeBookmark: Bool) {
    if let screen = NSScreen.screen(forUUID: sid) {
      clear(for: screen, purgeBookmark: purgeBookmark)
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
      cleanupScreenResources(forUUID: sid, purgeBookmark: false)
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

}

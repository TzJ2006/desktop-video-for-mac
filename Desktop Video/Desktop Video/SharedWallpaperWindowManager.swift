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
    if let win = windows[sid], win.screen !== screen {
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

  func syncWindow(to screen: NSScreen, from source: NSScreen) {

    dlog("syncing window from \(source.dv_localizedName) to \(screen.dv_localizedName)")
    let srcID = id(for: source)
    guard let entry = screenContent[srcID] else { return }

    // 获取当前播放状态
    let currentVolume = players[srcID]?.volume ?? 1.0
    let isVideoStretch: Bool
    if let gravity = (currentViews[srcID] as? AVPlayerView)?.videoGravity {
      isVideoStretch = (gravity == .resizeAspectFill)
    } else {
      isVideoStretch = false
    }
    let isImageStretch =
      (currentViews[srcID] as? NSImageView)?.imageScaling == .scaleAxesIndependently

    // 仅清理目标屏幕内容，保留源播放器以复用
    clear(for: screen)

    switch entry.type {
    case .image:
      showImage(for: screen, url: entry.url, stretch: isImageStretch)
      showImage(for: source, url: entry.url, stretch: isImageStretch)
      saveBookmark(for: entry.url, stretch: isImageStretch, volume: nil, screen: screen)
      saveBookmark(for: entry.url, stretch: isImageStretch, volume: nil, screen: source)
    case .video:
      // 复用源屏幕的视频播放器以避免内存暴涨
      showVideo(
        for: screen, url: entry.url, stretch: isVideoStretch, volume: currentVolume,
        allowReuse: true
      ) {
        dlog("synced video from \(source.dv_localizedName) to \(screen.dv_localizedName)")
      }
      saveBookmark(for: entry.url, stretch: isVideoStretch, volume: currentVolume, screen: screen)
      saveBookmark(for: entry.url, stretch: isVideoStretch, volume: currentVolume, screen: source)
    }

    // 若源条目是视频，则更新 AppState 中记录的地址
    if let sourceEntry = screenContent[srcID], sourceEntry.type != .image {
      AppState.shared.lastMediaURL = sourceEntry.url
    }
  }

  /// 全局静音前记录各屏幕的音量
  private var savedVolumes: [String: Float] = [:]
  private var currentViews: [String: NSView] = [:]
  private var loopers: [String: AVPlayerLooper] = [:]
  var windows: [String: WallpaperWindow] = [:]
  /// 用于检测遮挡状态的小窗口（每个屏幕四个）
  var overlayWindows: [String: NSWindow] = [:]
  /// 全屏覆盖窗口，用于屏保启动前的遮挡检测
  var screensaverOverlayWindows: [String: NSWindow] = [:]
  /// 状态栏视频窗口
  var statusBarWindows: [String: NSWindow] = [:]
  var players: [String: AVQueuePlayer] = [:]
  var screenContent: [String: (type: ContentType, url: URL, stretch: Bool, volume: Float?)] = [:]

  enum ContentType {
    case image
    case video
  }

  private func ensureWindow(for screen: NSScreen) {
    dlog("ensure window for \(screen.dv_localizedName)")
    let sid = id(for: screen)
    if windows[sid] != nil {
      windows[sid]?.orderFrontRegardless()
      return
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

    self.windows[sid] = win
    self.overlayWindows[sid] = overlay
    self.screensaverOverlayWindows[sid] = screensaverOverlay

    // 创建 / 恢复窗口后立即根据遮挡状态调整播放
    updatePlayState(for: screen)
  }

  func showImage(for screen: NSScreen, url: URL, stretch: Bool) {
    dlog("show image \(url.lastPathComponent) on \(screen.dv_localizedName) stretch=\(stretch)")
    ensureWindowOnCorrectScreen(for: screen)
    let sid = id(for: screen)
    ensureWindow(for: screen)
    stopVideoIfNeeded(for: screen)

    guard let image = NSImage(contentsOf: url),
      let contentView = windows[sid]?.contentView
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
    NotificationCenter.default.post(
      name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
    AppDelegate.shared?.startScreensaverTimer()
  }

  /// 为指定屏幕播放视频，始终从内存缓存读取数据。
  func showVideo(
    for screen: NSScreen, url: URL, stretch: Bool, volume: Float, allowReuse: Bool = true,
    onReady: (() -> Void)? = nil
  ) {
    ensureWindowOnCorrectScreen(for: screen)
    dlog(
      "show video \(url.lastPathComponent) on \(screen.dv_localizedName) stretch=\(stretch) volume=\(volume) UID=\(id(for: screen))"
    )
    do {
      let data: Data
      if let cached = AppDelegate.shared.cachedVideoData(for: url) {
        data = cached
      } else {
        let loaded = try Data(contentsOf: url)
        AppDelegate.shared.cacheVideoData(loaded, for: url)
        data = loaded
      }
      dlog("saveBookmark in showVideo for \(screen.dv_localizedName) url=\(url.lastPathComponent)")
      saveBookmark(for: url, stretch: stretch, volume: volume, screen: screen)
      AppState.shared.currentMediaURL = url.absoluteString
      AppDelegate.shared?.startScreensaverTimer()
      showVideoFromMemory(
        for: screen,
        data: data,
        stretch: stretch,
        volume: desktop_videoApp.shared!.globalMute ? 0.0 : volume,
        originalURL: url,
        allowReuse: allowReuse,
        onReady: onReady)
    } catch {
      errorLog("Cannot load from memory!")
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
      playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
    }
    updateBookmark(stretch: stretch, volume: volume, screen: screen)
  }

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

    // ---------- 新增：释放缓存 ----------
    if let entry = screenContent[sid], entry.type == .video {
      // 1️⃣ 先暂停并移除 player，确保没有引用
      stopVideoIfNeeded(for: screen)
      players[sid]?.replaceCurrentItem(with: nil)

      // 2️⃣ 若别的屏幕没在用，移除 Data 缓存
      let usedElsewhere = screenContent.contains { $0.key != sid && $0.value.url == entry.url }
      if !usedElsewhere { AppDelegate.shared.removeCachedVideoData(for: entry.url) }

      // 3️⃣ 无论如何，删除 **所有** 以 sid 为前缀的 temp 文件
      let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
      if let contents = try? FileManager.default.contentsOfDirectory(
        at: tempDir, includingPropertiesForKeys: nil)
      {
        for file in contents where file.lastPathComponent.hasPrefix("cached-\(sid)-") {
          try? FileManager.default.removeItem(at: file)
        }
      }
    } else {
      // 非视频也要移除潜在的播放器引用
      stopVideoIfNeeded(for: screen)
    }

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
    if let win = windows[sid] {
      win.orderOut(nil)
    }
    if !keepContent {
      screenContent.removeValue(forKey: sid)
      if screenContent.isEmpty {
        AppState.shared.currentMediaURL = nil
      }
    }
    windows.removeValue(forKey: sid)
    overlayWindows.removeValue(forKey: sid)
    screensaverOverlayWindows.removeValue(forKey: sid)
    NotificationCenter.default.post(
      name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
    AppDelegate.shared?.startScreensaverTimer()

    // 清除暂停状态
    pausedScreens.remove(sid)

    // 移除状态栏视频
    updateStatusBarVideo(for: screen)
  }

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
    dlog("stop video if needed on \(screen.dv_localizedName)")
    let sid = id(for: screen)
    guard let player = players[sid] else {
      players.removeValue(forKey: sid)
      loopers.removeValue(forKey: sid)
      return
    }

    let isShared = players.contains { key, value in
      key != sid && value === player
    }

    if !isShared {
      player.pause()
      player.replaceCurrentItem(with: nil)
      loopers[sid]?.disableLooping()
    } else {
      dlog("skip stopping shared player for \(screen.dv_localizedName)")
    }

    players.removeValue(forKey: sid)
    loopers.removeValue(forKey: sid)
  }

  private func switchContent(to newView: NSView, for screen: NSScreen) {
    dlog("switch content on \(screen.dv_localizedName)")
    let sid = id(for: screen)
    guard let contentView = windows[sid]?.contentView else { return }
    currentViews[sid]?.removeFromSuperview()
    contentView.addSubview(newView)
    currentViews[sid] = newView
    // 内容切换完成后，根据遮挡状态重新评估播放/暂停
    updatePlayState(for: screen)
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
  func refreshPlayState(for screen: NSScreen) {
    updatePlayState(for: screen)
  }

  /// 根据用户设置在状态栏显示或移除视频
  func updateStatusBarVideo(for screen: NSScreen) {
    let sid = id(for: screen)
    let enabled = UserDefaults.standard.bool(forKey: "showMenuBarVideo")
    guard enabled, let player = players[sid] else {
      if let win = statusBarWindows[sid] {
        dlog("remove status bar video on \(screen.dv_localizedName)")
        win.orderOut(nil)
        statusBarWindows.removeValue(forKey: sid)
      }
      return
    }

    dlog("update status bar video on \(screen.dv_localizedName)")
    let barHeight = NSStatusBar.system.thickness
    let screenFrame = screen.frame
    let frame = CGRect(
      x: screenFrame.minX, y: screenFrame.maxY - barHeight, width: screenFrame.width,
      height: barHeight)

    let win: NSWindow
    if let existing = statusBarWindows[sid] {
      win = existing
      win.setFrame(frame, display: true)
    } else {
      win = NSWindow(
        contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
      win.level = NSWindow.Level(Int(CGWindowLevelForKey(.backstopMenu)))
      win.isOpaque = false
      win.backgroundColor = .clear
      win.ignoresMouseEvents = true
      win.collectionBehavior = [.canJoinAllSpaces, .stationary]
      win.contentView?.wantsLayer = true
      win.contentView?.layer?.masksToBounds = true
      let viewFrame = CGRect(
        x: 0, y: barHeight - screenFrame.height, width: screenFrame.width,
        height: screenFrame.height)
      let view = AVPlayerView(frame: viewFrame)
      view.controlsStyle = .none
      view.videoGravity = .resizeAspectFill
      view.autoresizingMask = [.width]
      win.contentView?.addSubview(view)
      statusBarWindows[sid] = win
    }

    if let view = win.contentView?.subviews.first as? AVPlayerView {
      view.player = player
      view.frame = CGRect(
        x: 0, y: barHeight - screenFrame.height, width: screenFrame.width,
        height: screenFrame.height)
    }

    win.orderFrontRegardless()
  }

  /// 更新所有屏幕的状态栏视频
  func updateStatusBarVideoForAllScreens() {
    dlog("update status bar video for all screens")
    for screen in NSScreen.screens {
      updateStatusBarVideo(for: screen)
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
    for sid in Array(windows.keys) {
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
          windows.removeValue(forKey: sid)
          screenContent.removeValue(forKey: sid)
        }
      }
    }
  }

  func syncAllWindows(sourceScreen: NSScreen) {
    dlog("sync all windows from \(sourceScreen.dv_localizedName)")
    cleanupDisconnectedScreens()
    let srcID = id(for: sourceScreen)
    guard let currentEntry = screenContent[srcID] else {
      return
    }

    let currentVolume = players[srcID]?.volume ?? 1.0
    let isVideoStretch: Bool
    if let gravity = (currentViews[srcID] as? AVPlayerView)?.videoGravity {
      isVideoStretch = (gravity == .resizeAspectFill)
    } else {
      isVideoStretch = false
    }
    let isImageStretch =
      (currentViews[srcID] as? NSImageView)?.imageScaling == .scaleAxesIndependently
    let currentTime = players[srcID]?.currentItem?.currentTime()
    let shouldPlay = players[srcID]?.rate != 0

    // 先停止源屏幕的播放以断开共享
    stopVideoIfNeeded(for: sourceScreen)

    // 重新为源屏幕加载内容，不复用播放器
    switch currentEntry.type {
    case .image:
      showImage(for: sourceScreen, url: currentEntry.url, stretch: isImageStretch)
      saveBookmark(
        for: currentEntry.url, stretch: isImageStretch, volume: nil, screen: sourceScreen)
    case .video:
      showVideo(
        for: sourceScreen, url: currentEntry.url, stretch: isVideoStretch, volume: currentVolume,
        allowReuse: false
      ) {
        if let time = currentTime {
          let src = self.id(for: sourceScreen)
          self.players[src]?.pause()
          self.players[src]?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if shouldPlay { self.players[src]?.play() }
          }
        }
        self.saveBookmark(
          for: currentEntry.url, stretch: isVideoStretch, volume: currentVolume,
          screen: sourceScreen)
      }
    }

    for screen in NSScreen.screens {
      if screen == sourceScreen { continue }

      // 设置新内容前先停止并清空该屏幕
      stopVideoIfNeeded(for: screen)
      self.clear(for: screen)

      if currentEntry.type == .video {
        showVideo(
          for: screen, url: currentEntry.url, stretch: isVideoStretch, volume: currentVolume,
          allowReuse: false
        ) {
          if let time = currentTime {
            let destID = self.id(for: screen)
            self.players[destID]?.pause()
            self.players[destID]?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) {
              _ in
              if shouldPlay {
                self.players[destID]?.play()
              }
            }
          }
          // Save bookmark for synced video
          self.saveBookmark(
            for: currentEntry.url, stretch: isVideoStretch, volume: currentVolume, screen: screen)
        }
      } else if currentEntry.type == .image {
        showImage(for: screen, url: currentEntry.url, stretch: isImageStretch)
        // Save bookmark for synced image
        saveBookmark(for: currentEntry.url, stretch: isImageStretch, volume: nil, screen: screen)
      }
    }
  }

  @objc private func handleScreenChange() {

    //        return;

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
    let knownIDs = Set(windows.keys)

    // 移除已断开的屏幕窗口，安全地清理 overlay 和窗口
    for sid in knownIDs.subtracting(activeIDs) {
      dlog("removing UUID \(sid)")

      if let screen = NSScreen.screen(forUUID: sid) {
        // 屏幕对象仍存在时，使用 clear 保留书签
        clear(for: screen, purgeBookmark: false)
      } else {
        // 无对应屏幕对象时直接移除记录
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
        if let win = windows[sid] {
          win.orderOut(nil)
          windows.removeValue(forKey: sid)
        }
        currentViews[sid]?.removeFromSuperview()
        currentViews.removeValue(forKey: sid)
        players[sid]?.pause()
        players[sid]?.replaceCurrentItem(with: nil)
        players.removeValue(forKey: sid)
        loopers.removeValue(forKey: sid)
        screenContent.removeValue(forKey: sid)
      }

      // 清理过期书签，但保留有效书签
      if let savedAt: Double = BookmarkStore.get(prefix: "savedAt", id: sid),
        Date().timeIntervalSince1970 - savedAt > 86400
      {
        BookmarkStore.purge(id: sid)
      }
    }

    // 为新连接的屏幕创建窗口
    let autoSync = UserDefaults.standard.bool(forKey: "autoSyncNewScreens")
    let existingID = knownIDs.first
    var sourceScreen: NSScreen? = nil
    if autoSync, let id = existingID {
      sourceScreen = NSScreen.screen(forUUID: id)
    }

    for screen in NSScreen.screens {
      let sid = screen.dv_displayUUID
      guard !knownIDs.contains(sid) else { continue }
      dlog("add window for \(screen.dv_localizedName)")

      // 新增屏幕时先清理窗口但保留书签与内容记录
      clear(for: screen, purgeBookmark: false, keepContent: true)

      if let src = sourceScreen {
        syncWindow(to: screen, from: src)
      } else if let entry = screenContent[sid] {
        switch entry.type {
        case .image:
          showImage(for: screen, url: entry.url, stretch: entry.stretch)
        case .video:
          showVideo(
            for: screen, url: entry.url, stretch: entry.stretch, volume: entry.volume ?? 1.0)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let player = self.players[sid], player.timeControlStatus != .playing {
              player.play()
            }
          }
        }
      } else if let _: Data = BookmarkStore.get(prefix: "bookmark", id: sid) {
        // 没有记录时尝试从书签恢复
        restoreFromBookmark(for: screen)
      } else if let lastURL = AppState.shared.lastMediaURL {
        dlog("apply last media for \(screen.dv_localizedName)")
        let ext = lastURL.pathExtension.lowercased()
        let stretch = AppState.shared.lastStretchToFill
        let volume = AppState.shared.lastVolume
        if ["mp4", "mov", "m4v"].contains(ext) {
          showVideo(for: screen, url: lastURL, stretch: stretch, volume: volume)
          saveBookmark(for: lastURL, stretch: stretch, volume: volume, screen: screen)
        } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
          showImage(for: screen, url: lastURL, stretch: stretch)
          saveBookmark(for: lastURL, stretch: stretch, volume: nil, screen: screen)
        }
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.checkBlackScreens()
      self?.reassignAllWindows()
    }
  }

  // Debounced entry‑point: calls performBlackScreensCheck() once the
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
        AppDelegate.shared.reloadAndPlayVideoFromMemory(displayUUID: sid)
      } else {
        restoreFromBookmark(for: screen)
      }
    }
  }

  /// 将内存中的视频数据写入临时文件后播放。
  /// - Parameters:
  ///   - screen: 要显示视频的屏幕
  ///   - data: 视频数据
  ///   - stretch: 是否铺满
  ///   - volume: 播放音量
  ///   - originalURL: 用户选择的视频源地址
  ///   - allowReuse: 是否允许与其他屏幕复用播放器
  ///   - onReady: 准备完成回调
  func showVideoFromMemory(
    for screen: NSScreen, data: Data, stretch: Bool, volume: Float, originalURL: URL? = nil,
    allowReuse: Bool = true, onReady: (() -> Void)? = nil
  ) {
    dlog("show video from memory on \(screen.dv_localizedName) stretch=\(stretch) volume=\(volume)")
    ensureWindowOnCorrectScreen(for: screen)
    let sid = id(for: screen)

    // Fast path: same screen, same URL → just reuse the existing player / view.
    if allowReuse,
      let existingContent = screenContent[sid],
      existingContent.type == .video,
      existingContent.url == originalURL,
      let existingPlayer = players[sid]
    {

      dlog("reuse existing video player on same screen \(sid)")
      // Update stretch and volume only.
      existingPlayer.volume = volume
      if let playerView = currentViews[sid] as? AVPlayerView {
        playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
      }
      // Ensure it is playing.
      if existingPlayer.timeControlStatus != .playing {
        existingPlayer.play()
      }
      // Refresh cached meta.
      screenContent[sid] = (.video, originalURL ?? existingContent.url, stretch, volume)
      NotificationCenter.default.post(
        name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
      return
    }

    // 1. 优先尝试重用已存在的相同视频播放器
    if allowReuse {
      for (existingSID, content) in screenContent {
        if existingSID != sid,
          content.type == .video,
          content.url == originalURL,
          let existingPlayer = players[existingSID]
        {
          _ = currentViews[existingSID] as? AVPlayerView
          dlog("reuse existing video player from screen \(existingSID)")
          ensureWindow(for: screen)
          stopVideoIfNeeded(for: screen)
          let clonePlayerView = AVPlayerView(frame: windows[sid]!.contentView!.bounds)
          clonePlayerView.player = existingPlayer
          clonePlayerView.controlsStyle = .none
          clonePlayerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
          clonePlayerView.autoresizingMask = [.width, .height]
          players[sid] = existingPlayer
          loopers[sid] = loopers[existingSID]
          screenContent[sid] = (.video, originalURL!, stretch, volume)
          switchContent(to: clonePlayerView, for: screen)
          NotificationCenter.default.post(
            name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
          return
        }
      }
    }

    // Cleanup *other* cached temp files for this screen (keep the current hashed one)
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
    // Use a stable file name derived from the original URL so we only write once.
    let hashed = originalURL?.lastPathComponent.hashValue ?? 0
    let fileName = "cached-\(sid)-\(hashed).\(originalURL?.pathExtension ?? "mov")"
    if let contents = try? FileManager.default.contentsOfDirectory(
      at: tempDir, includingPropertiesForKeys: nil, options: [])
    {
      for fileURL in contents
      where fileURL.lastPathComponent.hasPrefix("cached-\(sid)-")
        && fileURL.lastPathComponent != fileName
      {
        try? FileManager.default.removeItem(at: fileURL)
      }
    }

    // Remove previous cached video data for this URL to free memory,
    // 但如果其他屏幕还在使用该视频，则不移除
    if let previousURL = screenContent[sid]?.url {
      let stillInUse = screenContent.contains { $0.key != sid && $0.value.url == previousURL }
      if !stillInUse {
        AppDelegate.shared.removeCachedVideoData(for: previousURL)
      }
    }

    ensureWindow(for: screen)
    stopVideoIfNeeded(for: screen)
    guard let contentView = windows[sid]?.contentView else { return }

    guard let contentType = UTType(filenameExtension: originalURL?.pathExtension ?? "mov"),
      contentType.conforms(to: .movie)
    else {
      errorLog("Unsupported video type")
      return
    }

    let tempURL = tempDir.appendingPathComponent(fileName)

    if !FileManager.default.fileExists(atPath: tempURL.path) {
      do {
        try data.write(to: tempURL)
      } catch {
        errorLog("Failed to write temp file for video: \(error)")
        return
      }
    }

    let asset = AVAsset(url: tempURL)
    let item = AVPlayerItem(asset: asset)
    let queuePlayer = AVQueuePlayer()
    queuePlayer.automaticallyWaitsToMinimizeStalling = false
    let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

    queuePlayer.volume = volume

    let playerView = AVPlayerView(frame: contentView.bounds)
    playerView.player = queuePlayer
    playerView.controlsStyle = .none
    playerView.videoGravity = stretch ? .resizeAspectFill : .resizeAspect
    playerView.autoresizingMask = [.width, .height]

    players[sid] = queuePlayer
    loopers[sid] = looper
    // 记录原始视频地址而非临时文件，用于保留用户选择
    let existingURL = screenContent[sid]?.url
    let actualURL = originalURL ?? existingURL ?? URL(fileURLWithPath: L("UnknownPath"))
    screenContent[sid] = (.video, actualURL, stretch, volume)

    if let sourceURL = originalURL {
      saveBookmark(for: sourceURL, stretch: stretch, volume: volume, screen: screen)
    }

    switchContent(to: playerView, for: screen)
    queuePlayer.play()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      dlog("delayed play state check for \(screen.dv_localizedName)")
      self?.updatePlayState(for: screen)
    }
    // 视频开始播放时移除暂停标记
    pausedScreens.remove(sid)
    NotificationCenter.default.post(
      name: NSNotification.Name("WallpaperContentDidChange"), object: nil)
  }

  /// 控制单个屏幕视频的暂停/播放
  func setPaused(_ paused: Bool, for screen: NSScreen) {
    let sid = id(for: screen)
    guard let player = players[sid] else { return }
    if paused {
      pausedScreens.insert(sid)
      player.pause()
    } else {
      pausedScreens.remove(sid)
      player.play()
    }
  }

  // MARK: - Automatic window reassignment
  /// 当系统把窗口挪到错误显示器时，自动迁回正确屏幕
  private func reassignWindowIfNeeded(for sid: String) {
    dlog("reassignWindowIfNeeded \(sid)")
    guard
      let expected = NSScreen.screen(forUUID: sid),
      let win = windows[sid],
      win.screen !== expected  // 屏幕不一致
    else { return }

    // 记录内容描述后先清理
    let entry = screenContent[sid]
    if let wrong = win.screen {
      clear(for: wrong, purgeBookmark: false, keepContent: true)
    }

    // 重新创建窗口并恢复内容
    if let entry = entry {
      switch entry.type {
      case .image:
        showImage(for: expected, url: entry.url, stretch: entry.stretch)
      case .video:
        showVideo(
          for: expected,
          url: entry.url,
          stretch: entry.stretch,
          volume: entry.volume ?? 1.0)
      }
    } else {
      restoreFromBookmark(for: expected)  // 没记录时走书签恢复
    }
  }

  /// 遍历全部窗口/overlay，批量校正
  private func reassignAllWindows() {
    dlog("reassignAllWindows")
    for sid in windows.keys { reassignWindowIfNeeded(for: sid) }
    for sid in overlayWindows.keys { reassignWindowIfNeeded(for: sid) }
  }

  /// 捕捉窗口被系统改屏事件
  @objc private func windowScreenDidChange(_ note: Notification) {
    guard let win = note.object as? NSWindow else { return }
    windowScreenChangeWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      dlog("windowScreenDidChange")
      if let sid = self.windows.first(where: { $0.value == win })?.key {
        self.reassignWindowIfNeeded(for: sid)
      } else if let sid = self.overlayWindows.first(where: { $0.value == win })?.key {
        self.reassignWindowIfNeeded(for: sid)
      }
      self.checkBlackScreens()
    }
    windowScreenChangeWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
  }
  // MARK: - Overlay coverage helpers (CoreGraphics)

  /// Returns true iff *some* window in front of `overlay` completely covers its bounds.
  private func overlayCompletelyCovered(_ overlay: NSWindow) -> Bool {
    let overlayID = CGWindowID(overlay.windowNumber)
    let overlayRect = overlay.frame

    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
      return false
    }

    for win in info {
      guard let wid = win[kCGWindowNumber as String] as? CGWindowID else { continue }

      if wid == overlayID {
        // Walked past overlay ⇒ nothing fully covers it
        return false
      }

      // Skip transparent / off‑screen windows
      let alpha = (win[kCGWindowAlpha as String] as? Double) ?? 1.0
      let ons = (win[kCGWindowIsOnscreen as String] as? Bool) ?? true
      if alpha < 0.01 || !ons { continue }

      if let boundsDict = win[kCGWindowBounds as String] as? NSDictionary,
        let winRect = CGRect(dictionaryRepresentation: boundsDict),
        winRect.contains(overlayRect)
      {
        return true
      }
    }
    return false
  }

  /// All overlay windows are completely hidden by front‑most windows.
  func allOverlaysCompletelyCovered() -> Bool {
    for overlay in overlayWindows.values where !overlayCompletelyCovered(overlay) {
      return false
    }
    return !overlayWindows.isEmpty  // At least one overlay must exist
  }

  /// At least one overlay window is fully covered.
  func anyOverlayCompletelyCovered() -> Bool {
    for overlay in overlayWindows.values where overlayCompletelyCovered(overlay) {
      return true
    }
    return false
  }
}

//
//  ScreensaverManager.swift
//  desktop video
//
//  Created by ChatGPT on 2025-06-11.
//

import AppKit
import Combine
import IOKit
import IOKit.pwr_mgt

/// 管理屏保逻辑的单例
class ScreensaverManager {
    static let shared = ScreensaverManager()

    private var screensaverTimer: Timer?
    private var eventMonitors: [Any] = []
    private(set) var isInScreensaver = false
    private var clockDateLabels: [NSTextField] = []
    private var clockTimeLabels: [NSTextField] = []
    private var clockTimer: Timer?
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var otherAppSuppressScreensaver: Bool = false

    private let screensaverEnabledKey = "screensaverEnabled"
    private let screensaverDelayMinutesKey = "screensaverDelayMinutes"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        dlog("ScreensaverManager init")
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.startTimer()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil)

        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(self,
                               selector: #selector(handleExternalScreensaverActive(_:)),
                               name: Notification.Name("OtherAppScreensaverActive"),
                               object: nil)
        distCenter.addObserver(self,
                               selector: #selector(handleExternalScreensaverInactive(_:)),
                               name: Notification.Name("OtherAppScreensaverInactive"),
                               object: nil)
    }

    // MARK: - Timer
    func startTimer() {
        if screensaverTimer != nil && screensaverTimer?.isValid == true {
            dlog("startTimer: timer already running")
            return
        }
        dlog("startTimer isInScreensaver=\(isInScreensaver) otherApp=\(otherAppSuppressScreensaver) url=\(AppState.shared.currentMediaURL ?? "None")")
        guard !otherAppSuppressScreensaver else { return }
        guard !isInScreensaver else { return }
        guard AppState.shared.currentMediaURL != nil else { return }

        screensaverTimer?.invalidate()
        screensaverTimer = nil

        guard UserDefaults.standard.bool(forKey: screensaverEnabledKey) else {
            closeScreensaverWindows()
            return
        }

        let delayMinutes = UserDefaults.standard.integer(forKey: screensaverDelayMinutesKey)
        let delaySeconds = TimeInterval(max(delayMinutes, 1) * 60)

        screensaverTimer = Timer.scheduledTimer(withTimeInterval: delaySeconds / 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard AppState.shared.currentMediaURL != nil else {
                self.screensaverTimer?.invalidate()
                self.screensaverTimer = nil
                return
            }
            let idleTime = self.getSystemIdleTime()
            dlog("idleTime=\(idleTime) delaySeconds=\(delaySeconds)")
            if idleTime >= delaySeconds {
                self.screensaverTimer?.invalidate()
                self.screensaverTimer = nil
                self.runScreenSaver()
            }
        }
    }

    private func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator)
        if result != KERN_SUCCESS { return 0 }

        let entry = IOIteratorNext(iterator)
        IOObjectRelease(iterator)

        var dict: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0)
        IOObjectRelease(entry)

        guard kr == KERN_SUCCESS,
              let cfDict = dict?.takeRetainedValue() as? [String: Any],
              let idleNS = cfDict["HIDIdleTime"] as? UInt64 else {
            return 0
        }

        return TimeInterval(idleNS) / 1_000_000_000
    }

    @objc private func appDidBecomeActive() {
        dlog("appDidBecomeActive")
        if isInScreensaver {
            closeScreensaverWindows()
        }
    }

    @objc private func appDidResignActive() {
        dlog("appDidResignActive")
        if !isInScreensaver {
            startTimer()
        }
    }

    // MARK: - Screensaver
    @objc func runScreenSaver() {
        dlog("runScreenSaver isInScreensaver=\(isInScreensaver)")
        guard UserDefaults.standard.bool(forKey: screensaverEnabledKey) else { return }
        if isInScreensaver { return }

        let assertionReason = "DesktopVideo screensaver active" as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionReason,
            &displaySleepAssertionID
        )

        let keys = NSScreen.screens.compactMap { screen in
            screen.dv_displayID.flatMap { id in
                SharedWallpaperWindowManager.shared.windows.keys.contains(id) ? id : nil
            }
        }

        for overlays in SharedWallpaperWindowManager.shared.overlayWindows.values {
            for overlay in overlays { overlay.orderOut(nil) }
        }

        for id in keys {
            if let screen = NSScreen.screen(forDisplayID: id) {
                guard let wallpaperWindow = SharedWallpaperWindowManager.shared.windows[id] else { continue }
                wallpaperWindow.level = .screenSaver
                wallpaperWindow.ignoresMouseEvents = false
                wallpaperWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                wallpaperWindow.alphaValue = 0
                wallpaperWindow.makeKeyAndOrderFront(nil)

                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.5
                    wallpaperWindow.animator().alphaValue = 1
                }, completionHandler: nil)

                if let entry = SharedWallpaperWindowManager.shared.screenContent[id], entry.type == .video {
                    do {
                        let data = try Data(contentsOf: entry.url)
                        SharedWallpaperWindowManager.shared.showVideoFromMemory(
                            for: screen,
                            data: data,
                            stretch: entry.stretch,
                            volume: entry.volume ?? 1.0
                        )
                    } catch {
                        errorLog("Failed to reload video data from memory: \(error)")
                    }
                } else {
                    SharedWallpaperWindowManager.shared.reloadAndPlayVideoFromMemory(displayID: id)
                }

                let dateLabel = NSTextField(labelWithString: "")
                dateLabel.font = NSFont(name: "DIN Alternate", size: 30) ?? NSFont.systemFont(ofSize: 30, weight: .medium)
                dateLabel.textColor = .white
                dateLabel.backgroundColor = .clear
                dateLabel.isBezeled = false
                dateLabel.isEditable = false
                dateLabel.sizeToFit()
                if let contentBounds = wallpaperWindow.contentView?.bounds {
                    let dateX = contentBounds.midX - dateLabel.frame.width / 2
                    let dateY = contentBounds.maxY - dateLabel.frame.height - 50
                    dateLabel.frame.origin = CGPoint(x: dateX, y: dateY)
                }
                wallpaperWindow.contentView?.addSubview(dateLabel)
                clockDateLabels.append(dateLabel)

                let timeLabel = NSTextField(labelWithString: "")
                timeLabel.font = NSFont(name: "DIN Alternate", size: 100) ?? NSFont.systemFont(ofSize: 100, weight: .light)
                timeLabel.textColor = .white
                timeLabel.backgroundColor = .clear
                timeLabel.isBezeled = false
                timeLabel.isEditable = false
                timeLabel.sizeToFit()
                if let contentBounds = wallpaperWindow.contentView?.bounds {
                    let dateY = dateLabel.frame.origin.y
                    let dateHeight = dateLabel.frame.height
                    let timeX = contentBounds.midX - timeLabel.frame.width / 2
                    let timeY = dateY - dateHeight - timeLabel.frame.height - 30
                    timeLabel.frame.origin = CGPoint(x: timeX, y: timeY)
                }
                wallpaperWindow.contentView?.addSubview(timeLabel)
                clockTimeLabels.append(timeLabel)
            }
        }

        updateClockLabels()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClockLabels()
        }

        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let eventTypes: [NSEvent.EventTypeMask] = [.any]
            for eventType in eventTypes {
                if let monitor = NSEvent.addGlobalMonitorForEvents(matching: eventType, handler: { [weak self] _ in
                    self?.closeScreensaverWindows()
                }) {
                    self.eventMonitors.append(monitor)
                }
            }
            if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .any, handler: { [weak self] event in
                self?.closeScreensaverWindows()
                return event
            }) {
                self.eventMonitors.append(localMonitor)
            }
            self.isInScreensaver = true
        }
    }

    func closeScreensaverWindows() {
        dlog("closeScreensaverWindows")
        if !isInScreensaver { return }

        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }

        clockTimer?.invalidate()
        clockTimer = nil
        for label in clockDateLabels { label.removeFromSuperview() }
        clockDateLabels.removeAll()
        for label in clockTimeLabels { label.removeFromSuperview() }
        clockTimeLabels.removeAll()

        for (id, wallpaperWindow) in SharedWallpaperWindowManager.shared.windows {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                wallpaperWindow.animator().alphaValue = 0
            }, completionHandler: {
                wallpaperWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
                wallpaperWindow.ignoresMouseEvents = true
                wallpaperWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                wallpaperWindow.orderBack(nil)
                SharedWallpaperWindowManager.shared.reloadAndPlayVideoFromMemory(displayID: id)
                wallpaperWindow.alphaValue = 1
            })
        }

        for overlays in SharedWallpaperWindowManager.shared.overlayWindows.values {
            for overlay in overlays { overlay.orderFrontRegardless() }
        }

        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()

        isInScreensaver = false
        startTimer()
    }

    private func updateClockLabels() {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "EEEE, yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: Date())

        for (index, dateLabel) in clockDateLabels.enumerated() {
            guard index < clockTimeLabels.count, index < NSScreen.screens.count else { continue }
            let timeLabel = clockTimeLabels[index]
            let screen = NSScreen.screens[index]
            if let sid = screen.dv_displayID,
               let window = SharedWallpaperWindowManager.shared.windows[sid],
               let contentBounds = window.contentView?.bounds {
                dateLabel.stringValue = dateString
                dateLabel.sizeToFit()
                let dateX = contentBounds.midX - dateLabel.frame.width / 2
                let dateY = contentBounds.maxY - dateLabel.frame.height - 50
                dateLabel.frame.origin = CGPoint(x: dateX, y: dateY)

                timeLabel.stringValue = timeString
                timeLabel.sizeToFit()
                let timeX = contentBounds.midX - timeLabel.frame.width / 2
                let timeY = dateY - dateLabel.frame.height - timeLabel.frame.height - 30
                timeLabel.frame.origin = CGPoint(x: timeX, y: timeY)
            }
        }
    }

    // MARK: - External
    @objc private func handleExternalScreensaverActive(_ notification: Notification) {
        dlog("handleExternalScreensaverActive")
        otherAppSuppressScreensaver = true
        screensaverTimer?.invalidate()
        screensaverTimer = nil
    }

    @objc private func handleExternalScreensaverInactive(_ notification: Notification) {
        dlog("handleExternalScreensaverInactive")
        otherAppSuppressScreensaver = false
        startTimer()
    }
}

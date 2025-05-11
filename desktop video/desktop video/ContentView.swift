//
//  ContentView.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/20/25.
//

// ContentView.swift (使用 SharedWallpaperWindowManager)

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Foundation



class AppState: ObservableObject {
    static let shared = AppState()
    @Published var lastMediaURL: URL?
    @Published var lastVolume: Float = 1.0
    @Published var lastStretchToFill: Bool = true
}

class ScreenObserver: ObservableObject {
    @Published var screens: [NSScreen] = NSScreen.screens

    private var observer: NSObjectProtocol?
    private var previousScreens: [NSScreen] = NSScreen.screens

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard let self = self else { return }
                let current = NSScreen.screens
                let added = current.filter { !self.previousScreens.contains($0) }
                self.screens = current
                self.previousScreens = current

                if UserDefaults.standard.bool(forKey: "autoSyncNewScreens"), let source = current.first {
                    for screen in added {
                        SharedWallpaperWindowManager.shared.syncWindow(to: screen, from: source)
                    }
                }
            }
        }
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct ContentView: View {
    
    @ObservedObject private var appState = AppState.shared
    @AppStorage("isMenuBarOnly") var isMenuBarOnly: Bool = false
    @AppStorage("autoSyncNewScreens") var autoSyncNewScreens: Bool = true
    @AppStorage("globalMute") private var globalMute: Bool = false   // <─ New line
    @State private var syncAllScreens: Bool = false
    @State private var selectedTabScreen: NSScreen? = NSScreen.screens.first
    @StateObject private var screenObserver = ScreenObserver()

    var body: some View {
        VStack {
            Spacer()
            if screenObserver.screens.count > 1 {
                TabView(selection: $selectedTabScreen) {
                    ForEach(screenObserver.screens, id: \.self) { screen in
                        SingleScreenView(screen: screen, syncAllScreens: syncAllScreens, selectedTabScreen: $selectedTabScreen)
                            .id(UUID())
                            .tabItem {
                                Text(screen.localizedNameIfAvailableOrFallback)
                            }
                            .tag(screen)
                    }
                }
            } else if let screen = screenObserver.screens.first {
                SingleScreenView(screen: screen, syncAllScreens: syncAllScreens, selectedTabScreen: $selectedTabScreen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            
            if screenObserver.screens.count > 1 {
                Button("同步当前屏幕状态到所有屏幕") {
                    if let sourceScreen = selectedTabScreen,
                       let entry = SharedWallpaperWindowManager.shared.screenContent[sourceScreen] {
                        
                        if let fileType = UTType(filenameExtension: entry.url.pathExtension) {
                            if fileType.conforms(to: .movie) || fileType.conforms(to: .image) {
                                SharedWallpaperWindowManager.shared.syncAllWindows(sourceScreen: sourceScreen)
                            } else {
                                for screen in screenObserver.screens {
                                    SharedWallpaperWindowManager.shared.clear(for: screen)
                                }
                            }
                        } else {
                            for screen in screenObserver.screens {
                                SharedWallpaperWindowManager.shared.clear(for: screen)
                            }
                        }
                    } else {
                        for screen in screenObserver.screens {
                            SharedWallpaperWindowManager.shared.clear(for: screen)
                        }
                    }
                }
                .padding()
            }
            
            Toggle("切换 Dock/菜单栏 图标", isOn: Binding(
                get: { !isMenuBarOnly },
                set: { newValue in
                    isMenuBarOnly = !newValue
                    AppDelegate.shared?.setDockIconVisible(newValue)
                }
            ))
            Toggle("全局静音", isOn: $globalMute)
                .onChange(of: globalMute) { newValue in
                    desktop_videoApp.applyGlobalMute(newValue)
                }
            .padding(.bottom)
        }
        .frame(minWidth: 400, idealWidth: 480, maxWidth: .infinity, minHeight: 200, idealHeight: 325, maxHeight: .infinity)
        .padding()
        .frame(maxHeight: .infinity)
    }
}

struct SingleScreenView: View {
    let screen: NSScreen
    let syncAllScreens: Bool
    @Binding var selectedTabScreen: NSScreen?
    @ObservedObject private var appState = AppState.shared
    @State private var dummy: Bool = false  // 用于触发视图刷新
    @State private var volume: Float = 1.0
    @State private var stretchToFill: Bool = true
    @State private var muted: Bool = false
    @State private var previousVolume: Float = 1.0
    @State private var currentEntry: (type: SharedWallpaperWindowManager.ContentType, url: URL, stretch: Bool, volume: Float?)? = nil
//    let useMemoryCache: Bool = true
//    @AppStorage("globalMute") var globalMute: Bool = true

    var body: some View {
        return VStack(spacing: 12) {
            Text("「\(screen.localizedNameIfAvailableOrFallback)」")
                .font(.headline)

            if let entry = currentEntry {
                let filename: String = {
                    if let name = AppState.shared.lastMediaURL?.lastPathComponent.removingPercentEncoding {
                        return name
                    } else if let name = AppState.shared.lastMediaURL?.lastPathComponent {
                        return name
                    } else if let name = entry.url.lastPathComponent.removingPercentEncoding {
                        return name
                    } else {
                        return entry.url.lastPathComponent
                    }
                }()


                Text("正在播放：\(filename)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Button("更换视频或图片") {
                    openFilePicker()
                }

                if UTType(filenameExtension: entry.url.pathExtension)?.conforms(to: .movie) == true {
                    HStack(spacing: 12) {
                        Text("音量：\(Int(volume * 100))%")

                        Slider(value: $volume, in: 0...1)
                            .frame(width: 100)
                            .onChange(of: volume) { newVolume in
                                // If the user drags the slider above 0, un‑mute
                                if newVolume > 0, muted {
                                    muted = false
                                }

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    let playerVolume = SharedWallpaperWindowManager.shared.players[screen]?.volume ?? newVolume
                                    if abs(playerVolume - newVolume) > 0.01 {

                                        if newVolume > 0 && desktop_videoApp.shared.globalMute {
                                            desktop_videoApp.shared.globalMute = false
                                        }

                                        SharedWallpaperWindowManager.shared.updateVideoSettings(
                                            for: screen,
                                            stretch: stretchToFill,
                                            volume: newVolume
                                        )
                                        if syncAllScreens {
                                            SharedWallpaperWindowManager.shared.syncAllWindows(sourceScreen: screen)
                                        }
                                    }
                                }
                            }

                        Button {
                            if muted {
                                // restore previous volume
                                volume = previousVolume
                                muted = false
                            } else {
                                // remember current volume and mute
                                previousVolume = volume
                                volume = 0
                                muted = true
                            }
                        } label: {
                            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Toggle("拉伸填充屏幕", isOn: $stretchToFill)
                    .onChange(of: stretchToFill) { newValue in
                        if UTType(filenameExtension: entry.url.pathExtension)?.conforms(to: .movie) == true {
                            SharedWallpaperWindowManager.shared.updateVideoSettings(
                                for: screen,
                                stretch: newValue,
                                volume: volume
                            )
                            if syncAllScreens {
                                SharedWallpaperWindowManager.shared.syncAllWindows(sourceScreen: screen)
                            }
                        } else {
                            SharedWallpaperWindowManager.shared.updateImageStretch(for: screen, stretch: newValue)
                            if syncAllScreens {
                                SharedWallpaperWindowManager.shared.syncAllWindows(sourceScreen: screen)
                            }
                        }
                    }

                Button("关闭壁纸") {
                    SharedWallpaperWindowManager.shared.clear(for: screen)
                    AppState.shared.lastMediaURL = nil
                }
            } else {
                Button("选择视频或图片") {
                    openFilePicker()
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WallpaperContentDidChange"))) { _ in
            if let entry = SharedWallpaperWindowManager.shared.screenContent[screen] {
                if currentEntry?.url != entry.url ||
                    currentEntry?.volume != entry.volume ||
                    currentEntry?.stretch != entry.stretch {
                    self.currentEntry = entry
                    self.volume = entry.volume ?? 1.0
                    muted = desktop_videoApp.shared.globalMute || (self.volume == 0)
                    self.stretchToFill = entry.stretch
                    self.dummy.toggle()
                }
            } else {
                self.currentEntry = nil
            }

            if !NSScreen.screens.contains(screen) {
                selectedTabScreen = NSScreen.screens.first
            }
        }
        .onAppear {
            if let entry = SharedWallpaperWindowManager.shared.screenContent[screen] {
                self.currentEntry = entry
                self.volume = entry.volume ?? 1.0
                self.stretchToFill = entry.stretch
            }
        }
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            let fileType = UTType(filenameExtension: url.pathExtension)

            if fileType?.conforms(to: .movie) == true {
                appState.lastMediaURL = url
                SharedWallpaperWindowManager.shared.showVideo(
                    for: screen,
                    url: url,
                    stretch: stretchToFill,
                    volume: volume
                )
                if syncAllScreens {
                    SharedWallpaperWindowManager.shared.syncAllWindows(sourceScreen: screen)
                }
            } else if fileType?.conforms(to: .image) == true {
                appState.lastMediaURL = url
                SharedWallpaperWindowManager.shared.showImage(
                    for: screen,
                    url: url,
                    stretch: stretchToFill
                )
                if syncAllScreens {
                    SharedWallpaperWindowManager.shared.syncAllWindows(sourceScreen: screen)
                }
            }
        }
    }
}

fileprivate extension NSScreen {
    var localizedNameIfAvailableOrFallback: String {
        if #available(macOS 14.0, *) {
            return self.localizedName
        } else if let idx = NSScreen.screens.firstIndex(of: self) {
            return "屏幕 \(idx + 1)"
        } else {
            return "未知屏幕"
        }
    }
}

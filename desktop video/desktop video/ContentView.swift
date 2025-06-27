//
//  ContentView.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/20/25.
//

// 主页视图，使用 SharedWallpaperWindowManager 管理壁纸窗口

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Foundation

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var lastMediaURL: URL?
    @Published var lastVolume: Float = 1.0
    @Published var lastStretchToFill: Bool = true
    @Published var currentMediaURL: String?
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
                guard current != self.previousScreens else { return }

                let added = current.filter { !self.previousScreens.contains($0) }
                dlog("screen change detected added=\(added.map { $0.dv_localizedName })")
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
    // 全局静音设置
    @AppStorage("globalMute") private var globalMute: Bool = false
    @State private var syncAllScreens: Bool = false
    @State private var selectedTabScreen: NSScreen? = NSScreen.screens.first
    @StateObject private var screenObserver = ScreenObserver()
    @ObservedObject private var languageManager = LanguageManager.shared

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
                Button {
                    if let sourceScreen = selectedTabScreen,
                       let id = sourceScreen.dv_displayID,
                       let entry = SharedWallpaperWindowManager.shared.screenContent[id] {

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
                } label: {
                    Text(L("SyncAllScreens"))
                }
                .padding()
            }

            Toggle(L("SwitchIconMode"), isOn: Binding(
                get: { !isMenuBarOnly },
                set: { newValue in
                    isMenuBarOnly = !newValue
                    AppDelegate.shared?.setDockIconVisible(newValue)
                }
            ))
        }
        .padding(.bottom)
        .fixedSize(horizontal: true, vertical: true)
        .frame(minWidth: 400, idealWidth: 480, maxWidth: .infinity, minHeight: 200, idealHeight: 325, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            dlog("onDrop count=\(providers.count)")
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url = url else { return }

                let type = UTType(filenameExtension: url.pathExtension)
                dlog("drop URL=\(url.lastPathComponent) type=\(String(describing: type))")

                DispatchQueue.main.async {
                    guard let selected = selectedTabScreen ?? NSScreen.screens.first else { return }

                    if type?.conforms(to: .movie) == true {
                        AppState.shared.lastMediaURL = url
                        SharedWallpaperWindowManager.shared.showVideo(
                            for: selected,
                            url: url,
                            stretch: true,
                            volume: 1.0
                        )
                    } else if type?.conforms(to: .image) == true {
                        AppState.shared.lastMediaURL = url
                        SharedWallpaperWindowManager.shared.showImage(
                            for: selected,
                            url: url,
                            stretch: true
                        )
                    }
                }
            }
            return true
        }
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

    var body: some View {
        return VStack(spacing: 12) {
            // 保持屏幕名称原样显示
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

                Text("\(L("NowPlaying")) \(filename)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .onAppear {
                        if appState.currentMediaURL != filename {
                            dlog("filename appeared \(filename)")
                            appState.currentMediaURL = filename
                            AppDelegate.shared.startScreensaverTimer()
                        }
                    }

                Button {
                    openFilePicker()
                } label: {
                    Text(L("ChangeFile"))
                }
                Text(L("DropFileHere"))
                if UTType(filenameExtension: entry.url.pathExtension)?.conforms(to: .movie) == true {
                    HStack(spacing: 12) {
                        Text("\(L("Volume")): \(Int(volume * 100))%")

                        Slider(value: $volume, in: 0...1)
                            .frame(width: 100)
                            .onChange(of: volume) { newVolume in
                                // 记住最后一次非零音量
                                if newVolume > 0 { previousVolume = newVolume }

                                // 当滑块调至非零值时自动取消静音
                                if newVolume > 0, muted {
                                    muted = false
                                }

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    let playerVolume: Float = {
                                        if let id = screen.dv_displayID {
                                            return SharedWallpaperWindowManager.shared.players[id]?.volume ?? newVolume
                                        }
                                        return newVolume
                                    }()
                                    if abs(playerVolume - newVolume) > 0.01 {

                                        if newVolume > 0 && desktop_videoApp.shared!.globalMute {
                                            desktop_videoApp.shared!.globalMute = false
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
                                // 恢复之前的音量
                                volume = previousVolume
                                muted = false
                            } else {
                                // 保存当前音量并静音
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

                Toggle(L("StretchToFill"), isOn: $stretchToFill)
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

                Button {
                    SharedWallpaperWindowManager.shared.clear(for: screen)
                    AppState.shared.lastMediaURL = nil
                    AppState.shared.currentMediaURL = nil
                } label: {
                    Text(L("CloseWallpaper"))
                }
            } else {
                Button {
                    openFilePicker()
                } label: {
                    Text(L("SelectFile"))
                }
                Text(L("DropFileHere"))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .onReceive(NotificationCenter.default.publisher(for: .wallpaperContentDidChange)) { _ in
            if let id = screen.dv_displayID,
               let entry = SharedWallpaperWindowManager.shared.screenContent[id] {
                if currentEntry?.url != entry.url ||
                    currentEntry?.volume != entry.volume ||
                    currentEntry?.stretch != entry.stretch {
                    self.currentEntry = entry
                    self.volume = entry.volume ?? 1.0
                    if self.volume > 0 { previousVolume = self.volume }
                    muted = desktop_videoApp.shared!.globalMute || (self.volume == 0)
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
            dlog("SingleScreenView onAppear \(screen.dv_localizedName)")
            if let id = screen.dv_displayID,
               let entry = SharedWallpaperWindowManager.shared.screenContent[id] {
                self.currentEntry = entry
                self.volume = entry.volume ?? 1.0
                self.stretchToFill = entry.stretch
            }
        }
    }

    func openFilePicker() {
        dlog("openFilePicker for screen \(screen.dv_localizedName)")
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // 根据文件扩展名判断类型
            let fileType = UTType(filenameExtension: url.pathExtension)
            dlog("picker selected \(url.lastPathComponent) type=\(String(describing: fileType))")

            DispatchQueue.main.async {
                
                dlog("Clear screen on \(screen.dv_localizedName)")
                SharedWallpaperWindowManager.shared.clear(for: screen)
                
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
}

fileprivate extension NSScreen {
    var localizedNameIfAvailableOrFallback: String {
        if #available(macOS 14.0, *) {
            return self.localizedName
        } else if let idx = NSScreen.screens.firstIndex(of: self) {
            // 无本地化名称时的编号名称
            return String(format: NSLocalizedString(L("Screen %d"), comment: ""), idx + 1)
        } else {
            // 未知屏幕的回退名称
            return NSLocalizedString(L("UnknownScreen"), comment: "")
        }
    }
}

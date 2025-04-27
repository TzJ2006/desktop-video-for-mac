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

struct ContentView: View {
    @ObservedObject private var appState = AppState.shared
    @AppStorage("isMenuBarOnly") var isMenuBarOnly: Bool = false
    @State private var syncAllScreens: Bool = false

    var body: some View {
        VStack {
            Spacer()
            if NSScreen.screens.count > 1 {
                TabView {
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        SingleScreenView(screen: screen, syncAllScreens: syncAllScreens)
                            .tabItem {
                                Text(screen.localizedNameIfAvailableOrFallback)
                            }
                    }
                }
                .frame(minHeight: 250)
            } else if let screen = SharedWallpaperWindowManager.shared.selectedScreen {
                SingleScreenView(screen: screen, syncAllScreens: syncAllScreens)
            }
//            Spacer()
            
            Button("同步到所有屏幕") {
                if let sourceScreen = SharedWallpaperWindowManager.shared.selectedScreen,
                   let entry = SharedWallpaperWindowManager.shared.screenContent[sourceScreen],
                   UTType(filenameExtension: entry.url.pathExtension)?.conforms(to: .movie) == true {
                    SharedWallpaperWindowManager.shared.syncAllWindows(sourceScreen: sourceScreen)
                } else {
                    for screen in NSScreen.screens {
                        SharedWallpaperWindowManager.shared.clear(for: screen)
                    }
                }
            }
            .padding()
            
            Toggle("显示 Dock 图标", isOn: Binding(
                get: { !isMenuBarOnly },
                set: { newValue in
                    isMenuBarOnly = !newValue
                    AppDelegate.shared?.setDockIconVisible(newValue)
                }
            ))
            .padding(.bottom)
        }
        .frame(minWidth: 400, idealWidth: 480, maxWidth: .infinity, minHeight: 200, idealHeight: 325, maxHeight: .infinity)
        .padding()
    }
}

struct SingleScreenView: View {
    let screen: NSScreen
    let syncAllScreens: Bool
    @ObservedObject private var appState = AppState.shared
    @State private var dummy: Bool = false  // 用于触发视图刷新
    @State private var volume: Float = 1.0
    @State private var stretchToFill: Bool = true

    var body: some View {
        let entry = SharedWallpaperWindowManager.shared.screenContent[screen]

        return VStack(spacing: 12) {
            Text("「\(screen.localizedNameIfAvailableOrFallback)」")
                .font(.headline)

            if let entry {
                let filename = entry.url.lastPathComponent.removingPercentEncoding ?? entry.url.lastPathComponent

                Text("正在播放：\(filename)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .onAppear {
                        let currentVolume = entry.volume ?? 1.0
                        if self.volume != currentVolume {
                            self.volume = currentVolume
                        }
                        if currentVolume > 0 {
                            AppDelegate.shared.globalMute = false
                        }

                        if self.stretchToFill != entry.stretch {
                            self.stretchToFill = entry.stretch
                        }
                    }

                Button("更换视频或图片") {
                    openFilePicker()
                }

                if UTType(filenameExtension: entry.url.pathExtension)?.conforms(to: .movie) == true {
                    Text("音量：\(Int(volume * 100))%")
                    Slider(value: $volume, in: 0...1, step: 0.01)
                        .frame(width: 200)
                        .onChange(of: volume) { newValue in
                            SharedWallpaperWindowManager.shared.updateVideoSettings(
                                for: screen,
                                stretch: stretchToFill,
                                volume: newValue
                            )
                            if syncAllScreens {
                                SharedWallpaperWindowManager.shared.syncAllWindows(sourceScreen: screen)
                            }
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
                    dummy.toggle()
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
            dummy.toggle()
        }
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.lastMediaURL = url

            let fileType = UTType(filenameExtension: url.pathExtension)
            if fileType?.conforms(to: .movie) == true {
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

//func showRestartAlert() {
//    let shouldSuppress = UserDefaults.standard.bool(forKey: "suppressRestartAlert")
//    if shouldSuppress { return }
//
//    let alert = NSAlert()
//    alert.messageText = "需要重新启动应用"
//    alert.informativeText = "更改是否显示 Dock 图标的设置将在下次启动时生效。请重新打开 App。"
//    alert.addButton(withTitle: "不再显示")
//    alert.addButton(withTitle: "好的")
//    
//
//    let response = alert.runModal()
//    if response == .alertSecondButtonReturn {
//        UserDefaults.standard.set(true, forKey: "suppressRestartAlert")
//    }
//}

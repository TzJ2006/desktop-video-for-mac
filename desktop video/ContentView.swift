//
//  ContentView.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/20/25.
//

// ContentView.swift (使用 SharedWallpaperWindowManager)

import SwiftUI
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
    @State private var selectedScreenIndex: Int = 0
    @State private var playbackInfoMap: [NSScreen: String] = [:]
    @AppStorage("isMenuBarOnly") var isMenuBarOnly: Bool = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                if NSScreen.screens.count > 1 {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        VStack(spacing: 8) {
                            Text("「\(screen.localizedNameIfAvailableOrFallback)」")
                                .font(.headline)

                            if let entry = SharedWallpaperWindowManager.shared.screenContent[screen] {
                                let filename = entry.url.lastPathComponent.removingPercentEncoding ?? entry.url.lastPathComponent
                                Text("正在播放：\(filename)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)

                                Button("更换视频或图片") {
                                    selectedScreenIndex = index
                                    openFilePicker()
                                }

                                if UTType(filenameExtension: entry.url.pathExtension)?.conforms(to: .movie) == true {
                                    Text("音量：\(Int(appState.lastVolume * 100))%")
                                    Slider(value: $appState.lastVolume, in: 0...1, step: 0.01)
                                        .frame(width: 200)
                                        .onChange(of: appState.lastVolume) { newValue in
                                            SharedWallpaperWindowManager.shared.updateVideoSettings(
                                                stretch: appState.lastStretchToFill,
                                                volume: newValue
                                            )
                                        }
                                }

                                Toggle("拉伸填充屏幕", isOn: $appState.lastStretchToFill)
                                    .onChange(of: appState.lastStretchToFill) { newValue in
                                        if UTType(filenameExtension: entry.url.pathExtension)?.conforms(to: .movie) == true {
                                            SharedWallpaperWindowManager.shared.updateVideoSettings(
                                                stretch: newValue,
                                                volume: appState.lastVolume
                                            )
                                        } else {
                                            SharedWallpaperWindowManager.shared.updateImageStretch(stretch: newValue)
                                        }
                                    }

                                Button("关闭壁纸") {
                                    SharedWallpaperWindowManager.shared.selectedScreenIndex = index
                                    SharedWallpaperWindowManager.shared.clear()
                                    playbackInfoMap.removeValue(forKey: screen)
                                }
                            } else {
                                Button("选择视频或图片") {
                                    selectedScreenIndex = index
                                    openFilePicker()
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }
                } else {
                    // Single screen fallback
                    if let screen = SharedWallpaperWindowManager.shared.selectedScreen {
                        if let entry = SharedWallpaperWindowManager.shared.screenContent[screen] {
                            let filename = entry.url.lastPathComponent.removingPercentEncoding ?? entry.url.lastPathComponent
                            Text("正在「\(screen.localizedNameIfAvailableOrFallback)」上播放：\(filename)")
                                .font(.subheadline)
                                .foregroundColor(.gray)

                            Button("更换视频或图片") {
                                openFilePicker()
                            }
                        } else {
                            Button("选择视频或图片") {
                                openFilePicker()
                            }
                        }

                        if appState.lastMediaURL != nil {
                            Button("关闭壁纸") {
                                SharedWallpaperWindowManager.shared.clear()
                                appState.lastMediaURL = nil
                                playbackInfoMap.removeValue(forKey: screen)
                            }

                            if let url = appState.lastMediaURL,
                               UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true {
                                Text("音量：\(Int(appState.lastVolume * 100))%")
                                Slider(value: $appState.lastVolume, in: 0...1, step: 0.01)
                                    .frame(width: 200)
                                    .onChange(of: appState.lastVolume) { newValue in
                                        SharedWallpaperWindowManager.shared.updateVideoSettings(
                                            stretch: appState.lastStretchToFill,
                                            volume: newValue
                                        )
                                    }
                            }

                            Toggle("拉伸填充屏幕", isOn: $appState.lastStretchToFill)
                                .onChange(of: appState.lastStretchToFill) { newValue in
                                    if let url = appState.lastMediaURL {
                                        let fileType = UTType(filenameExtension: url.pathExtension)
                                        if fileType?.conforms(to: .movie) == true {
                                            SharedWallpaperWindowManager.shared.updateVideoSettings(
                                                stretch: newValue,
                                                volume: appState.lastVolume
                                            )
                                        } else if fileType?.conforms(to: .image) == true {
                                            SharedWallpaperWindowManager.shared.updateImageStretch(stretch: newValue)
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            Spacer()
            
            Toggle("仅显示在菜单栏（隐藏 Dock）", isOn: $isMenuBarOnly)
                .onChange(of: isMenuBarOnly) { value in
                    UserDefaults.standard.set(value, forKey: "isMenuBarOnly")
                    UserDefaults.standard.set(!value, forKey: "showDockIcon")
                    UserDefaults.standard.set(value, forKey: "showMenuBarIcon")

                    if value {
                        NSApp.setActivationPolicy(.accessory)
                        StatusBarController.shared.updateStatusItemVisibility()
                        NSApp.activate(ignoringOtherApps: true)
                        AppDelegate.shared.openMainWindow()
                    } else {
                        NSApp.setActivationPolicy(.regular)
                        StatusBarController.shared.updateStatusItemVisibility()
                        AppDelegate.shared.openMainWindow()
                    }
                }
                .padding(.bottom)
        }
        .frame(minWidth: 400, idealWidth: 480, maxWidth: .infinity, minHeight: 200, idealHeight: 300, maxHeight: .infinity)
        .padding()
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
                    url: url,
                    stretch: appState.lastStretchToFill,
                    volume: appState.lastVolume
                )
            } else if fileType?.conforms(to: .image) == true {
                SharedWallpaperWindowManager.shared.showImage(
                    url: url,
                    stretch: appState.lastStretchToFill
                )
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

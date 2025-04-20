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

    var body: some View {
        VStack(spacing: 16) {
            if let screen = SharedWallpaperWindowManager.shared.selectedScreen {
                if SharedWallpaperWindowManager.shared.screenContent[screen] != nil {
                    if let info = playbackInfoMap[screen] {
                        Text(info)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    Button("选择视频或图片") {
                        openFilePicker()
                    }
                }
            }

            if NSScreen.screens.count > 1 {
                Picker("选择屏幕", selection: $selectedScreenIndex) {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        if #available(macOS 14.0, *) {
                            Text("「\(screen.localizedName)」").tag(index)
                        } else {
                            Text("「屏幕 \(index + 1)」").tag(index)
                        }
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedScreenIndex) { newIndex in
                    SharedWallpaperWindowManager.shared.selectedScreenIndex = newIndex
                    let selectedScreen = NSScreen.screens[newIndex]
                    SharedWallpaperWindowManager.shared.restoreContent(for: selectedScreen)
                }
            }

            if appState.lastMediaURL != nil {
                Button("关闭壁纸") {
                    SharedWallpaperWindowManager.shared.clear()
                    appState.lastMediaURL = nil
                }
                
                if let url = appState.lastMediaURL {
                    let fileType = UTType(filenameExtension: url.pathExtension)
                    if fileType?.conforms(to: .movie) == true {
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
        .padding()
//        .frame(width: 480, height: 300)
        .frame(minWidth: 400, idealWidth: 480, maxWidth: .infinity, minHeight: 200, idealHeight: 300, maxHeight: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            SharedWallpaperWindowManager.shared.selectedScreenIndex = selectedScreenIndex
            if let url = appState.lastMediaURL {
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
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            var updated: [NSScreen: String] = [:]
            for screen in NSScreen.screens {
                if let entry = SharedWallpaperWindowManager.shared.screenContent[screen] {
                    if #available(macOS 14.0, *) {
                        updated[screen] = "正在「\(screen.localizedName)」上播放：\(entry.url.absoluteString)"
                    } else if let idx = NSScreen.screens.firstIndex(of: screen) {
                        updated[screen] = "正在「屏幕 \(idx + 1)」上播放：\(entry.url.absoluteString)"
                    }
                }
            }
            playbackInfoMap = updated
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

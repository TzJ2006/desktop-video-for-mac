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

    var body: some View {
        VStack(spacing: 16) {
            Button(appState.lastMediaURL == nil ? "选择视频或图片" : "更换视频或图片") {
                openFilePicker()
            }

            if appState.lastMediaURL != nil {
                Button("关闭壁纸") {
                    SharedWallpaperWindowManager.shared.clear()
                    appState.lastMediaURL = nil
                }

                Text("音量：\(Int(appState.lastVolume * 100))%")
                Slider(value: $appState.lastVolume, in: 0...1, step: 0.01)
                    .frame(width: 200)
                    .onChange(of: appState.lastVolume) { newValue in
                        SharedWallpaperWindowManager.shared.updateVideoSettings(
                            stretch: appState.lastStretchToFill,
                            volume: newValue
                        )
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
        .frame(width: 480, height: 300)
        .onAppear {
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

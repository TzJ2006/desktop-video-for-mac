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
    @AppStorage("isMenuBarOnly") var isMenuBarOnly: Bool = false

    var body: some View {
        VStack {
            Spacer()
            if NSScreen.screens.count > 1 {
                TabView {
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        SingleScreenView(screen: screen)
                            .tabItem {
                                Text(screen.localizedNameIfAvailableOrFallback)
                            }
                    }
                }
                .frame(minHeight: 300)
            } else if let screen = SharedWallpaperWindowManager.shared.selectedScreen {
                SingleScreenView(screen: screen)
            }
            Spacer()
            
            Toggle("仅显示在菜单栏（隐藏 Dock）", isOn: $isMenuBarOnly)
                .onChange(of: isMenuBarOnly) { value in
                    UserDefaults.standard.set(value, forKey: "isMenuBarOnly")
                    UserDefaults.standard.set(!value, forKey: "showDockIcon")
                    UserDefaults.standard.set(value, forKey: "showMenuBarIcon")
                    showRestartAlert()
                }
                .padding(.bottom)
        }
        .frame(minWidth: 400, idealWidth: 480, maxWidth: .infinity, minHeight: 200, idealHeight: 300, maxHeight: .infinity)
        .padding()
    }
}

struct SingleScreenView: View {
    let screen: NSScreen
    @ObservedObject private var appState = AppState.shared
    @State private var dummy: Bool = false  // 用于触发视图刷新

    var body: some View {
        VStack(spacing: 12) {
            Text("「\(screen.localizedNameIfAvailableOrFallback)」")
                .font(.headline)

            if let entry = SharedWallpaperWindowManager.shared.screenContent[screen] {
                let filename = entry.url.lastPathComponent.removingPercentEncoding ?? entry.url.lastPathComponent
                Text("正在播放：\(filename)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Button("更换视频或图片") {
                    openFilePicker()
                }

                if UTType(filenameExtension: entry.url.pathExtension)?.conforms(to: .movie) == true {
                    Text("音量：\(Int(appState.lastVolume * 100))%")
                    Slider(value: $appState.lastVolume, in: 0...1, step: 0.01)
                        .frame(width: 200)
                        .onChange(of: appState.lastVolume) { newValue in
                            SharedWallpaperWindowManager.shared.updateVideoSettings(
                                for: screen,
                                stretch: appState.lastStretchToFill,
                                volume: newValue
                            )
                        }
                }

                Toggle("拉伸填充屏幕", isOn: $appState.lastStretchToFill)
                    .onChange(of: appState.lastStretchToFill) { newValue in
                        if UTType(filenameExtension: entry.url.pathExtension)?.conforms(to: .movie) == true {
                            SharedWallpaperWindowManager.shared.updateVideoSettings(
                                for: screen,
                                stretch: newValue,
                                volume: appState.lastVolume
                            )
                        } else {
                            SharedWallpaperWindowManager.shared.updateImageStretch(for: screen, stretch: newValue)
                        }
                    }

                Button("关闭壁纸") {
                    SharedWallpaperWindowManager.shared.clear(for: screen)
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
                    stretch: appState.lastStretchToFill,
                    volume: appState.lastVolume
                )
            } else if fileType?.conforms(to: .image) == true {
                SharedWallpaperWindowManager.shared.showImage(
                    for: screen,
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

func showRestartAlert() {
    let alert = NSAlert()
    alert.messageText = "需要重新启动应用"
    alert.informativeText = "更改是否显示 Dock 图标的设置将在下次启动时生效。请重新打开 App。"
    alert.addButton(withTitle: "好的")
    alert.runModal()
}

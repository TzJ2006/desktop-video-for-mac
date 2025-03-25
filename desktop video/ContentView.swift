//
//  ContentView.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/20/25.
//

import UniformTypeIdentifiers
import SwiftUI
import AVKit

class MyWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = MyWindowDelegate()
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }
}

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var isVideoStretched: Bool = true
    @State private var volume: Float = 1.0 // 音量范围 0.0 ~ 1.0

    var body: some View {
        VStack {
            Button(videoURL == nil ? "点我选择视频" : "点我更换视频") {
                openFilePicker()
            }
            .padding()
            
            
            if videoURL != nil {
                Button("点我关闭壁纸") {
                    VideoWallpaperManager.shared.stopVideoWallpaper()
                    videoURL = nil
                }
                .padding()
            }
            
            
            Toggle("拉伸视频以填充屏幕", isOn: $isVideoStretched)
                .padding()
                .onChange(of: isVideoStretched) { newValue in
                    if let url = videoURL {
                        VideoWallpaperManager.shared.setVideoWallpaper(url: url, stretchToFill: newValue)
                    }
                }
            

            if let url = videoURL {
                Text("已选择: \(url.lastPathComponent)")
            }
            
            if videoURL != nil {
                VStack {
                    Text("音量：\(Int(volume * 100))%")
                    Slider(value: $volume, in: 0.0...1.0, step: 0.01)
                        .frame(width: 200)
                        .onChange(of: volume) { newValue in
                            VideoWallpaperManager.shared.setVolume(newValue)
                        }
                }
                .padding()
            }
        }
        .background(WindowAccessor { window in
            if let window = window {
                window.delegate = MyWindowDelegate.shared
            }
        })
        .frame(width: 300, height: 200)
        
        
        
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.movie]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            if let selectedURL = panel.urls.first {
                videoURL = selectedURL
                VideoWallpaperManager.shared.setVideoWallpaper(url: selectedURL, stretchToFill: isVideoStretched)
            }
        }
    }
}

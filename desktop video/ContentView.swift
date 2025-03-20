//
//  ContentView.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/20/25.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var isVideoStretched: Bool = true

    var body: some View {
        VStack {
            Button(videoURL == nil ? "点我选择视频/图片" : "点我更换视频/图片") {
                openFilePicker()
            }
            .padding()
            
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
        }
        .frame(width: 300, height: 200)
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.movie, UTType.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            if let selectedURL = panel.urls.first {
                videoURL = selectedURL
                VideoWallpaperManager.shared.setVideoWallpaper(url: selectedURL, stretchToFill: isVideoStretched)
            }
        }
    }
}

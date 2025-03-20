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

    var body: some View {
        VStack {
            Button("选择视频") {
                openFilePicker()
            }
            .padding()

            if let url = videoURL {
                Text("已选择: \(url.lastPathComponent)")
            }
        }
        .frame(width: 300, height: 200)
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.movie]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            if let selectedURL = panel.urls.first {
                videoURL = selectedURL
                VideoWallpaperManager.shared.setVideoWallpaper(url: selectedURL)
            }
        }
    }
}

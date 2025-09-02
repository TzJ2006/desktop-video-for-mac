import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Controls for a single screen's wallpaper.
struct SingleScreenView: View {
    let screen: NSScreen
    @State private var volume: Double = 100
    @State private var stretchToFill: Bool = true
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Button("Choose Video…", action: chooseMedia)
                Button("Clear", action: clear)
                Button("Play", action: play)
                Button("Pause", action: pause)
            }
            SliderInputRow(title: "Volume", value: $volume, range: 0...100)
                .onChange(of: volume) { newValue in
                    let clamped = min(max(newValue, 0), 100)
                    volume = clamped
                    let sid = screen.dv_displayUUID
                    SharedWallpaperWindowManager.shared.players[sid]?.volume = Float(clamped / 100.0)
                    dlog("set volume \(clamped) for \(screen.dv_localizedName)")
                }
            ToggleRow(title: "Stretch to fill", value: $stretchToFill)
                .onChange(of: stretchToFill) { newValue in
                    updateStretch(newValue)
                }
        }
        .onAppear(perform: syncInitialState)
    }

    // 打开媒体选择面板并设置壁纸
    private func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            dlog("chooseMedia url=\(url.lastPathComponent)")
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                if type.conforms(to: .image) {
                    SharedWallpaperWindowManager.shared.showImage(for: screen, url: url, stretch: stretchToFill)
                } else {
                    SharedWallpaperWindowManager.shared.showVideo(for: screen, url: url, stretch: stretchToFill, volume: Float(volume / 100))
                }
            }
        }
    }
    
    // 清除当前屏幕的壁纸
    private func clear() {
        dlog("clear wallpaper for \(screen.dv_localizedName)")
        SharedWallpaperWindowManager.shared.clear(for: screen)
    }
    
    // 播放当前屏幕的壁纸
    private func play() {
        let sid = screen.dv_displayUUID
        dlog("play wallpaper for \(screen.dv_localizedName)")
        SharedWallpaperWindowManager.shared.players[sid]?.play()
    }
    
    // 暂停当前屏幕的壁纸
    private func pause() {
        let sid = screen.dv_displayUUID
        dlog("pause wallpaper for \(screen.dv_localizedName)")
        SharedWallpaperWindowManager.shared.players[sid]?.pause()
    }

    private func updateStretch(_ stretch: Bool) {
        let sid = screen.dv_displayUUID
        if let entry = SharedWallpaperWindowManager.shared.screenContent[sid] {
            switch entry.type {
            case .image:
                SharedWallpaperWindowManager.shared.showImage(for: screen, url: entry.url, stretch: stretch)
            case .video:
                SharedWallpaperWindowManager.shared.showVideo(for: screen, url: entry.url, stretch: stretch, volume: Float(volume / 100))
            }
        }
        dlog("update stretch \(stretch) for \(screen.dv_localizedName)")
    }

    private func syncInitialState() {
        let sid = screen.dv_displayUUID
        if let player = SharedWallpaperWindowManager.shared.players[sid] {
            volume = Double(player.volume * 100)
        }
        if let entry = SharedWallpaperWindowManager.shared.screenContent[sid] {
            stretchToFill = entry.stretch
        }
        dlog("sync controls for \(screen.dv_localizedName)")
    }
}

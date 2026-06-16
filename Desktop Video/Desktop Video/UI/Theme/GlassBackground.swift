//
//  GlassBackground.swift
//  Desktop Video
//
//  整窗「liquid glass」的底层模糊。把一个 behind-window 混合模式的
//  NSVisualEffectView 铺在主窗口最底层，配合窗口本身半透明
//  （isOpaque=false / backgroundColor=.clear，见 ContentView 的 MainWindowBridge），
//  即可模糊透出后面的桌面与壁纸——近似 macOS 原生的玻璃窗口。
//  （真正的系统级 Liquid Glass API 需 macOS 26，此处用材质模拟同等观感。）
//

import SwiftUI
import AppKit

/// 整窗底层模糊：behind-window 混合，透出桌面/壁纸。
struct WindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

extension View {
    /// 在视图最底层铺一层整窗模糊（透出桌面）。
    func glassWindowBackground(_ material: NSVisualEffectView.Material = .underWindowBackground) -> some View {
        background(WindowBlur(material: material).ignoresSafeArea())
    }
}

extension NSWindow {
    /// 应用整窗 liquid glass 外观：半透明 + 透明标题栏，使底层 WindowBlur 透出桌面。
    /// 需在窗口 `makeKeyAndOrderFront` 之前（或视图刚加入窗口时）同步调用，避免首帧闪现不透明背景。
    func applyGlassWindowStyle() {
        isOpaque = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }
}

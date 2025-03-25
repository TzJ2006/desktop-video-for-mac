//
//  Untitled.swift
//  desktop video
//
//  Created by 汤子嘉 on 3/22/25.
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let nsView = NSView()
        DispatchQueue.main.async {
            onWindow(nsView.window)
        }
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}

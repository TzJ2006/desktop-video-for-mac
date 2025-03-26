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
        let view = NSView()
        DispatchQueue.main.async {
            self.onWindow(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

//
//  WindowChrome.swift
//  VisualSimple
//

import AppKit
import SwiftUI

/// Strips the window down to its content: transparent title bar, traffic lights
/// hidden unless the user asks for them, window draggable by its background.
struct WindowChrome: NSViewRepresentable {
    let showsWindowControls: Bool
    /// Reports the window's corner radius so the border can follow it.
    let onCornerRadius: (CGFloat) -> Void

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.showsWindowControls = showsWindowControls
        view.onCornerRadius = onCornerRadius
        return view
    }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.showsWindowControls = showsWindowControls
        view.onCornerRadius = onCornerRadius
        view.apply()
    }

    final class ChromeView: NSView {
        var showsWindowControls = false
        var onCornerRadius: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            // Dragging is offered by the tab bar only: moving by background would steal
            // mouse-downs from non-opaque views such as the image canvas.
            window.isMovableByWindowBackground = false
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = !showsWindowControls
            }
            let radius = Self.cornerRadius(of: window)
            DispatchQueue.main.async { [onCornerRadius] in onCornerRadius?(radius) }
        }

        /// AppKit keeps the radius private; 6 pt is what macOS 26 reports for this window style.
        private static func cornerRadius(of window: NSWindow) -> CGFloat {
            let selector = NSSelectorFromString("_cornerRadius")
            guard window.responds(to: selector), let method = class_getInstanceMethod(type(of: window), selector) else { return 6 }
            typealias Getter = @convention(c) (AnyObject, Selector) -> CGFloat
            let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
            let value = getter(window, selector)
            return value > 0 ? value : 6
        }
    }
}

/// One-point chrome line hugging the window edge: silver by day, gold by night.
struct WindowBorder: View {
    let isDark: Bool
    let cornerRadius: CGFloat

    private var colors: [Color] {
        if isDark {
            return [Color(hex: "f3dc8e"), Color(hex: "c9a227"), Color(hex: "8c6a0c"), Color(hex: "e3c567")]
        }
        return [Color(hex: "fafafa"), Color(hex: "bdbdbd"), Color(hex: "8f8f8f"), Color(hex: "e6e6e6")]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
            .strokeBorder(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}

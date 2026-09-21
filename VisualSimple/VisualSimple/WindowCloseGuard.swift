//
//  WindowCloseGuard.swift
//  VisualSimple
//

import AppKit
import SwiftUI

/// Asks about unsaved changes when the window's close button is used.
/// SwiftUI owns the window delegate, so a forwarding proxy is slipped in front of it.
struct WindowCloseGuard: NSViewRepresentable {
    let shouldClose: () -> Bool

    func makeNSView(context: Context) -> GuardView {
        let view = GuardView()
        view.shouldClose = shouldClose
        return view
    }

    func updateNSView(_ view: GuardView, context: Context) {
        view.shouldClose = shouldClose
    }

    final class GuardView: NSView {
        var shouldClose: (() -> Bool)?
        private var proxy: WindowDelegateProxy?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !(window.delegate is WindowDelegateProxy) else { return }
            let proxy = WindowDelegateProxy(original: window.delegate) { [weak self] in
                self?.shouldClose?() ?? true
            }
            self.proxy = proxy
            window.delegate = proxy
        }
    }
}

/// Answers `windowShouldClose` itself and forwards everything else to SwiftUI's delegate.
final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    private weak var original: NSWindowDelegate?
    private let shouldClose: () -> Bool

    init(original: NSWindowDelegate?, shouldClose: @escaping () -> Bool) {
        self.original = original
        self.shouldClose = shouldClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose() else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original
    }
}

//
//  EditorFocus.swift
//  VisualSimple
//

import AppKit

/// Remembers the selected tab's editor so keyboard focus can be handed back to it
/// after SwiftUI removes another tab's view (AppKit then drops focus on the window).
enum EditorFocus {
    static weak var active: NSView?

    /// Deferred, and looked up at that moment only: a view leaving a window that is
    /// being torn down must not keep that window alive or touch it afterwards.
    static func reclaim() {
        DispatchQueue.main.async {
            guard let active, let window = active.window,
                  window.firstResponder === window else { return }
            window.makeFirstResponder(active)
        }
    }
}

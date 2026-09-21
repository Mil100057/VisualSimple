//
//  AppDelegate.swift
//  VisualSimple
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openFilesHandler: (([URL]) -> Void)?
    /// Returns false to keep the app running (unsaved changes, user cancelled).
    var shouldTerminateHandler: (() -> Bool)?

    /// The window is the app: closing it with the red button quits, after the usual save prompt.
    /// The one exception is a window hidden into the menu bar — there the app is meant to stay
    /// alive with its tabs, and AppKit sends this the moment the last window leaves the screen.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MainActor.assumeIsolated { MenuBarController.shared.isHidden }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (shouldTerminateHandler?() ?? true) ? .terminateNow : .terminateCancel
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { MenuBarController.shared.restore() }
        openFilesHandler?(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        MainActor.assumeIsolated { MenuBarController.shared.restore() }
        openFilesHandler?([URL(fileURLWithPath: filename)])
        return true
    }

    /// Clicking the Dock icon of an app whose window is hidden in the menu bar brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { MenuBarController.shared.restore() }
        return true
    }
}

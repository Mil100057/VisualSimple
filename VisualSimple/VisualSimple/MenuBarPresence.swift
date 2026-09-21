//
//  MenuBarPresence.swift
//  VisualSimple
//

import AppKit
import SwiftUI

/// Hides the window into the macOS menu bar instead of the Dock.
///
/// While hidden the app keeps running with all its tabs, its unsaved work and its undo stacks;
/// only the window is ordered out and the activation policy drops to `.accessory`, which also
/// takes the Dock icon away. The status item is created on the way in and removed on the way out:
/// nothing sits in the menu bar while the window is on screen.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private weak var hiddenWindow: NSWindow?

    /// True from the moment the window leaves the screen until it is back on it. `AppDelegate`
    /// reads it to refuse the automatic "last window closed, so quit" — AppKit sends that as soon
    /// as no window is on screen, which is precisely the state this feature lives in.
    private(set) var isHidden = false

    /// The window the app is built around: the first on-screen one that can take the keyboard.
    private var mainWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first { $0.canBecomeKey && $0.isVisible }
    }

    func toggle() {
        isHidden ? restore() : hide()
    }

    func hide() {
        guard !isHidden, let window = mainWindow else { return }
        hiddenWindow = window
        isHidden = true

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "chevron.left.forwardslash.chevron.right",
                accessibilityDescription: String(localized: "VisualSimple")
            )
            button.image?.isTemplate = true
            button.toolTip = String(localized: "Show VisualSimple")
            button.target = self
            button.action = #selector(statusItemClicked)
            // Left click restores straight away; right click opens the menu below.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func restore() {
        guard isHidden else { return }

        // Order matters. The window goes back on screen FIRST, and `isHidden` is only cleared once
        // it is there: clearing it while no window was on screen let AppKit quit the app between
        // the two steps.
        NSApp.setActivationPolicy(.regular)
        let window = hiddenWindow ?? NSApp.windows.first { $0.canBecomeKey }
        window?.makeKeyAndOrderFront(nil)

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        hiddenWindow = nil
        isHidden = false

        // The policy change needs one turn of the run loop before the app can come to the front.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            restore()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            restore()
        }
    }

    private func showMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()

        let show = NSMenuItem(title: String(localized: "Show VisualSimple"), action: #selector(menuRestore), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: String(localized: "Quit VisualSimple"), action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        // Attaching the menu makes the button open it on the NEXT click too, so it is detached
        // again as soon as it closes; otherwise a left click would stop restoring the window.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func menuRestore() {
        restore()
    }

    @objc private func menuQuit() {
        // Bring the window back first: quitting may raise a save alert per modified tab, and an
        // alert with no window behind it would leave the user with no idea what it is about.
        restore()
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}

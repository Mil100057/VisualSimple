//
//  AppTheme.swift
//  VisualSimple
//

import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var isDark: Bool { self == .dark }
}

enum AppAppearance {
    static func nsAppearance(for mode: AppearanceMode) -> NSAppearance? {
        mode.isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
    }

    static func apply(mode: AppearanceMode) {
        DispatchQueue.main.async {
            let app = NSApplication.shared
            guard app.isRunning else { return }

            let appearance = nsAppearance(for: mode)
            app.appearance = appearance
            for window in app.windows where window.canBecomeKey {
                window.appearance = appearance
            }
        }
    }
}

@Observable
final class AppearanceController {
    var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "appearanceMode")
            AppAppearance.apply(mode: mode)
        }
    }

    /// Traffic lights are hidden by default; the View menu can bring them back.
    var showsWindowControls: Bool {
        didSet { UserDefaults.standard.set(showsWindowControls, forKey: "showsWindowControls") }
    }

    /// Read from the window once it exists; used by the chrome border.
    var windowCornerRadius: CGFloat = 6

    var isDark: Bool { mode.isDark }

    var theme: EditorTheme {
        EditorTheme.obsidian(isDark: isDark)
    }

    init() {
        showsWindowControls = UserDefaults.standard.bool(forKey: "showsWindowControls")
        let stored = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.dark.rawValue
        if stored == "system" {
            mode = .dark
        } else {
            mode = AppearanceMode(rawValue: stored) ?? .dark
        }
    }
}

struct EditorTheme {
    let backgroundPrimary: Color
    let backgroundSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let divider: Color

    static func obsidian(isDark: Bool) -> EditorTheme {
        if isDark {
            return EditorTheme(
                backgroundPrimary: Color(hex: "1e1e1e"),
                backgroundSecondary: Color(hex: "161616"),
                textPrimary: Color(hex: "dadada"),
                textSecondary: Color(hex: "dadada").opacity(0.6),
                accent: Color(hex: "a882ff"),
                divider: Color(hex: "dadada").opacity(0.12)
            )
        }
        return EditorTheme(
            backgroundPrimary: Color(hex: "ffffff"),
            backgroundSecondary: Color(hex: "fafafa"),
            textPrimary: Color(hex: "222222"),
            textSecondary: Color(hex: "222222").opacity(0.55),
            accent: Color(hex: "7852ee"),
            divider: Color(hex: "222222").opacity(0.1)
        )
    }
}

struct WindowAppearanceModifier: ViewModifier {
    let mode: AppearanceMode

    func body(content: Content) -> some View {
        content
            .onAppear { AppAppearance.apply(mode: mode) }
            .onChange(of: mode) { AppAppearance.apply(mode: mode) }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension View {
    func windowAppearance(_ mode: AppearanceMode) -> some View {
        modifier(WindowAppearanceModifier(mode: mode))
    }
}

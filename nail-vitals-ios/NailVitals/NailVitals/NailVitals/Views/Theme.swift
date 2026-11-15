//
//  Theme.swift
//  NailVitals
//
//  Shared colors from the capture design spec (guided_capture_demo.html):
//  cyan while searching, amber while adjusting, green when aligned. The
//  same green / warm amber / coral mark result states: typical, close to
//  a cut-off (or "measure again"), above a cut-off (or "worth
//  discussing"). Text uses the system font, SF Pro (SF Pro Display at
//  20 pt and up).
//
//  The camera uses cyan / amber / green. The home side (tabs) stays
//  neutral and flat -- white cards on light gray, or dark gray cards on
//  black -- and uses color only for result states.
//
//  Three looks, picked on Home (AppAppearance): Automatic (follows the
//  phone, the default), White and Dark. Every state color keeps text at
//  4.5:1 or better on the background, on a card and on its own tinted
//  pill, in both schemes (checked Nov 14: light 4.55 to 5.99, dark 4.82
//  to 6.66). One accent (deep teal) marks what can be tapped; red appears
//  only on destructive actions. Dark is a very dark gray, not pure black: pure black behind
//  white text gives some people glare halos. The camera screen is always
//  dark, so it always gets the bright shades.
//

import SwiftUI
import UIKit

enum Theme {
    static let searching = shade(dark: 0x00E5FF, classic: 0x007A99)
    static let adjusting = shade(dark: 0xFFB300, classic: 0x945500)
    static let aligned = shade(dark: 0x00E676, classic: 0x087A4B)
    /// Burnt orange: a sign above its cut-off, or "worth discussing". Not
    /// red: red is kept for destructive actions (Delete), so a flagged
    /// result doesn't read as an alarm.
    static let attention = shade(dark: 0xFB923C, classic: 0xB93C0B)
    /// Gray: a sign the app couldn't check. Never amber, so it can't look
    /// like a warning.
    static let unmeasured = shade(dark: 0xAEAEB2, classic: 0x636366)
    /// Red, for destructive actions only (Delete).
    static let destructive = shade(dark: 0xFF7B7B, classic: 0xB42318)
    /// The one brand accent, a deep blue-leaning teal: the main button,
    /// links and selected items. Blue enough not to be mistaken for the
    /// "typical" green.
    static let accent = shade(dark: 0x4FB3C4, classic: 0x0D6E84)
    /// Text and icons on the accent.
    static let onAccent = shade(dark: 0x0B1215, classic: 0xFFFFFF)
    /// Main buttons use the accent.
    static let action = accent
    static let onAction = onAccent
    /// Main text: black on light, off-white on dark (pure white on a dark
    /// screen gives some people glare halos).
    static let text = shade(dark: 0xF8FAFC, classic: 0x000000)
    /// Supporting text.
    static let secondaryText = shade(dark: 0xAEAEB2, classic: 0x636366)
    /// The page behind the cards.
    static let background = shade(dark: 0x121214, classic: 0xF2F2F7)
    /// Cards and tiles.
    static let card = shade(dark: 0x1F1F23, classic: 0xFFFFFF)

    static func color(for state: CaptureState) -> Color {
        switch state {
        case .searching: return searching
        case .adjusting: return adjusting
        case .aligned: return aligned
        }
    }

    /// A color that follows the screen's look.
    private static func shade(dark: UInt32, classic: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let darkColor = ui(dark), classicColor = ui(classic)
        return Color(UIColor { $0.userInterfaceStyle == .light ? classicColor : darkColor })
    }
}

/// One spacing scale (8-point steps), so every screen breathes the same way.
enum Spacing {
    /// Between closely related lines.
    static let tight: CGFloat = 8
    /// Inside cards, between rows.
    static let normal: CGFloat = 16
    /// Between components.
    static let component: CGFloat = 24
    /// Between sections.
    static let section: CGFloat = 32
}

extension AppAppearance {
    /// What SwiftUI should prefer; nil follows the phone's setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: return nil
        case .classic: return .light
        case .dark: return .dark
        }
    }

    /// The scheme to force on a screen presented over the always-dark
    /// camera: Automatic takes the phone's own setting, since there it
    /// would otherwise inherit the camera's dark.
    var schemeOverCamera: ColorScheme {
        colorScheme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light)
    }
}

/// Starts a new assessment (opens the camera) from any screen.
private struct StartAssessmentKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var startAssessment: () -> Void {
        get { self[StartAssessmentKey.self] }
        set { self[StartAssessmentKey.self] = newValue }
    }
}

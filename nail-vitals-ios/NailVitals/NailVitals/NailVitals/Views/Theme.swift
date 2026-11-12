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
//  pill, in both schemes (checked Nov 12: light 4.55 to 5.99, dark 4.82
//  to 6.66). Dark is a very dark gray, not pure black: pure black behind
//  white text gives some people glare halos. The camera screen is always
//  dark, so it always gets the bright shades.
//

import SwiftUI
import UIKit

enum Theme {
    static let searching = shade(dark: 0x00E5FF, classic: 0x007A99)
    static let adjusting = shade(dark: 0xFFB300, classic: 0x945500)
    static let aligned = shade(dark: 0x00E676, classic: 0x087A4B)
    /// Coral: a sign above its cut-off, or "worth discussing".
    static let attention = shade(dark: 0xFF7B7B, classic: 0xBF3030)
    /// Gray: a sign the app couldn't check. Never amber, so it can't look
    /// like a warning.
    static let unmeasured = shade(dark: 0xAEAEB2, classic: 0x636366)
    /// Main buttons: charcoal in Classic, white in Dark (no cyan outside
    /// the camera).
    static let action = shade(dark: 0xFFFFFF, classic: 0x1C1C1E)
    /// Text and icons on a main button.
    static let onAction = shade(dark: 0x000000, classic: 0xFFFFFF)
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

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
//  Two looks, picked on Home (AppAppearance): Classic (white, the
//  default) and Dark. Each color has a Classic shade that keeps text at
//  4.5:1 or better on white, on the gray background and on its own tinted
//  pill (checked Nov 11: 4.55 to 5.99). The camera screen is always dark,
//  so it always gets the bright shades.
//

import SwiftUI
import UIKit

enum Theme {
    static let searching = shade(dark: 0x00E5FF, classic: 0x007A99)
    static let adjusting = shade(dark: 0xFFB300, classic: 0x945500)
    static let aligned = shade(dark: 0x00E676, classic: 0x087A4B)
    /// Coral: a sign above its cut-off, or "worth discussing".
    static let attention = shade(dark: 0xFF6B6B, classic: 0xBF3030)
    /// Gray: a sign the app couldn't check. Never amber, so it can't look
    /// like a warning.
    static let unmeasured = shade(dark: 0xAEAEB2, classic: 0x636366)
    /// Main buttons: charcoal in Classic, white in Dark (no cyan outside
    /// the camera).
    static let action = shade(dark: 0xFFFFFF, classic: 0x1C1C1E)
    /// Supporting text.
    static let secondaryText = shade(dark: 0xAEAEB2, classic: 0x636366)
    /// The page behind the cards.
    static let background = shade(dark: 0x000000, classic: 0xF2F2F7)
    /// Cards and tiles.
    static let card = shade(dark: 0x1C1C1E, classic: 0xFFFFFF)

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

/// The app's look, chosen from the Home screen's menu. Classic is the default.
enum AppAppearance: String, CaseIterable {
    case dark
    case classic

    static let storageKey = "appearance"

    var label: String {
        switch self {
        case .dark: return "Dark"
        case .classic: return "Classic (white)"
        }
    }

    var colorScheme: ColorScheme { self == .classic ? .light : .dark }
}

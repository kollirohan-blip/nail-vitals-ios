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
//  neutral -- white and gray on graphite -- and uses color only for
//  result states.
//
//  Two looks, picked on Home (AppAppearance): Dark, and Classic (white).
//  Each color has a Classic shade dark enough to read on white. The camera
//  screen is always dark, so it always gets the bright shades.
//

import SwiftUI
import UIKit

enum Theme {
    static let searching = shade(dark: 0x00E5FF, classic: 0x007A99)
    static let adjusting = shade(dark: 0xFFB300, classic: 0xA35F00)
    static let aligned = shade(dark: 0x00E676, classic: 0x087A4B)
    /// Coral: a sign above its cut-off, or "worth discussing".
    static let attention = shade(dark: 0xFF6B6B, classic: 0xCF3B3B)
    /// Main buttons after a scan: cyan in Dark, charcoal in Classic.
    static let action = shade(dark: 0x00E5FF, classic: 0x1C1C1E)
    /// Background glow only, on the home side.
    static let violet = Color(red: 0.56, green: 0.42, blue: 1)

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

/// The app's look, chosen from the Home screen's menu.
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

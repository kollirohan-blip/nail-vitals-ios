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

import SwiftUI

enum Theme {
    static let searching = Color(red: 0, green: 229 / 255, blue: 1)          // #00E5FF
    static let adjusting = Color(red: 1, green: 179 / 255, blue: 0)          // #FFB300
    static let aligned = Color(red: 0, green: 230 / 255, blue: 118 / 255)    // #00E676
    /// Coral: a sign above its cut-off, or "worth discussing".
    static let attention = Color(red: 1, green: 107 / 255, blue: 107 / 255)  // #FF6B6B
    /// Background glow only, on the home side.
    static let violet = Color(red: 0.56, green: 0.42, blue: 1)

    static func color(for state: CaptureState) -> Color {
        switch state {
        case .searching: return searching
        case .adjusting: return adjusting
        case .aligned: return aligned
        }
    }
}

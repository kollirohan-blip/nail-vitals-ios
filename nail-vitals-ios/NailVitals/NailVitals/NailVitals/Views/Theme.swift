//
//  Theme.swift
//  NailVitals
//
//  Shared colors from the capture design spec (guided_capture_demo.html):
//  cyan while searching, amber while adjusting, green when aligned.
//

import SwiftUI

enum Theme {
    static let searching = Color(red: 0, green: 229 / 255, blue: 1)          // #00E5FF
    static let adjusting = Color(red: 1, green: 179 / 255, blue: 0)          // #FFB300
    static let aligned = Color(red: 0, green: 230 / 255, blue: 118 / 255)    // #00E676

    static func color(for state: CaptureState) -> Color {
        switch state {
        case .searching: return searching
        case .adjusting: return adjusting
        case .aligned: return aligned
        }
    }
}

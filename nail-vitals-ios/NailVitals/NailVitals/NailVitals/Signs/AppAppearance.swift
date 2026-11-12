//
//  AppAppearance.swift
//  NailVitals
//
//  The app's look, chosen from Home's menu. Automatic (the default)
//  follows the phone's light or dark setting: light suits reading in
//  daylight, dark is easier on the eyes at night. The camera screen is
//  always dark. How each look maps to SwiftUI is in Theme.swift.
//

import Foundation

nonisolated enum AppAppearance: String, CaseIterable {
    case automatic
    case classic
    case dark

    static let storageKey = "appearance"

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .classic: return "White"
        case .dark: return "Dark"
        }
    }

    /// The look for a saved setting; Automatic when nothing (or something
    /// this build doesn't know) was saved.
    static func from(stored: String?) -> AppAppearance {
        stored.flatMap(AppAppearance.init(rawValue:)) ?? .automatic
    }
}

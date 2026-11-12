//
//  SignResult.swift
//  NailVitals
//
//  The v2 result model: every nail sign the app can check gives one
//  SignResult in one of four states. Every result screen shows a list of
//  these, so a new sign needs an analyzer and its flag in
//  SignAvailability, and no screen changes.
//
//  Plain values only, so Tools/signs-harness can test them.
//

import Foundation

/// How the report card groups the signs.
nonisolated enum SignGroup: String, CaseIterable {
    case shape, colour, circulation, extra

    var title: String {
        switch self {
        case .shape: return "Shape"
        case .colour: return "Colour"
        case .circulation: return "Circulation"
        case .extra: return "Extra"
        }
    }
}

/// A nail sign, in the order the report card lists them.
nonisolated enum NailSign: String, Codable, CaseIterable {
    case clubbing, spoonNails, pallor, cyanosis, tipBands, refill, schamroth

    var title: String {
        switch self {
        case .clubbing: return "Clubbing"
        case .spoonNails: return "Spoon nails"
        case .pallor: return "Pallor"
        case .cyanosis: return "Cyanosis"
        case .tipBands: return "Terry's / half-and-half"
        case .refill: return "Refill time"
        case .schamroth: return "Schamroth window"
        }
    }

    var group: SignGroup {
        switch self {
        case .clubbing, .spoonNails: return .shape
        case .pallor, .cyanosis, .tipBands: return .colour
        case .refill: return .circulation
        case .schamroth: return .extra
        }
    }
}

/// What one sign's result says. Each sign documents how its numbers map to
/// these; for clubbing it is ClubbingAssessment's verdict.
nonisolated enum SignState: String, Codable {
    /// In the range seen in healthy fingers.
    case typical
    /// Close to a cut-off, or one noisy reading: measure again.
    case measureAgain
    /// Past a cut-off: worth showing a doctor.
    case worthDiscussing
    /// The app couldn't measure this sign this time. Never a warning.
    case couldntCheck

    /// For picking a report's overall state. "Couldn't check" is the
    /// lowest: an unmeasured sign never raises the banner.
    var severity: Int {
        switch self {
        case .couldntCheck: return 0
        case .typical: return 1
        case .measureAgain: return 2
        case .worthDiscussing: return 3
        }
    }

    var label: String {
        switch self {
        case .typical: return "Typical"
        case .measureAgain: return "Measure again"
        case .worthDiscussing: return "Worth discussing"
        case .couldntCheck: return "Couldn't check"
        }
    }

    /// SF Symbol shown with the colour and the word, so the state never
    /// depends on colour alone.
    var symbol: String {
        switch self {
        case .typical: return "checkmark.circle"
        case .measureAgain: return "arrow.clockwise.circle"
        case .worthDiscussing: return "exclamationmark.triangle"
        case .couldntCheck: return "minus.circle"
        }
    }

    init(_ verdict: ClubbingAssessment.Verdict) {
        switch verdict {
        case .typical: self = .typical
        case .measureAgain: self = .measureAgain
        case .worthDiscussing: self = .worthDiscussing
        }
    }

    /// One clubbing sign against its own cut-off.
    init(_ status: SignStatus) {
        switch status {
        case .typical: self = .typical
        case .nearThreshold: self = .measureAgain
        case .above: self = .worthDiscussing
        }
    }
}

/// One sign's result for one check-up.
nonisolated struct SignResult: Codable, Equatable, Identifiable {
    var sign: NailSign
    var state: SignState
    /// The headline number; nil when there is none.
    var value: Double?
    /// The value as shown: "166.9°", "≥180°", "1.4 s".
    var valueText: String?
    /// Why it couldn't be checked (state == .couldntCheck).
    var reason: String?
    /// Which version of the sign's analyzer measured it.
    var analyzerVersion: Int

    var id: String { sign.rawValue }
}

//
//  CheckupWording.swift
//  NailVitals
//
//  The short lines of text on Home and History: the status line (which
//  finger, how it came out, when), the latest-against-previous comparison,
//  and whether a change is within the usual day-to-day range. Plain logic,
//  so Tools/signs-harness can test it.
//

import Foundation

nonisolated enum CheckupWording {

    static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// "today", "yesterday", "3 days ago", "3 weeks ago", "on Oct 5".
    /// A date after `now` (the clock was changed) counts as today.
    static func relativeDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                                   to: calendar.startOfDay(for: now)).day ?? 0)
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default: return "on " + shortDate(date, calendar: calendar)
        }
    }

    /// Home's one status line: "Right index · Typical · assessed 2 days ago".
    static func statusLine(hand: MeasuredHand?, overall: SignState?, date: Date?, now: Date = Date(),
                           calendar: Calendar = .current) -> String {
        guard let date, let hand else { return "No assessments yet" }
        let state = (overall ?? .couldntCheck).label
        return "\(hand.label) index · \(state) · assessed \(relativeDay(date, now: now, calendar: calendar))"
    }

    /// "Last assessment 3 days ago · nothing stood out".
    /// - Parameters:
    ///   - date: when the last assessment was; nil when there isn't one.
    ///   - overall: its overall state.
    static func lastCheckupLine(date: Date?, overall: SignState?, now: Date = Date(),
                                calendar: Calendar = .current) -> String {
        guard let date else { return "No assessments yet" }
        let outcome: String
        switch overall {
        case .typical: outcome = "nothing stood out"
        case .measureAgain: outcome = "measure again"
        case .worthDiscussing: outcome = "worth discussing with a doctor"
        case .couldntCheck, nil: outcome = "couldn't check"
        }
        return "Last assessment \(relativeDay(date, now: now, calendar: calendar)) · \(outcome)"
    }

    /// History's comparison: "Latest 166.8° · previous 168.1° (Nov 5)".
    static func comparison(_ kind: SignKind, latest: Double, previous: Double, previousDate: Date,
                           calendar: Calendar = .current) -> String {
        "Latest \(kind.formatted(latest)) · previous \(kind.formatted(previous)) (\(shortDate(previousDate, calendar: calendar)))"
    }

    /// Whether a change is within how far the same finger usually moves
    /// from day to day (Repeatability). Never "better" or "worse": a change
    /// of a few degrees is usually how the finger was held.
    static func changeNote(_ kind: SignKind, latest: Double, previous: Double) -> String {
        guard let range = Repeatability.range95[kind] else { return "" }
        let usual = kind == .depthRatio ? String(format: "± %.2f", range) : String(format: "± %.0f°", range)
        if abs(latest - previous) <= range {
            return "Within the usual day-to-day range (\(usual))."
        }
        return "More than the usual day-to-day range (\(usual)). Assess again with your finger held straight to check it."
    }

    private static func shortDate(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

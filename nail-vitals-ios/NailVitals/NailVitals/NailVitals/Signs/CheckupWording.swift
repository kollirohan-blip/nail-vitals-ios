//
//  CheckupWording.swift
//  NailVitals
//
//  Home's two lines of text: a greeting for the time of day, and when the
//  last check-up was and how it came out. Plain logic, so
//  Tools/signs-harness can test it.
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

    /// "Last check-up 3 days ago · nothing stood out".
    /// - Parameters:
    ///   - date: when the last check-up was; nil when there isn't one.
    ///   - overall: its overall state.
    static func lastCheckupLine(date: Date?, overall: SignState?, now: Date = Date(),
                                calendar: Calendar = .current) -> String {
        guard let date else { return "No check-ups yet" }
        // Whole calendar days; a date after "now" (the clock was changed)
        // counts as today.
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                                   to: calendar.startOfDay(for: now)).day ?? 0)
        let when: String
        switch days {
        case 0: when = "today"
        case 1: when = "yesterday"
        case 2..<14: when = "\(days) days ago"
        case 14..<60: when = "\(days / 7) weeks ago"
        default:
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            style.timeZone = calendar.timeZone
            when = "on " + date.formatted(style)
        }
        let outcome: String
        switch overall {
        case .typical: outcome = "nothing stood out"
        case .measureAgain: outcome = "measure again"
        case .worthDiscussing: outcome = "worth discussing with a doctor"
        case .couldntCheck, nil: outcome = "couldn't check"
        }
        return "Last check-up \(when) · \(outcome)"
    }
}

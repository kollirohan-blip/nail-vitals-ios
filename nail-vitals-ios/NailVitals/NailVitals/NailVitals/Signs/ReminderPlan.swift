//
//  ReminderPlan.swift
//  NailVitals
//
//  When the optional "next check-up" reminder fires, and what its button
//  says. One reminder at a time, at 6 PM local time on the target day, and
//  only when the person asks for it. No reminder after "worth discussing"
//  (the next step is a doctor, not another scan) or "couldn't check".
//
//  Plain logic, so Tools/signs-harness can test it.
//

import Foundation

nonisolated enum ReminderPlan {
    static let hour = 18

    /// Days until the reminder that fits a result; nil for no reminder.
    static func days(after state: SignState) -> Int? {
        switch state {
        case .typical: return 14
        case .measureAgain: return 1
        case .worthDiscussing, .couldntCheck: return nil
        }
    }

    /// 6 PM local time, `days` calendar days after `now`; the day after
    /// when that would already be in the past.
    static func fireDate(from now: Date, days: Int, calendar: Calendar = .current) -> Date {
        func sixPM(daysAhead: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        let planned = sixPM(daysAhead: max(0, days))
        return planned > now ? planned : sixPM(daysAhead: max(0, days) + 1)
    }

    static func buttonTitle(days: Int) -> String {
        if days <= 1 { return "Remind me tomorrow" }
        if days % 7 == 0 { return "Remind me in \(days / 7) week\(days == 7 ? "" : "s")" }
        return "Remind me in \(days) days"
    }
}

//
//  NextAction.swift
//  NailVitals
//
//  The one main thing to do after a result, so the report card has a
//  single clear next step instead of three equal buttons: a reminder when
//  nothing stood out, another assessment when the app says measure again
//  or couldn't check, and sharing with a doctor when a result is worth
//  discussing.
//

import Foundation

nonisolated enum NextAction: Equatable {
    case remind(days: Int)
    case assessAgain
    case shareWithDoctor

    init(after state: SignState) {
        switch state {
        case .typical: self = .remind(days: ReminderPlan.days(after: .typical) ?? 14)
        case .measureAgain, .couldntCheck: self = .assessAgain
        case .worthDiscussing: self = .shareWithDoctor
        }
    }
}

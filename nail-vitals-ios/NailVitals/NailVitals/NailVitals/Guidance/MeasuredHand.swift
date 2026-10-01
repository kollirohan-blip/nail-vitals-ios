//
//  MeasuredHand.swift
//  NailVitals
//
//  Which index finger is being measured. The right index is the usual
//  standard in clubbing studies (Bentley 1976, Husarik 2002). In 26
//  healthy people the hyponychial angle read 178.6 right vs 180.4 left
//  (not significant, Husarik 2002), so readings from the two hands are
//  kept apart.
//

import Foundation

nonisolated enum MeasuredHand: String, CaseIterable {
    case right, left

    var label: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        }
    }
}

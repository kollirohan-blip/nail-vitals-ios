//
//  MeasuredHand.swift
//  NailVitals
//
//  Which index finger is being measured. The right index is the usual
//  standard in clubbing studies; right and left can differ by about 2 deg,
//  so readings from the two hands are never mixed in one session.
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

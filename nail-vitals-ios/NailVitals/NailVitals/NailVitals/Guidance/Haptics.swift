//
//  Haptics.swift
//  NailVitals
//
//  The camera screen's buzzes, with generators prepared ahead so they land
//  on time: light ticks as the finger fills the target, and a success buzz
//  once the photo has been delivered. Nothing buzzes while the photo is
//  being taken: a buzz then can blur it, and a buzz just before it made
//  first-time users flinch out of position.
//

import UIKit

final class Haptics {
    private let tick = UIImpactFeedbackGenerator(style: .light)
    private let success = UINotificationFeedbackGenerator()

    func prepare() {
        tick.prepare()
        success.prepare()
    }

    /// Light tick when the fit crosses 0.4 or 0.6 on the way up.
    func fitChanged(from old: Double, to new: Double) {
        guard [0.4, 0.6].contains(where: { old < $0 && new >= $0 }) else { return }
        tick.impactOccurred()
        tick.prepare()
    }

    /// The photo has been taken and delivered.
    func photoTaken() {
        success.notificationOccurred(.success)
        success.prepare()
    }
}

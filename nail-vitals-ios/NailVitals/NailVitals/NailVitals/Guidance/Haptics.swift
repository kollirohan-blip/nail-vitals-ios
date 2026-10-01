//
//  Haptics.swift
//  NailVitals
//
//  The camera screen's buzzes, with generators prepared ahead so they land
//  on time: light ticks as the finger fills the target, a success buzz on
//  lock, and a firm thump once the photo has been delivered. Nothing buzzes
//  while the photo is being exposed (a buzz then can blur it), which is why
//  the thump waits for the delivered photo.
//

import UIKit

final class Haptics {
    private let tick = UIImpactFeedbackGenerator(style: .light)
    private let lock = UINotificationFeedbackGenerator()
    private let thump = UIImpactFeedbackGenerator(style: .heavy)

    func prepare() {
        tick.prepare()
        lock.prepare()
        thump.prepare()
    }

    /// Light tick when the fit crosses 0.4 or 0.6 on the way up.
    func fitChanged(from old: Double, to new: Double) {
        guard [0.4, 0.6].contains(where: { old < $0 && new >= $0 }) else { return }
        tick.impactOccurred()
        tick.prepare()
    }

    /// Everything lines up (the glove turns green).
    func locked() {
        lock.notificationOccurred(.success)
        lock.prepare()
    }

    /// The photo has been delivered.
    func shutter() {
        thump.impactOccurred()
        thump.prepare()
    }
}

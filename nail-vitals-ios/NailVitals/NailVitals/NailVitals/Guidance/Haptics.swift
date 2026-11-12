//
//  Haptics.swift
//  NailVitals
//
//  The app's buzzes. On the camera screen, generators are prepared ahead
//  so they land on time: light ticks as the finger fills the target, and a
//  success buzz once the photo has been delivered. On the result, each
//  state has its own pattern (result(_:)). Nothing buzzes while the photo is
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

    /// The result's own buzz as its banner appears: success for typical,
    /// the warning buzz for "measure again", two soft taps for "worth
    /// discussing" (noticeable, but not the harsh error buzz), one light
    /// tick when the app couldn't check. So the result can be felt.
    static func result(_ state: SignState) {
        switch state {
        case .typical:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .measureAgain:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .worthDiscussing:
            let tap = UIImpactFeedbackGenerator(style: .medium)
            tap.impactOccurred(intensity: 0.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { tap.impactOccurred(intensity: 0.7) }
        case .couldntCheck:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

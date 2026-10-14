//
//  FingerIdentity.swift
//  NailVitals
//
//  Catches a switch of finger partway through a 3-reading scan: during
//  scan sessions with other people, some changed fingers or hands between
//  readings, and the session's middle values then mixed two fingers.
//
//  What the saved captures (82 photos, Sep 30 - Oct 5) showed is reliable:
//   - Which side of the photo the nail faces: the same in every reading of
//     every clean session; it flipped mid-session only where a hand was
//     switched (Sep 30, 20:32).
//   - Which finger is raised, from hand pose's four finger chains: the index
//     on 80 of 82 photos; the one "middle" was that same switched hand.
//   - How far a reading moves from the session's first: replaying the
//     readings as confirmed on the phone, clean sessions moved at most 4.7
//     degrees and 0.06 in depth ratio. Over the limits (7, 0.10): the
//     fingertip bent back on purpose (Oct 5, 158 against 168 straight) and
//     one early test session (168, 163, 176).
//  Not reliable, so not used: Vision's left/right-hand guess (it called
//  most scans of either hand "right" in this side view), and the finger's
//  thickness over its length (hand pose's DIP joint moves too much: 0.58-
//  0.84 within one session).
//

import CoreGraphics

nonisolated struct FingerPrint: Codable, Equatable {
    /// Left or right hand, from Vision's hand pose (recorded, not used to decide).
    var side: HandSide
    /// Whether the nail faced the photo's right side (from the thumb's side).
    var nailOnRight: Bool?
    var lovibond: Double?
    var depthRatio: Double?

    init(hand: HandLandmarks, signs: FingerSigns) {
        side = hand.side
        let dip = hand.indexDIP.point
        // A point well to the photo's right of the finger, level with the DIP joint.
        nailOnRight = hand.isOnNailSide(CGPoint(x: dip.x + hand.imageSize.width * 0.25, y: dip.y))
        // With no cuticle dip the profile angle is a stand-in (180), not measured.
        lovibond = signs.noCuticleDip ? nil : signs.lovibond
        depthRatio = signs.depthRatio
    }
}

nonisolated enum FingerSwitch: Equatable {
    /// The nail faces the other way: the other hand (or the hand turned around).
    case otherHand
    /// Same way round, but the reading is far outside what one finger gives.
    case veryDifferent
}

nonisolated enum FingerIdentity {
    /// Largest change from the session's first reading that one finger
    /// gives (clean sessions moved at most 4.7 degrees and 0.06).
    static let maxNailAngleChange = 7.0
    static let maxDepthRatioChange = 0.10

    /// Why `later` doesn't look like the same finger as `first`, or nil.
    static func mismatch(first: FingerPrint, later: FingerPrint) -> FingerSwitch? {
        if let a = first.nailOnRight, let b = later.nailOnRight, a != b { return .otherHand }
        if let a = first.lovibond, let b = later.lovibond, abs(b - a) > maxNailAngleChange { return .veryDifferent }
        if let a = first.depthRatio, let b = later.depthRatio, abs(b - a) > maxDepthRatioChange { return .veryDifferent }
        return nil
    }

    /// Which finger is the raised one in the outline, by hand pose: the
    /// finger whose tip is nearest the outline's top, if it's within a
    /// finger's width of it (on saved captures the index tip was at most 0.6
    /// widths away). nil when hand pose found no finger there.
    static func raisedFingerName(contour: [CGPoint], imageSize: CGSize, hands: [[FingerChain]]) -> (name: FingerChain.Name, distance: CGFloat)? {
        guard let finger = OutlineFingerFinder.raisedFinger(in: contour),
              OutlineFingerFinder.isPlausible(finger, imageSize: imageSize) else { return nil }
        // The outline's highest point on the finger, not its axis.
        let apex = contour.filter { abs($0.x - finger.apex.x) < finger.width }.min { $0.y < $1.y } ?? finger.apex
        let nearest = hands.flatMap { $0 }.min {
            hypot($0.tip.point.x - apex.x, $0.tip.point.y - apex.y) < hypot($1.tip.point.x - apex.x, $1.tip.point.y - apex.y)
        }
        guard let nearest else { return nil }
        let distance = hypot(nearest.tip.point.x - apex.x, nearest.tip.point.y - apex.y)
        return distance < finger.width ? (nearest.name, distance / finger.width) : nil
    }
}

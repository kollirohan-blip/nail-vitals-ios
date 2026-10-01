//
//  OutlineFingerFinder.swift
//  NailVitals
//
//  Backup for hand pose: finds the raised finger from the hand's outline
//  (the subject mask) alone. Hand pose can miss the raised finger or label
//  a curled one as the index -- seen with rings on the index finger and
//  with an OK-sign hand (thumb touching the middle finger), where the
//  model expects the index to be the curled one. The outline doesn't care
//  which finger is up: start at the outline's highest point, follow the
//  finger down while it keeps a finger's width, and stop where it widens
//  into the fist. Only the top of the finger -- the part that is measured --
//  decides anything, so rings lower down don't break it (they widen the
//  outline a little, not like a fist does).
//
//  Joint positions along that finger come from where hand pose put them on
//  real side-view captures (see the calibration note on `jointFractions`).
//

import CoreGraphics

nonisolated enum OutlineFingerFinder {

    nonisolated struct Finger {
        /// Top of the outline: the fingertip.
        let apex: CGPoint
        /// Where the finger meets the rest of the hand, on the finger's axis.
        let base: CGPoint
        /// Unit vector from the base toward the tip.
        let axis: CGVector
        /// Typical width of the finger, image pixels.
        let width: CGFloat
        /// Apex to base, image pixels.
        var length: CGFloat { hypot(apex.x - base.x, apex.y - base.y) }

        /// A point `fraction` of the finger's length below the apex, on its axis.
        func point(atFraction fraction: CGFloat) -> CGPoint {
            CGPoint(x: apex.x - axis.dx * length * fraction, y: apex.y - axis.dy * length * fraction)
        }
    }

    /// Hand-pose joint positions as a fraction of apex-to-base length:
    /// medians over 28 side-view captures where hand pose found the finger
    /// (DIP ranged 0.32-0.57, so outline joints are estimates).
    static let jointFractions = (tip: CGFloat(0.08), dip: CGFloat(0.40), pip: CGFloat(0.75), mcp: CGFloat(1.35))

    /// The finger pointing up from the hand outline, or nil when the top of
    /// the outline doesn't look like a finger (too short or too wide).
    static func raisedFinger(in contour: [CGPoint]) -> Finger? {
        guard contour.count > 20, let apex = contour.min(by: { $0.y < $1.y }),
              let bottom = contour.map(\.y).max(), bottom - apex.y > 20 else { return nil }
        let height = bottom - apex.y
        let step = max(1, height / 500)

        var centers: [CGPoint] = [], widths: [CGFloat] = []
        var center = apex.x
        var y = apex.y + step
        var missed: CGFloat = 0
        var baseIndex: Int?
        while y < bottom {
            guard let (left, right) = interval(of: contour, atY: y, near: center, maxShift: (widths.last ?? height * 0.05)) else {
                // A short gap (e.g. a ring the mask cut out): keep going.
                missed += step
                if missed > max(step * 3, (widths.last ?? 0) * 0.5) { break }
                y += step
                continue
            }
            missed = 0
            let w = right - left
            widths.append(w)
            centers.append(CGPoint(x: (left + right) / 2, y: y))
            center = (left + right) / 2

            // The finger's own width: the middle of the recent stretch, past
            // the rounded tip. Stop once the outline has stayed much wider
            // for a few rows (the fist), after at least two finger widths.
            let n = widths.count
            if n >= 9 {
                let reference = median(Array(widths[(n / 2)..<n]))
                let depth = y - apex.y
                let lastThree = widths.suffix(3)
                if depth > reference * 2, lastThree.allSatisfy({ $0 > reference * 1.6 }) {
                    baseIndex = n - 4
                    break
                }
            }
            y += step
        }
        guard let end = baseIndex ?? (centers.isEmpty ? nil : centers.count - 1), end >= 8 else { return nil }

        let fingerWidths = Array(widths[(end / 3)...end])
        let width = median(fingerWidths)
        let depth = centers[end].y - apex.y
        guard depth > width * 1.8 else { return nil }

        // Axis: straight line through the centers below the rounded tip.
        let fit = Array(centers[(end / 4)...end])
        guard let axis = fitAxis(fit) else { return nil }
        // Base on the axis line, level with the last finger row.
        let mean = CGPoint(x: fit.map(\.x).reduce(0, +) / CGFloat(fit.count), y: fit.map(\.y).reduce(0, +) / CGFloat(fit.count))
        let t = (centers[end].y - mean.y) / (axis.dy == 0 ? -1 : -axis.dy)
        let base = CGPoint(x: mean.x - axis.dx * t, y: centers[end].y)
        // The highest outline point sits off the axis when the finger
        // leans; measure joints from its level on the axis instead.
        let s = (apex.x - mean.x) * axis.dx + (apex.y - mean.y) * axis.dy
        let tipOnAxis = CGPoint(x: mean.x + axis.dx * s, y: mean.y + axis.dy * s)
        return Finger(apex: tipOnAxis, base: base, axis: axis, width: width)
    }

    /// Whether hand pose's index finger is the raised finger in the outline:
    /// its tip near the top and its DIP joint inside the finger.
    static func handPose(_ hand: HandLandmarks, matches finger: Finger) -> Bool {
        let tip = coordinates(hand.indexTip.point, on: finger), dip = coordinates(hand.indexDIP.point, on: finger)
        return abs(tip.along) < finger.length * 0.3 && tip.across < finger.width
            && (0.15...0.9).contains(dip.along / finger.length) && dip.across < finger.width * 0.75
    }

    /// Whether hand pose's index fingertip is clearly not on the raised
    /// finger: well below its top, or off to the side.
    static func handPose(_ hand: HandLandmarks, isClearlyOff finger: Finger) -> Bool {
        let tip = coordinates(hand.indexTip.point, on: finger)
        return tip.along > finger.length * 0.5 || tip.across > finger.width * 1.5
    }

    /// Whether the outline's top looks like one finger, not a merged
    /// background object (e.g. a laptop the mask joined to the hand).
    static func isPlausible(_ finger: Finger, imageSize: CGSize) -> Bool {
        finger.width < imageSize.width * 0.3 && finger.width < finger.length * 0.55
    }

    /// Distance below the finger's top along its axis, and distance off
    /// the axis.
    private static func coordinates(_ p: CGPoint, on finger: Finger) -> (along: CGFloat, across: CGFloat) {
        let rel = CGVector(dx: p.x - finger.apex.x, dy: p.y - finger.apex.y)
        return (-(rel.dx * finger.axis.dx + rel.dy * finger.axis.dy), abs(rel.dx * finger.axis.dy - rel.dy * finger.axis.dx))
    }

    /// Joints for the raised finger, keeping hand pose's thumb when it's
    /// clearly off to one side of the finger (it decides the nail side).
    static func landmarks(for finger: Finger, thumbTip: HandLandmarks.Joint?, imageSize: CGSize) -> HandLandmarks {
        func joint(_ fraction: CGFloat) -> HandLandmarks.Joint {
            HandLandmarks.Joint(point: finger.point(atFraction: fraction), confidence: 0.5)
        }
        var thumb: HandLandmarks.Joint?
        if let t = thumbTip, t.confidence >= 0.4 {
            let rel = CGVector(dx: t.point.x - finger.base.x, dy: t.point.y - finger.base.y)
            let across = abs(rel.dx * finger.axis.dy - rel.dy * finger.axis.dx)
            if across > finger.width * 0.75 { thumb = t }
        }
        return HandLandmarks(
            indexTip: joint(jointFractions.tip), indexDIP: joint(jointFractions.dip),
            indexPIP: joint(jointFractions.pip), indexMCP: joint(jointFractions.mcp),
            wrist: nil, thumbTip: thumb, imageSize: imageSize, fromOutline: true
        )
    }

    /// Hand pose's joints when they describe the raised finger; otherwise
    /// joints found from the outline. nil only when neither works.
    /// A confident hand pose is only overruled when its fingertip is
    /// clearly elsewhere (a curled finger taken for the index). Needs hand
    /// pose to have seen a hand at all, so a bottle or a doorframe in the
    /// subject mask is never taken for a finger.
    static func resolve(_ hand: HandLandmarks?, contour: [CGPoint]?, imageSize: CGSize,
                        minConfidence: Float = 0.3, trustedConfidence: Float = 0.5) -> HandLandmarks? {
        guard let hand else { return nil }
        guard let contour, let finger = raisedFinger(in: contour), isPlausible(finger, imageSize: imageSize) else { return hand }
        if hand.minIndexConfidence >= minConfidence {
            if handPose(hand, matches: finger) { return hand }
            if hand.minIndexConfidence >= trustedConfidence, !handPose(hand, isClearlyOff: finger) { return hand }
        }
        return landmarks(for: finger, thumbTip: hand.thumbTip, imageSize: imageSize)
    }

    // MARK: - Geometry

    /// The inside stretch of the outline on the horizontal line at `y` that
    /// contains (or is nearest to) x = `near`.
    private static func interval(of contour: [CGPoint], atY y: CGFloat, near x: CGFloat, maxShift: CGFloat) -> (CGFloat, CGFloat)? {
        var xs: [CGFloat] = []
        for i in 0..<contour.count {
            let p = contour[i], q = contour[(i + 1) % contour.count]
            guard (p.y <= y) != (q.y <= y) else { continue }
            xs.append(p.x + (q.x - p.x) * (y - p.y) / (q.y - p.y))
        }
        xs.sort()
        var best: (CGFloat, CGFloat)?
        var bestGap = CGFloat.greatestFiniteMagnitude
        var i = 0
        while i + 1 < xs.count {
            let l = xs[i], r = xs[i + 1]
            let gap = x < l ? l - x : (x > r ? x - r : 0)
            if gap < bestGap { bestGap = gap; best = (l, r) }
            i += 2
        }
        return bestGap <= maxShift ? best : nil
    }

    /// Unit direction (pointing up, toward smaller y) of the best-fit line
    /// x = a + b*y through the points.
    private static func fitAxis(_ points: [CGPoint]) -> CGVector? {
        let n = CGFloat(points.count)
        guard n >= 2 else { return nil }
        let my = points.map(\.y).reduce(0, +) / n, mx = points.map(\.x).reduce(0, +) / n
        var syy: CGFloat = 0, sxy: CGFloat = 0
        for p in points { syy += (p.y - my) * (p.y - my); sxy += (p.x - mx) * (p.y - my) }
        guard syy > 0 else { return nil }
        let b = sxy / syy  // dx per dy
        let length = hypot(b, 1)
        return CGVector(dx: -b / length, dy: -1 / length)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

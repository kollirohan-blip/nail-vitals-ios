//
//  FingerSigns.swift
//  NailVitals
//
//  The three side-view clubbing signs, measured from the finger outline and
//  the hand-pose tip and DIP joints:
//   - Lovibond (profile) angle: from AngleAnalyzer (local fit at the cuticle).
//   - Hyponychial angle: outside angle at the cuticle (B) between a line to
//     the nail-side edge at the DIP knuckle (A, the distal digital crease)
//     and a line to the nail-side edge at the fingertip (C, the hyponychium).
//     Long lines make it robust to outline noise, and it needs no cuticle
//     dip, so it works on clubbed fingers. Healthy 178.9 +/- 4.7 deg, above
//     192 deg in clubbing (Husarik et al., Swiss Med Wkly 2002, photos of
//     the radial side of the index finger).
//   - Phalangeal depth ratio: finger thickness at the nail bed (cuticle
//     level) / thickness at the DIP joint. Below 1.0 in people without
//     clubbing (Myers & Farquhar, JAMA 2001); our healthy photos averaged
//     0.84.
//  Plain geometry only, so Tools/angle-harness can test it.
//

import CoreGraphics

nonisolated struct FingerSigns: Equatable {
    nonisolated struct Slice: Equatable {
        let a: CGPoint
        let b: CGPoint
        var width: CGFloat { hypot(b.x - a.x, b.y - a.y) }
    }

    var lovibond: Double?
    var hyponychial: Double?
    var depthRatio: Double?

    /// A, B, C of the hyponychial angle (image pixels).
    var crease: CGPoint?
    var cuticle: CGPoint?
    var hyponychium: CGPoint?
    /// Across-the-finger slices for the depth ratio.
    var nailBedSlice: Slice?
    var jointSlice: Slice?
}

nonisolated enum FingerSignsAnalyzer {

    /// - Parameters:
    ///   - contour: closed finger/hand outline, image pixels.
    ///   - tip, dip: hand-pose index fingertip and DIP joint.
    ///   - cuticle: the confirmed cuticle point on the nail-side edge.
    ///   - lovibond: the confirmed Lovibond angle, passed through.
    ///   - isNailSide: whether a point is on the nail side of the finger
    ///     (HandLandmarks.isOnNailSide); without it the hyponychial angle,
    ///     which needs the nail side, is left out.
    ///   - turnDegrees: how far the nail-side profile turns in over the
    ///     fingertip where the nail's free edge (the hyponychium) is taken.
    ///     30 deg put it at the visible free edge on real captures (45 went
    ///     past it toward the tip); 33 healthy photos then averaged 180.6
    ///     (SD 4.2), against the published 178.9 (SD 4.7).
    static func measure(contour: [CGPoint], tip: CGPoint, dip: CGPoint, cuticle: CGPoint,
                        lovibond: Double?, isNailSide: ((CGPoint) -> Bool?)?,
                        turnDegrees: Double = 30) -> FingerSigns {
        var signs = FingerSigns(lovibond: lovibond, cuticle: cuticle)
        guard let frame = FingerFrame(tip: tip, dip: dip), contour.count > 3 else { return signs }

        // Depth ratio: thickness at the cuticle's level vs at the DIP joint.
        let cuticleLevel = frame.along(cuticle)
        let jointWidth = averageWidth(contour, frame, at: 0)
        let nailBedWidth = averageWidth(contour, frame, at: cuticleLevel)
        signs.jointSlice = slice(contour, frame, at: 0)
        signs.nailBedSlice = slice(contour, frame, at: cuticleLevel)
        if let jointWidth, let nailBedWidth, jointWidth > 0 {
            signs.depthRatio = Double(nailBedWidth / jointWidth)
        }

        // Hyponychial angle, on the nail side.
        guard let isNailSide,
              let nailOnPlus = isNailSide(frame.point(along: 0, across: frame.length)) else { return signs }
        let side: CGFloat = nailOnPlus ? 1 : -1
        guard let crease = edgePoint(contour, frame, at: 0, side: side),
              let hyponychium = hyponychium(contour, frame, from: cuticleLevel, side: side, turnDegrees: turnDegrees)
        else { return signs }
        // The cuticle sits on the nail-side edge; a hand-placed dot only
        // says how far along the finger it is.
        let onEdge = edgePoint(contour, frame, at: cuticleLevel, side: side) ?? cuticle
        signs.cuticle = onEdge
        signs.crease = crease
        signs.hyponychium = hyponychium
        signs.hyponychial = AngleAnalyzer.outsideAngle(nailPoint: hyponychium, cuticle: onEdge, skinPoint: crease) {
            polygonContains(contour, $0)
        }
        return signs
    }

    /// The hyponychium, under the nail's free edge: following the nail-side
    /// profile from the cuticle toward the tip, the first place where it
    /// stops running along the finger and turns in over the fingertip by
    /// `turnDegrees`. If it never turns that far (a pointed tip, a long
    /// nail), the last profile point before the tip.
    static func hyponychium(_ contour: [CGPoint], _ frame: FingerFrame, from cuticleLevel: CGFloat,
                            side: CGFloat, turnDegrees: Double) -> CGPoint? {
        let step = frame.length / 200
        let half = max(1, Int((frame.length * 0.02 / step).rounded()))
        var levels: [CGFloat] = [], heights: [CGFloat] = [], points: [CGPoint] = []
        var level = cuticleLevel
        while level < frame.length * 2 {
            guard let p = edgePoint(contour, frame, at: level, side: side) else { break }
            let height = frame.across(p) * side
            // A jump outward means the crossing moved to a different finger.
            if let last = heights.last, height - last > frame.length * 0.08 { break }
            levels.append(level); heights.append(height); points.append(p)
            level += step
        }
        guard points.count > 2 * half + 1 else { return points.last }
        let threshold = CGFloat(tan(turnDegrees * .pi / 180))
        let start = max(half, Int(frame.length * 0.1 / step))
        if start < points.count - half {
            for i in start..<(points.count - half) {
                let slope = (heights[i + half] - heights[i - half]) / (levels[i + half] - levels[i - half])
                if slope < -threshold { return points[i] }
            }
        }
        return points.last
    }

    // MARK: - Geometry

    /// Coordinates along the finger (from the DIP joint toward the tip) and
    /// across it.
    nonisolated struct FingerFrame {
        let origin: CGPoint
        let axis: CGVector      // unit, DIP -> tip
        let normal: CGVector    // unit, perpendicular
        let length: CGFloat     // DIP to tip

        init?(tip: CGPoint, dip: CGPoint) {
            let l = hypot(tip.x - dip.x, tip.y - dip.y)
            guard l > 1 else { return nil }
            origin = dip
            axis = CGVector(dx: (tip.x - dip.x) / l, dy: (tip.y - dip.y) / l)
            normal = CGVector(dx: -axis.dy, dy: axis.dx)
            length = l
        }

        func along(_ p: CGPoint) -> CGFloat { (p.x - origin.x) * axis.dx + (p.y - origin.y) * axis.dy }
        func across(_ p: CGPoint) -> CGFloat { (p.x - origin.x) * normal.dx + (p.y - origin.y) * normal.dy }
        func point(along a: CGFloat, across c: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + axis.dx * a + normal.dx * c, y: origin.y + axis.dy * a + normal.dy * c)
        }
    }

    /// Outline crossings of the line across the finger at `level`, as
    /// (across offset, point).
    private static func crossings(_ contour: [CGPoint], _ frame: FingerFrame, at level: CGFloat) -> [(CGFloat, CGPoint)] {
        var result: [(CGFloat, CGPoint)] = []
        for i in 0..<contour.count {
            let p = contour[i], q = contour[(i + 1) % contour.count]
            let a0 = frame.along(p) - level, a1 = frame.along(q) - level
            guard a0 != a1, (a0 <= 0) != (a1 <= 0) else { continue }
            let t = a0 / (a0 - a1)
            let x = CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
            result.append((frame.across(x), x))
        }
        return result
    }

    /// The finger's edge on one side at `level`: the crossing nearest the
    /// finger's axis on that side (the axis runs through the finger, so the
    /// nearest crossing is the finger's own edge, not a neighbouring finger).
    static func edgePoint(_ contour: [CGPoint], _ frame: FingerFrame, at level: CGFloat, side: CGFloat) -> CGPoint? {
        crossings(contour, frame, at: level)
            .filter { $0.0 * side > 0 }
            .min { abs($0.0) < abs($1.0) }?.1
    }

    private static func slice(_ contour: [CGPoint], _ frame: FingerFrame, at level: CGFloat) -> FingerSigns.Slice? {
        guard let minus = edgePoint(contour, frame, at: level, side: -1),
              let plus = edgePoint(contour, frame, at: level, side: 1) else { return nil }
        return FingerSigns.Slice(a: minus, b: plus)
    }

    /// Width averaged over three slices a few percent of the finger length
    /// apart, to smooth out outline noise and skin creases.
    private static func averageWidth(_ contour: [CGPoint], _ frame: FingerFrame, at level: CGFloat) -> CGFloat? {
        let widths = [-0.03, 0, 0.03].compactMap { offset in
            slice(contour, frame, at: level + frame.length * offset)?.width
        }
        return widths.isEmpty ? nil : widths.reduce(0, +) / CGFloat(widths.count)
    }

    private static func polygonContains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

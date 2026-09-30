//
//  AngleAnalyzer.swift
//  NailVitals
//
//  Full Swift port of the Lovibond angle pipeline from
//  contour_angle.py (find_fingertip, curvature_along_contour,
//  find_cuticle_inflection, fit_line, angle_between_lines,
//  measure_lovibond_angle). NOT YET COMPILED/TESTED -- no Swift
//  toolchain available where this was written. Treat as a strong
//  first draft to debug on the Mac.
//
//  This carries forward every real bug we found and fixed while
//  building the Python version -- see inline comments at each spot.
//  Do not "simplify" these away without understanding why they're
//  there; each one came from testing against actual photos, not
//  theoretical concerns.
//
//  ONE THING THAT GENUINELY NEEDS VERIFICATION ON DEVICE: Vision
//  framework's contour point ordering (clockwise vs counterclockwise)
//  may differ from OpenCV's convention, which the Python version relied
//  on for its "left"/"right" stepping direction. If results come out
//  systematically mirrored (e.g. the side that should be "left" always
//  reports as "right"), that's the likely cause -- just swap the step
//  directions in searchInflectionPoint, don't rewrite the algorithm.
//

import CoreGraphics

struct LovibondCandidate {
    let side: String  // "left" or "right", matching Python's naming
    let angleDegrees: Double
    let inflectionPoint: CGPoint   // SUGGESTED point -- see note below
    // NEW: needed so InflectionPointConfirmation can call
    // recomputeAngle() again if the user drags this point to a
    // different spot on the contour -- recomputeAngle needs the
    // ORIGINAL search direction (step) and a valid contour index to
    // work from, neither of which can be recovered from
    // inflectionPoint alone (it's just a raw CGPoint by that stage).
    let inflectionIndex: Int
    let step: Int  // -1 for "left", +1 for "right" -- matches analyze()'s (side, step) pairing below
}

struct LovibondResult {
    let fingertip: CGPoint
    // NEW: exposed so InflectionPointConfirmation can pass them back
    // into recomputeAngle() and can nearest-neighbor-search the full
    // contour when the user drags a marker. None of this was needed
    // until a real confirmation UI existed to call back into the
    // analyzer -- previously this data just lived and died inside
    // analyze()'s local scope.
    let tipIndex: Int
    let contourPoints: [CGPoint]
    let segmentLengthPixels: Double
    let candidates: [LovibondCandidate]
}

final class AngleAnalyzer {

    /// Full pipeline, mirroring measure_lovibond_angle() in
    /// contour_angle.py -- but see IMPORTANT note below.
    ///
    /// IMPORTANT: the inflection point this returns is a SUGGESTION,
    /// not a final answer. We tested automatic corner-detection
    /// (originally raw local-curvature-maximum, then an improved
    /// best-fit-split search) against synthetic shapes with
    /// mathematically known angles, and found it's unreliable
    /// specifically for SHALLOW bends near 160-180 degrees -- which
    /// is exactly the clinically normal range, i.e. the case we most
    /// need to get right. The line-fitting and angle math themselves
    /// are verified exact (zero error against ground truth), so the
    /// fix is NOT more algorithm tuning here -- it's letting the
    /// person tap/drag to confirm or correct this suggested point
    /// before the final angle gets computed. See
    /// InflectionPointConfirmation (Views/) for that UI step.
    /// - Parameter dipHint: the index finger's DIP joint (image pixels, from
    ///   hand pose). The cuticle always lies between the fingertip and this
    ///   joint, so when given, the search is confined to that stretch.
    /// - Parameter tipHint: the index fingertip (hand pose). With it, the
    ///   apex is taken from the outline near the real fingertip instead of
    ///   the outline's topmost point, and if the outline doesn't pass near
    ///   the fingertip at all, nothing is returned.
    func analyze(_ silhouette: DetectedSilhouette, dipHint: CGPoint? = nil, tipHint: CGPoint? = nil) -> LovibondResult? {
        let points = silhouette.contourPoints
        guard points.count > 20 else { return nil }

        // On device, a finger held over a laptop got merged with the laptop in
        // the subject mask: the outline traced the laptop, its top edge was
        // taken as the "fingertip", and the reading was nonsense (~181-269).
        // The finger's own edge isn't in such an outline, so refuse. Same
        // anatomical search band as the dipHint-only path below.
        if let dip = dipHint, let tipHint {
            guard let tipIndex = fingertipIndex(points, near: tipHint, dip: dip) else { return nil }
            let tip = points[tipIndex]
            let l = Double(hypot(dip.x - tip.x, dip.y - tip.y))
            guard l > 20 else { return nil }
            return search(points: points, tip: tip, tipIndex: tipIndex,
                          windowDistancePixels: l * 0.25,
                          maxSearchDistancePixels: l * 0.65,
                          segmentLengthPixels: l * 0.12,
                          tipZoneDistancePixels: l * 0.15)
        }

        // Anatomical search band from the tip-apex-to-DIP distance L.
        // Without it, a shallow (near-180) cuticle loses to the pointed-tip-
        // to-nail transition, which always bends outward and reads as false
        // clubbing (189-193 seen on device). The first zoomed on-device photo
        // put the real cuticle at ~0.42 L (an earlier 0.55-0.85 L guess left
        // markers well below it), so the band is 0.25-0.65 L.
        if let dip = dipHint, let tipIndex = findFingertipIndex(points) {
            let tip = points[tipIndex]
            let l = Double(hypot(dip.x - tip.x, dip.y - tip.y))
            if l > 20, let result = search(points: points, tip: tip, tipIndex: tipIndex,
                                           windowDistancePixels: l * 0.25,
                                           maxSearchDistancePixels: l * 0.65,
                                           segmentLengthPixels: l * 0.12,
                                           tipZoneDistancePixels: l * 0.15) {
                return result
            }
        }

        let perimeter = contourPerimeter(points)
        // CORRECTED: my first attempt at this (bumping the old 0.12
        // perimeter-fraction up to 0.30) was WRONG -- based on a
        // misread screenshot, I assumed both candidates were
        // collapsing too close to the tip. Real device testing showed
        // the opposite: candidates landing at OPPOSITE EDGES OF THE
        // SCREEN, meaning the search was already free to wander too
        // FAR from the tip, not too little. Any percentage of total
        // PERIMETER is the wrong kind of bound here regardless of the
        // exact number -- perimeter includes the whole folded fist,
        // wrist, and palm creases, none of which have anything to do
        // with where a cuticle should physically be. findBestSplit()
        // scores purely by two-line-fit residual with NO distance
        // penalty, so it's structurally biased toward whichever bend
        // is SHARPEST anywhere in the search window -- and a
        // clinically-normal cuticle (a subtle, nearly-straight
        // 160-180 degree bend) will systematically lose that contest
        // against a genuinely sharp, unrelated crease elsewhere in
        // the hand, wherever one happens to fall within range.
        //
        // CORRECTED AGAIN: the previous fix (bounding by
        // silhouette.boundingBox.width as a stand-in for "finger
        // width") was ALSO wrong, for a different reason -- that
        // bounding box wraps the ENTIRE hand, fist included, and a
        // folded fist is considerably WIDER than the actual extended
        // finger. So "3x finger width" was really closer to "3x fist
        // width," generous enough that it barely constrained anything
        // -- real device testing after this fix STILL showed
        // candidates landing at the edges of the frame.
        //
        // FIX: stop trying to infer "finger width" from a bounding box
        // that's dominated by the wider fist. Instead bound the search
        // by a small fraction of the PHOTO'S OWN HEIGHT -- a cuticle
        // should never be more than a modest slice of the frame away
        // from the tip if the photo was framed the way the app's
        // guidance asks for, regardless of hand shape or fist size.
        // This sidesteps the whole "estimate finger thickness"
        // problem instead of trying to fix it again.
        //
        // TODO/VERIFY: maxSearchFrameHeightFraction=0.15 is a first
        // guess (roughly: cuticle within the top ~15% of frame height
        // from the tip), not calibrated against real photos -- if
        // candidates still land far from the real cuticle, lower this;
        // if they're landing too close to the tip, raise it. Test this
        // one on an ACTUAL capture-to-confirmation run, not just
        // reasoning about it -- that's what caught the previous
        // fix's flaw.
        // CORRECTED A THIRD TIME: the frame-height-fraction fix STILL
        // failed real device testing -- candidates were still landing
        // at the frame edges. The actual flaw wasn't the number
        // (0.15), it was the whole APPROACH: converting a physical
        // pixel budget into an INDEX COUNT via one global "average
        // point spacing" (perimeter / point count). That average is
        // unreliable because point density is NOT uniform along a
        // hand's contour -- the curved fingertip gets sampled much
        // more densely than the straighter wrist/arm edges. Walking a
        // fixed number of index steps from the tip can cover wildly
        // different REAL distances depending on which stretch of the
        // contour that walk happens to pass through. No single
        // average could fix that, regardless of which fraction was
        // chosen -- which is exactly why two different numbers, both
        // reasoned out carefully, both failed the same way.
        //
        // FIX: stop converting to an index count at all. findBestSplit
        // now checks the ACTUAL Euclidean distance from the tip to
        // each candidate point directly, every step, and stops the
        // search the moment that real distance exceeds the budget --
        // see its updated signature below. No averaging, no
        // approximation.
        guard let tipIndex = findFingertipIndex(points) else { return nil }
        let tip = points[tipIndex]

        // SUPERSEDES the frame-height bounds below: all search distances
        // now scale with the finger's own measured width (still real
        // pixel distances, never perimeter/index counts). Synthetic
        // fingers showed frame-height bounds only work at one finger
        // size -- smaller or larger fingers put the cuticle 50-110px off
        // or outside the search range entirely. Ratios assume a
        // side-view index finger (tip apex to cuticle ~1.2-1.6 widths);
        // capped at 2 widths so the next bend down (the DIP knuckle,
        // ~1 width past the cuticle) can't out-score the cuticle.
        if let width = estimateFingerWidth(points: points, tipIndex: tipIndex) {
            let w = Double(width)
            return search(points: points, tip: tip, tipIndex: tipIndex,
                          windowDistancePixels: w * 0.75,
                          maxSearchDistancePixels: w * 2.0,
                          segmentLengthPixels: w * 0.45,
                          tipZoneDistancePixels: w * 0.6)
        }

        // Fallback when the width can't be measured: the older
        // frame-height-based bounds.
        let maxSearchFrameHeightFraction = 0.15
        let maxSearchDistancePixels = Double(silhouette.imageSize.height) * maxSearchFrameHeightFraction
        // CORRECTED YET AGAIN: window (the minimum distance before a
        // candidate is even considered) was STILL perimeter-based
        // (perimeter * 0.006) even after fixing the maximum-distance
        // side of this search. Real device testing after switching the
        // final capture to highQuality (higher-resolution Vision
        // analysis) showed the exact same markers-at-the-corners
        // symptom, despite the max-distance fix being correct on its
        // own terms -- because a higher-fidelity trace resolves more
        // real detail (skin texture, tiny creases) and genuinely
        // computes a LONGER perimeter for the same physical hand (the
        // same effect that makes a coastline measured at higher
        // resolution come out longer). That inflated window enough to
        // skip past the real cuticle before the search even started
        // scoring candidates -- independent of the correct maximum
        // bound. Fixed the same way: real distance, not a perimeter
        // fraction, so it can't be thrown off by tracing fidelity.
        let windowDistancePixels = maxSearchDistancePixels * 0.05
        // FIX (completing the same conversion): segmentLen was STILL
        // perimeter-based (perimeter * 0.05), even after window and
        // the max-distance bound were both fixed. Confirmed necessary
        // by real device testing -- markers were STILL landing wrong
        // after those two fixes, and this was the one remaining
        // perimeter-derived value left. Same coastline-effect problem:
        // a higher-fidelity trace inflates perimeter, which inflated
        // this index count, which changed how much of the contour each
        // line-fit segment covered in a way that had nothing to do
        // with the actual geometry. Now expressed as a real distance
        // and walked directly (see collectSegment below) instead of a
        // fixed index count.
        // TODO/VERIFY: segmentLengthPixels as 30% of the max search
        // distance is a first guess, not calibrated -- if the fitted
        // lines look too short/noisy to reliably distinguish a real
        // bend, raise it; if they're picking up unrelated curvature
        // beyond the immediate area of the split point, lower it.
        let segmentLengthPixels = maxSearchDistancePixels * 0.3

        return search(points: points, tip: tip, tipIndex: tipIndex,
                      windowDistancePixels: windowDistancePixels,
                      maxSearchDistancePixels: maxSearchDistancePixels,
                      segmentLengthPixels: segmentLengthPixels,
                      tipZoneDistancePixels: 0)
    }

    private func search(
        points: [CGPoint], tip: CGPoint, tipIndex: Int,
        windowDistancePixels: Double, maxSearchDistancePixels: Double, segmentLengthPixels: Double,
        tipZoneDistancePixels: Double
    ) -> LovibondResult? {
        var candidates: [LovibondCandidate] = []
        for (side, step) in [("left", -1), ("right", 1)] {
            guard let splitIndex = findBestSplit(
                points: points, tipIndex: tipIndex, step: step,
                windowDistancePixels: windowDistancePixels, maxSearchDistancePixels: maxSearchDistancePixels, segmentLengthPixels: segmentLengthPixels,
                tipZoneDistancePixels: tipZoneDistancePixels
            ) else { continue }

            guard let angle = computeAngleAtInflection(
                points: points, tipIndex: tipIndex, inflectionIndex: splitIndex,
                step: step, segmentLengthPixels: segmentLengthPixels
            ) else { continue }

            candidates.append(LovibondCandidate(
                side: side,
                angleDegrees: angle,
                inflectionPoint: points[splitIndex],
                inflectionIndex: splitIndex,
                step: step
            ))
        }

        guard !candidates.isEmpty else { return nil }
        return LovibondResult(
            fingertip: tip,
            tipIndex: tipIndex,
            contourPoints: points,
            segmentLengthPixels: segmentLengthPixels,
            candidates: candidates
        )
    }

    /// Recomputes the angle for a specific inflection point the user
    /// picked/adjusted by hand, bypassing the automatic search
    /// entirely. Called after the person confirms or drags the
    /// suggested point in the UI.
    func recomputeAngle(
        points: [CGPoint], tipIndex: Int, userConfirmedIndex: Int,
        step: Int, segmentLengthPixels: Double
    ) -> Double? {
        computeAngleAtInflection(
            points: points, tipIndex: tipIndex, inflectionIndex: userConfirmedIndex,
            step: step, segmentLengthPixels: segmentLengthPixels
        )
    }

    // MARK: - Fingertip

    /// The outline's apex near the hand-pose fingertip: among outline points
    /// within 0.6 of the tip-to-DIP distance of the tip joint, the one
    /// furthest out along the DIP-to-tip direction (so a tilted finger still
    /// gets its real apex). nil when the outline never comes near the tip.
    private func fingertipIndex(_ points: [CGPoint], near tipHint: CGPoint, dip: CGPoint) -> Int? {
        let length = hypot(tipHint.x - dip.x, tipHint.y - dip.y)
        guard length > 0 else { return nil }
        let axis = CGVector(dx: (tipHint.x - dip.x) / length, dy: (tipHint.y - dip.y) / length)
        var best: Int?
        var bestReach = -CGFloat.infinity
        for (i, p) in points.enumerated() where hypot(p.x - tipHint.x, p.y - tipHint.y) <= length * 0.6 {
            let reach = (p.x - dip.x) * axis.dx + (p.y - dip.y) * axis.dy
            if reach > bestReach {
                bestReach = reach
                best = i
            }
        }
        return best
    }

    private func findFingertipIndex(_ points: [CGPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        var minY = points[0].y
        var minIndex = 0
        for (i, p) in points.enumerated() where p.y < minY {
            minY = p.y
            minIndex = i
        }
        return minIndex
    }

    /// Finger width just below the tip: walk the contour both ways from
    /// the tip to a given depth and measure the horizontal gap, then
    /// re-measure at depth = that width until it settles (the rounded
    /// tip is narrower than the finger, so a shallow first depth
    /// underestimates).
    private func estimateFingerWidth(points: [CGPoint], tipIndex: Int) -> CGFloat? {
        let n = points.count
        let tipY = points[tipIndex].y

        func widthAt(depth: CGFloat) -> CGFloat? {
            func walk(_ step: Int) -> CGPoint? {
                for k in 1..<(n / 2) {
                    let p = points[((tipIndex + step * k) % n + n) % n]
                    if p.y >= tipY + depth { return p }
                }
                return nil
            }
            guard let a = walk(1), let b = walk(-1) else { return nil }
            return abs(a.x - b.x)
        }

        var depth: CGFloat = 20
        var width: CGFloat = 0
        for _ in 0..<6 {
            guard let w = widthAt(depth: depth), w > 0 else { break }
            width = w
            if depth >= w { break }
            depth = w
        }
        return width > 0 ? width : nil
    }

    // MARK: - Best-fit-split search (replaces raw curvature-maximum)

    /// Instead of picking the single sharpest local-curvature point
    /// (found to be unreliable, especially for shallow bends -- see
    /// class-level note), this tries many candidate split points and
    /// picks whichever gives the BEST two-line fit (minimum combined
    /// per-point residual). Verified against synthetic ground-truth
    /// shapes to correctly identify a perfectly straight control edge
    /// (180 degrees) in most cases -- a real improvement over the
    /// curvature approach, though not a complete fix, which is why
    /// user confirmation is still required.
    ///
    /// UPDATED: stops based on REAL Euclidean distance from the tip,
    /// not a fixed count of contour points -- see the class-level
    /// comment in analyze() for why an index-count bound (even a
    /// carefully-computed one) was structurally unreliable. This
    /// checks actual pixel distance every step, so it can't be fooled
    /// by uneven point density along different parts of the contour.
    private func findBestSplit(
        points: [CGPoint], tipIndex: Int, step: Int,
        windowDistancePixels: Double, maxSearchDistancePixels: Double, segmentLengthPixels: Double,
        tipZoneDistancePixels: Double
    ) -> Int? {
        let n = points.count
        guard n > 0 else { return nil }
        var bestIndex: Int?
        var bestResidual = Double.infinity
        var bestTurnIndex: Int?
        var bestTurn = -1.0
        var bestDipIndex: Int?
        var bestDip = -1.0
        let maxStraightRms = max(1.5, segmentLengthPixels * 0.03)
        let orientation = signedArea(points) * CGFloat(step)
        let tip = points[tipIndex]

        var k = 1
        while k < n {
            let splitIdx = ((tipIndex + step * k) % n + n) % n
            let candidatePoint = points[splitIdx]

            // The actual fix: real distance, checked directly, not
            // inferred from how many points we've stepped through.
            let distanceFromTip = Double(hypot(candidatePoint.x - tip.x, candidatePoint.y - tip.y))
            if distanceFromTip > maxSearchDistancePixels {
                break
            }

            // Skip scoring candidates too close to the tip itself --
            // a near-zero-length segment trivially "fits" any line
            // with ~zero residual, which would otherwise win by
            // default without meaning anything. This is the window
            // check, now also real-distance-based -- see analyze()'s
            // comment on windowDistancePixels for why the old
            // perimeter-based version wasn't reliable.
            if distanceFromTip < windowDistancePixels {
                k += 1
                continue
            }

            // Both segments are LOCAL, equal-length windows on either
            // side of the candidate. seg1 used to run all the way from
            // the tip apex; on synthetic fingers with known angles that
            // made the fit prefer points on the rounded fingertip (every
            // finger scored ~125 deg, ~200px from the real cuticle).
            let seg1 = nailSideSegment(points: points, tipIndex: tipIndex, splitIndex: splitIdx, step: step, segmentLengthPixels: segmentLengthPixels)
            // The nail-side window itself must start clear of the rounded
            // tip, or the tip-to-nail transition reads as a false convex
            // "corner" (a normal 170 deg finger scored 191 = clubbed).
            if let windowStart = seg1.first,
               Double(hypot(windowStart.x - tip.x, windowStart.y - tip.y)) < tipZoneDistancePixels {
                k += 1
                continue
            }
            let seg2 = collectSegment(points: points, startIndex: splitIdx, step: step, targetDistancePixels: segmentLengthPixels)
            guard seg1.count >= 5, seg2.count >= 5 else {
                k += 1
                continue
            }

            let r1 = lineFitResidual(seg1)
            let r2 = lineFitResidual(seg2)
            let total = r1 / Double(seg1.count) + r2 / Double(seg2.count)

            if total < bestResidual {
                bestResidual = total
                bestIndex = splitIdx
            }

            // Local windows fit ANY straight stretch perfectly, so residual
            // alone ties a flat point with the real corner. Among points
            // where both windows are genuinely straight (which excludes the
            // rounded tip), prefer the biggest change in direction.
            let rms1 = sqrt(r1 / Double(seg1.count))
            let rms2 = sqrt(r2 / Double(seg2.count))
            if rms1 <= maxStraightRms && rms2 <= maxStraightRms {
                let d1 = fitLineOriented(seg1), d2 = fitLineOriented(seg2)
                let turn = acos(max(-1, min(1, Double(d1.dx * d2.dx + d1.dy * d2.dy))))
                if turn > bestTurn {
                    bestTurn = turn
                    bestTurnIndex = splitIdx
                }
                let isDip = (d1.dx * d2.dy - d1.dy * d2.dx) * orientation < 0
                if isDip && turn > bestDip {
                    bestDip = turn
                    bestDipIndex = splitIdx
                }
            }

            k += 1
        }
        // A normal cuticle is the only inward dip on the nail side: the
        // rounded tip above it and the skin slope below it both bulge
        // outward (on device the old max-turn rule picked that lower bulge).
        // Only when there's no real dip -- the clubbing case -- fall back to
        // the sharpest bend overall. ("First bend below the nail, either
        // direction" was also tried: it read 12 synthetic normal fingers as
        // clubbed, because the rounded tip is usually that first bend.)
        if bestDip >= minCuticleDipRadians, let bestDipIndex {
            return bestDipIndex
        }
        return bestTurnIndex ?? bestIndex
    }

    private let minCuticleDipRadians = 4.0 * .pi / 180

    /// Sum of squared perpendicular distances from points to their
    /// best-fit line -- lower means the points are more truly
    /// collinear. Used to score candidate split points in
    /// findBestSplit().
    private func lineFitResidual(_ points: [CGPoint]) -> Double {
        let direction = fitLineOriented(points)
        let meanX = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
        let meanY = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
        let pointOnLine = CGPoint(x: meanX, y: meanY)

        var totalResidual: Double = 0
        for p in points {
            let vx = p.x - pointOnLine.x
            let vy = p.y - pointOnLine.y
            let proj = vx * direction.dx + vy * direction.dy
            let perpX = vx - proj * direction.dx
            let perpY = vy - proj * direction.dy
            totalResidual += Double(perpX * perpX + perpY * perpY)
        }
        return totalResidual
    }

    // MARK: - Line fitting + angle

    /// Walks from a starting index, collecting points until the real
    /// (straight-line-from-start) distance covers approximately
    /// targetDistancePixels, rather than a fixed number of points --
    /// this is what makes segment length immune to how densely the
    /// contour happens to be sampled at that particular spot (see
    /// analyze()'s comment on segmentLengthPixels for the bug this
    /// fixes). Safety-capped at n so a degenerate contour can't loop
    /// forever.
    private func collectSegment(
        points: [CGPoint], startIndex: Int, step: Int, targetDistancePixels: Double,
        stopIndex: Int? = nil
    ) -> [CGPoint] {
        let n = points.count
        guard n > 0 else { return [] }
        let start = points[startIndex]
        var segment: [CGPoint] = [start]
        if startIndex == stopIndex { return segment }

        var k = 1
        while k < n {
            let idx = ((startIndex + step * k) % n + n) % n
            let p = points[idx]
            segment.append(p)
            if idx == stopIndex { break }

            let distanceFromStart = Double(hypot(p.x - start.x, p.y - start.y))
            if distanceFromStart >= targetDistancePixels {
                break
            }
            k += 1
        }
        return segment
    }

    /// Fits a line to the two segments on either side of the
    /// inflection point (tip-to-inflection = nail side,
    /// inflection-onward = skin side) and measures the angle between
    /// them.
    ///
    /// BUG WE FOUND AND FIXED (Python): a fitted line's direction has
    /// an ambiguous sign. If the two segments' directions aren't
    /// consistently oriented (both "forward" along the contour's
    /// traversal direction), the angle comes out flipped/wrong. This
    /// orients each fitted direction to match its segment's actual
    /// first-point-to-last-point direction before comparing them.
    private func computeAngleAtInflection(
        points: [CGPoint], tipIndex: Int, inflectionIndex: Int,
        step: Int, segmentLengthPixels: Double
    ) -> Double? {
        // Local nail-plate window just before the cuticle (not from the
        // tip apex -- the rounded fingertip biased the fit ~13 deg on
        // synthetic fingers with known angles).
        let seg1 = nailSideSegment(points: points, tipIndex: tipIndex, splitIndex: inflectionIndex, step: step, segmentLengthPixels: segmentLengthPixels)
        let seg2 = collectSegment(points: points, startIndex: inflectionIndex, step: step, targetDistancePixels: segmentLengthPixels)

        guard seg1.count >= 2, seg2.count >= 2 else { return nil }

        let dir1 = fitLineOriented(seg1)
        let dir2 = fitLineOriented(seg2)

        let dot = dir1.dx * dir2.dx + dir1.dy * dir2.dy
        let mag1 = sqrt(dir1.dx * dir1.dx + dir1.dy * dir1.dy)
        let mag2 = sqrt(dir2.dx * dir2.dx + dir2.dy * dir2.dy)
        guard mag1 > 0, mag2 > 0 else { return nil }

        let cosAngle = max(-1, min(1, dot / (mag1 * mag2)))
        let turn = acos(cosAngle) * 180 / .pi

        // Lovibond angle is measured on the OUTSIDE of the finger:
        // below 180 = the normal dip at the nail fold, above 180 = the
        // bulge of clubbing. An unsigned acos can't tell those apart
        // (200 deg used to read as 160), so the turn direction decides:
        // turning toward the finger's interior is a convex bulge. Cross
        // product and shoelace area share the image's handedness, and
        // stepping backwards (step == -1) flips the traversal direction.
        let cross = dir1.dx * dir2.dy - dir1.dy * dir2.dx
        let orientation = signedArea(points) * CGFloat(step)
        let isConvex = cross * orientation > 0
        return isConvex ? 180 + turn : 180 - turn
    }

    /// The segmentLengthPixels-long stretch of contour ending at the
    /// split point, walked back toward (never past) the fingertip, in
    /// traversal order so fitLineOriented points tip -> split.
    private func nailSideSegment(
        points: [CGPoint], tipIndex: Int, splitIndex: Int, step: Int, segmentLengthPixels: Double
    ) -> [CGPoint] {
        collectSegment(points: points, startIndex: splitIndex, step: -step,
                       targetDistancePixels: segmentLengthPixels, stopIndex: tipIndex).reversed()
    }

    /// Least-squares line direction (PCA-based, same approach verified
    /// against real photo data for GuidanceEngine's tilt calculation),
    /// explicitly oriented to match the point sequence's actual
    /// traversal direction (first point -> last point) -- this is the
    /// orientation fix, not just an undirected axis like tilt used.
    private func fitLineOriented(_ points: [CGPoint]) -> CGVector {
        let meanX = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
        let meanY = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)

        var sXX: CGFloat = 0, sYY: CGFloat = 0, sXY: CGFloat = 0
        for p in points {
            let dx = p.x - meanX
            let dy = p.y - meanY
            sXX += dx * dx
            sYY += dy * dy
            sXY += dx * dy
        }

        let theta = 0.5 * atan2(2 * sXY, sXX - sYY)
        var direction = CGVector(dx: cos(theta), dy: sin(theta))

        guard let first = points.first, let last = points.last else { return direction }
        let pathDirection = CGVector(dx: last.x - first.x, dy: last.y - first.y)
        let dot = direction.dx * pathDirection.dx + direction.dy * pathDirection.dy
        if dot < 0 {
            direction = CGVector(dx: -direction.dx, dy: -direction.dy)
        }
        return direction
    }

    /// Readings outside this range come from misplaced points, not anatomy
    /// (normal ~160, clubbing above 180; a manual mis-drag produced 305.7).
    static let plausibleRange: ClosedRange<Double> = 120...240

    // MARK: - Manual three-point angle

    /// Lovibond angle from three user-placed points (a point on the nail
    /// plate, the cuticle corner, a point on the skin fold), measured on the
    /// OUTSIDE of the finger so clubbing reads above 180. `isInsideFinger`
    /// says whether a point is inside the finger; nil = unknown, in which
    /// case the normal (concave, below 180) reading is assumed.
    nonisolated static func outsideAngle(
        nailPoint a: CGPoint, cuticle b: CGPoint, skinPoint c: CGPoint,
        isInsideFinger: (CGPoint) -> Bool?
    ) -> Double? {
        let u = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let v = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let lu = hypot(u.dx, u.dy), lv = hypot(v.dx, v.dy)
        guard lu > 0, lv > 0 else { return nil }
        let cosine = max(-1, min(1, (u.dx * v.dx + u.dy * v.dy) / (lu * lv)))
        let wedge = Double(acos(cosine)) * 180 / .pi

        // Probe just inside the wedge (along its bisector): if that lands
        // inside the finger, the wedge faces inward and the outside angle
        // is its reflex.
        let bisector = CGVector(dx: u.dx / lu + v.dx / lv, dy: u.dy / lu + v.dy / lv)
        let lb = hypot(bisector.dx, bisector.dy)
        guard lb > 1e-6 else { return 180 }
        let reach = 0.15 * min(lu, lv)
        let probe = CGPoint(x: b.x + bisector.dx / lb * reach, y: b.y + bisector.dy / lb * reach)
        return (isInsideFinger(probe) ?? false) ? 360 - wedge : wedge
    }

    // MARK: - Helpers

    /// Shoelace signed area; its sign gives the contour's winding.
    private func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 2 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    private func contourPerimeter(_ points: [CGPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            total += hypot(b.x - a.x, b.y - a.y)
        }
        return Double(total)
    }
}

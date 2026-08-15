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
}

struct LovibondResult {
    let fingertip: CGPoint
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
    func analyze(_ silhouette: DetectedSilhouette) -> LovibondResult? {
        let points = silhouette.contourPoints
        guard points.count > 20 else { return nil }

        let perimeter = contourPerimeter(points)
        let window = max(4, Int(perimeter * 0.006))
        let searchRange = max(40, Int(perimeter * 0.12))
        let segmentLen = max(20, Int(perimeter * 0.05))

        guard let tipIndex = findFingertipIndex(points) else { return nil }
        let tip = points[tipIndex]

        var candidates: [LovibondCandidate] = []
        for (side, step) in [("left", -1), ("right", 1)] {
            guard let splitIndex = findBestSplit(
                points: points, tipIndex: tipIndex, step: step,
                window: window, searchRange: searchRange, segmentLen: segmentLen
            ) else { continue }

            guard let angle = computeAngleAtInflection(
                points: points, tipIndex: tipIndex, inflectionIndex: splitIndex,
                step: step, segmentLen: segmentLen
            ) else { continue }

            candidates.append(LovibondCandidate(
                side: side,
                angleDegrees: angle,
                inflectionPoint: points[splitIndex]
            ))
        }

        guard !candidates.isEmpty else { return nil }
        return LovibondResult(fingertip: tip, candidates: candidates)
    }

    /// Recomputes the angle for a specific inflection point the user
    /// picked/adjusted by hand, bypassing the automatic search
    /// entirely. Called after the person confirms or drags the
    /// suggested point in the UI.
    func recomputeAngle(
        points: [CGPoint], tipIndex: Int, userConfirmedIndex: Int,
        step: Int, segmentLen: Int
    ) -> Double? {
        computeAngleAtInflection(
            points: points, tipIndex: tipIndex, inflectionIndex: userConfirmedIndex,
            step: step, segmentLen: segmentLen
        )
    }

    // MARK: - Fingertip

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
    private func findBestSplit(
        points: [CGPoint], tipIndex: Int, step: Int,
        window: Int, searchRange: Int, segmentLen: Int
    ) -> Int? {
        let n = points.count
        var bestIndex: Int?
        var bestResidual = Double.infinity

        for k in window..<searchRange {
            let splitIdx = ((tipIndex + step * k) % n + n) % n

            var seg1: [CGPoint] = []
            for j in 0..<k {
                seg1.append(points[((tipIndex + step * j) % n + n) % n])
            }
            var seg2: [CGPoint] = []
            for j in 0..<segmentLen {
                seg2.append(points[((splitIdx + step * j) % n + n) % n])
            }
            guard seg1.count >= 5, seg2.count >= 5 else { continue }

            let r1 = lineFitResidual(seg1)
            let r2 = lineFitResidual(seg2)
            let total = r1 / Double(seg1.count) + r2 / Double(seg2.count)

            if total < bestResidual {
                bestResidual = total
                bestIndex = splitIdx
            }
        }
        return bestIndex
    }

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
        step: Int, segmentLen: Int
    ) -> Double? {
        let n = points.count

        let seg1Count = max(1, (((inflectionIndex - tipIndex) * step) % n + n) % n)
        var seg1: [CGPoint] = []
        for k in 0..<seg1Count {
            seg1.append(points[((tipIndex + step * k) % n + n) % n])
        }

        var seg2: [CGPoint] = []
        for k in 0..<segmentLen {
            seg2.append(points[((inflectionIndex + step * k) % n + n) % n])
        }

        guard seg1.count >= 2, seg2.count >= 2 else { return nil }

        let dir1 = fitLineOriented(seg1)
        let dir2 = fitLineOriented(seg2)

        let dot = dir1.dx * dir2.dx + dir1.dy * dir2.dy
        let mag1 = sqrt(dir1.dx * dir1.dx + dir1.dy * dir1.dy)
        let mag2 = sqrt(dir2.dx * dir2.dx + dir2.dy * dir2.dy)
        guard mag1 > 0, mag2 > 0 else { return nil }

        let cosAngle = max(-1, min(1, dot / (mag1 * mag2)))
        let angleBetween = acos(cosAngle) * 180 / .pi

        // Lovibond convention: report the "outer" angle (normal is
        // ~160-180 deg, meaning nearly straight/collinear segments).
        return 180 - angleBetween
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

    // MARK: - Helpers

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

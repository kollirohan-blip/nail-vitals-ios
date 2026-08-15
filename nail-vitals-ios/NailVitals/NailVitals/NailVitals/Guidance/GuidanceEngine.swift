//
//  GuidanceEngine.swift
//  NailVitals
//
//  Direct port of guidance_logic.py -- already calibrated against 5
//  known-good real photos in the Python prototype (see
//  cv-prototype/guidance_logic.py for the calibration data and the
//  two real bugs we found + fixed: the tilt-angle sign ambiguity, and
//  the false-positive edge-cutoff check).
//
//  STATUS: stub -- straightforward port once SilhouetteDetector
//  supplies real contour data to feed this.
//

import CoreGraphics

enum GuidanceDirection: Equatable {
    case moveCloser
    case moveBack
    case moveLeft
    case moveRight
    case straighten(degrees: Double)
    case moveHandDown
    case noFingerDetected
    case looksGood
}

struct GuidanceResult {
    let widthFraction: Double
    let centerOffset: Double
    let tiltDegrees: Double
    let directions: [GuidanceDirection]
}

final class GuidanceEngine {

    // Calibrated from 5 known-good photos in the Python prototype --
    // do not change these without re-validating against real data,
    // the same way we did originally (guessed values were wrong the
    // first time; these are the corrected, tested ones).
    private let targetWidthFraction: ClosedRange<Double> = 0.55...0.85
    private let centerTolerance: Double = 0.20
    private let tiltToleranceDegrees: Double = 35.0

    func analyze(_ silhouette: DetectedSilhouette?) -> GuidanceResult {
        guard let silhouette = silhouette else {
            return GuidanceResult(
                widthFraction: 0, centerOffset: 0, tiltDegrees: 0,
                directions: [.noFingerDetected]
            )
        }

        let widthFraction = Double(silhouette.boundingBox.width / silhouette.imageSize.width)
        let centerXFraction = Double(
            (silhouette.boundingBox.minX + silhouette.boundingBox.width / 2) / silhouette.imageSize.width
        )
        let offset = centerXFraction - 0.5

        let tiltDegrees = computeTiltFromVertical(silhouette.contourPoints)

        var directions: [GuidanceDirection] = []

        if widthFraction < targetWidthFraction.lowerBound {
            directions.append(.moveCloser)
        } else if widthFraction > targetWidthFraction.upperBound {
            directions.append(.moveBack)
        }

        if abs(offset) > centerTolerance {
            directions.append(offset > 0 ? .moveLeft : .moveRight)
        }

        if tiltDegrees > tiltToleranceDegrees {
            directions.append(.straighten(degrees: tiltDegrees))
        }

        if silhouette.boundingBox.minY <= 2 {
            directions.append(.moveHandDown)
        }

        if directions.isEmpty {
            directions = [.looksGood]
        }

        return GuidanceResult(
            widthFraction: widthFraction,
            centerOffset: offset,
            tiltDegrees: tiltDegrees,
            directions: directions
        )
    }

    /// Swift equivalent of cv2.fitLine(DIST_L2), computing the tilt of
    /// the finger's silhouette from vertical.
    ///
    /// No OpenCV available in Swift, so this uses the point cloud's
    /// second moments to find the principal axis orientation directly
    /// -- mathematically equivalent to what cv2.fitLine(DIST_L2)
    /// computes, but as an UNDIRECTED axis angle (mod 180) rather than
    /// a direction vector with an ambiguous sign. That's actually
    /// cleaner than the Python version's approach: cv2.fitLine returns
    /// a direction vector whose sign is ambiguous, which is what
    /// caused the angle-wraparound bug we found and fixed in Python
    /// (fold via min(raw, 180-raw)). This formula sidesteps that
    /// entirely since doubling the angle in atan2(2*Sxy, ...) already
    /// makes it inherently mod-180 -- verified by hand for both the
    /// pure-vertical case (0 deg tilt) and pure-horizontal case (90
    /// deg tilt) before shipping this.
    private func computeTiltFromVertical(_ points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }

        let meanX = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
        let meanY = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)

        var sXX: CGFloat = 0
        var sYY: CGFloat = 0
        var sXY: CGFloat = 0
        for p in points {
            let dx = p.x - meanX
            let dy = p.y - meanY
            sXX += dx * dx
            sYY += dy * dy
            sXY += dx * dy
        }

        // Principal axis angle FROM THE X-AXIS, range -90...90 degrees
        // (the doubling inside atan2 is what makes this undirected/
        // mod-180, so a line and its 180-degree-rotated self give the
        // same theta -- no separate sign-ambiguity fix needed here).
        let thetaFromXAxis = 0.5 * atan2(2 * sXY, sXX - sYY) * 180 / .pi

        // Convert to deviation from VERTICAL (not horizontal): a
        // perfectly vertical contour has thetaFromXAxis near +-90,
        // which should read as 0 degrees of tilt.
        return 90 - abs(Double(thetaFromXAxis))
    }
}

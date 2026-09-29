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

// nonisolated: same fix as SilhouetteDetector -- marking just
// analyze() wasn't enough, since it calls private helpers
// (computeTiltFromVertical) that hit the identical warning. No
// shared mutable state here either (only let-constant thresholds),
// so nonisolated on the whole type is correct.
nonisolated final class GuidanceEngine {

    // Calibrated from 5 known-good photos in the Python prototype --
    // do not change these without re-validating against real data,
    // the same way we did originally (guessed values were wrong the
    // first time; these are the corrected, tested ones).
    private let targetWidthFraction: ClosedRange<Double> = 0.55...0.85
    private let centerTolerance: Double = 0.20
    private let tiltToleranceDegrees: Double = 35.0

    // Debug readout for the on-screen HUD: the aspect ratio of the most
    // recent silhouette, populated whether or not it passed the >= 1.4
    // gate, so a rejection there shows its real value. Same single-queue
    // safety reasoning as SilhouetteDetector.lastSolidity.
    private(set) nonisolated(unsafe) var lastAspectRatio: Double = 0

    // nonisolated: called synchronously from CameraManager's
    // nonisolated captureOutput() on a background queue -- this
    // method only touches let-constant thresholds (targetWidthFraction
    // etc.), no shared mutable state, so it's safe to mark nonisolated.
    nonisolated func analyze(_ silhouette: DetectedSilhouette?) -> GuidanceResult {
        guard let silhouette = silhouette else {
            lastAspectRatio = 0
            return GuidanceResult(
                widthFraction: 0, centerOffset: 0, tiltDegrees: 0,
                directions: [.noFingerDetected]
            )
        }

        // NEW: basic shape sanity check, added after real device
        // testing showed the pipeline was treating ANY large contour
        // (walls, doorframes, random edges) as a valid finger, since
        // SilhouetteDetector just finds "the largest contour in
        // frame" with no opinion on whether it looks finger-shaped.
        // A finger held up should be noticeably taller than it is
        // wide -- this threshold is a first pass, not carefully
        // calibrated against real data yet (unlike widthFraction/
        // centerTolerance/tiltTolerance below, which WERE validated
        // against the 5 known-good photos). Expect to need real-world
        // tuning once more device testing happens.
        let aspectRatio = silhouette.boundingBox.height / max(silhouette.boundingBox.width, 1)
        lastAspectRatio = Double(aspectRatio)
        guard aspectRatio >= 1.4 else {
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

    // Hand-pose coaching thresholds. Starting values from the Detection
    // Lab (finger read 26-34% of frame height at a comfortable distance,
    // joint confidence 0.75-0.89); tune with more device readings.
    private let minJointConfidence: Float = 0.3
    private let targetFingerLength: ClosedRange<Double> = 0.25...0.65
    private let maxLandmarkTiltDegrees: Double = 20
    private let maxPIPBendDegrees: Double = 30

    /// Live guidance from Apple's hand-pose joints -- replaces the
    /// silhouette-based analyze(_:) for coaching.
    nonisolated func analyze(landmarks: HandLandmarks?) -> GuidanceResult {
        guard let hand = landmarks, hand.minIndexConfidence >= minJointConfidence else {
            return GuidanceResult(widthFraction: 0, centerOffset: 0, tiltDegrees: 0, directions: [.noFingerDetected])
        }

        let size = hand.fingerLengthFraction
        let offset = Double(hand.indexDIP.point.x / hand.imageSize.width) - 0.5
        let tilt = hand.tiltFromVerticalDegrees

        var directions: [GuidanceDirection] = []
        if size < targetFingerLength.lowerBound {
            directions.append(.moveCloser)
        } else if size > targetFingerLength.upperBound {
            directions.append(.moveBack)
        }
        if abs(offset) > centerTolerance {
            directions.append(offset > 0 ? .moveLeft : .moveRight)
        }
        if tilt > maxLandmarkTiltDegrees || pipBendDegrees(hand) > maxPIPBendDegrees {
            directions.append(.straighten(degrees: tilt))
        }
        if hand.indexTip.point.y < hand.imageSize.height * 0.05 {
            directions.append(.moveHandDown)
        }
        if directions.isEmpty {
            directions = [.looksGood]
        }
        return GuidanceResult(widthFraction: size, centerOffset: offset, tiltDegrees: tilt, directions: directions)
    }

    /// How far the finger bends at the middle knuckle (0 = straight).
    private func pipBendDegrees(_ hand: HandLandmarks) -> Double {
        let a = CGVector(dx: hand.indexPIP.point.x - hand.indexMCP.point.x, dy: hand.indexPIP.point.y - hand.indexMCP.point.y)
        let b = CGVector(dx: hand.indexDIP.point.x - hand.indexPIP.point.x, dy: hand.indexDIP.point.y - hand.indexPIP.point.y)
        let magnitude = hypot(a.dx, a.dy) * hypot(b.dx, b.dy)
        guard magnitude > 0 else { return 0 }
        let cosine = max(-1, min(1, (a.dx * b.dx + a.dy * b.dy) / magnitude))
        return Double(acos(cosine)) * 180 / .pi
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

//
//  GuidanceEngine.swift
//  NailVitals
//
//  Live capture coaching from Apple's hand-pose joints (HandPoseDetector):
//  finger size in frame, centering, tilt, finger straightness, and fingertip
//  near the top edge. Replaced the original port of guidance_logic.py, which
//  worked from an edge-detected silhouette and depended on wall color,
//  lighting and skin tone.
//

import CoreGraphics

enum GuidanceDirection: Equatable {
    case moveCloser
    case moveBack
    case moveLeft
    case moveRight
    case straighten(degrees: Double)
    case moveHandDown
    /// The back of the hand is turned toward the camera; the nail needs to
    /// face sideways for the side-view measurements.
    case turnToSide
    case noFingerDetected
    case looksGood
}

struct GuidanceResult {
    let fingerLengthFraction: Double
    let centerOffset: Double
    let tiltDegrees: Double
    let directions: [GuidanceDirection]
}

// nonisolated: called synchronously from CameraManager's captureOutput on a
// background queue; only let-constant thresholds, no shared mutable state.
nonisolated final class GuidanceEngine {

    // Starting values from the Detection Lab (finger read 26-34% of frame
    // height at a comfortable distance, joint confidence 0.75-0.89); tune
    // with more device readings. centerTolerance carries over from the
    // Python prototype's calibration.
    private let minJointConfidence: Float = 0.3
    private let targetFingerLength: ClosedRange<Double> = 0.25...0.65
    private let centerTolerance: Double = 0.20
    private let maxLandmarkTiltDegrees: Double = 20
    private let maxPIPBendDegrees: Double = 30
    // Knuckle spread (HandLandmarks.knuckleSpread) on real captures: clean
    // side views 0.05-0.28; back of the hand toward the camera 0.50-0.70.
    // Only clear turns are caught; small ones overlap with side views.
    private let maxKnuckleSpread: Double = 0.42
    private let minKnuckleConfidence: Float = 0.3

    nonisolated func analyze(landmarks: HandLandmarks?) -> GuidanceResult {
        guard let hand = landmarks, hand.minIndexConfidence >= minJointConfidence else {
            return GuidanceResult(fingerLengthFraction: 0, centerOffset: 0, tiltDegrees: 0, directions: [.noFingerDetected])
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
        if let spread = hand.knuckleSpread, let little = hand.littleMCP,
           little.confidence >= minKnuckleConfidence, spread > maxKnuckleSpread {
            directions.append(.turnToSide)
        }
        if directions.isEmpty {
            directions = [.looksGood]
        }
        return GuidanceResult(fingerLengthFraction: size, centerOffset: offset, tiltDegrees: tilt, directions: directions)
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
}

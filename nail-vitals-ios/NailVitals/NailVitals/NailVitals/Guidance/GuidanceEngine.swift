//
//  GuidanceEngine.swift
//  NailVitals
//
//  Live capture coaching from Apple's hand-pose joints (HandPoseDetector):
//  how well the finger fills the on-screen hologram "glove" (GuidanceTarget:
//  position, size), plus tilt, straightness and a turned hand. Every photo
//  then comes out at about the same framing, which is what the reference
//  study fixed with a bar and a camera at 12 cm.
//

import CoreGraphics

enum GuidanceDirection: Equatable {
    case moveCloser
    case moveBack
    case moveLeft
    case moveRight
    case straighten(degrees: Double)
    case moveHandDown
    case moveUp
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
    /// How well the finger fills the hologram, 0...1.
    var fit: Double = 0
    /// Within the looser limits that keep a steady hold going once it has
    /// started (see CameraManager): small wobbles don't restart it.
    var steadyEnough = false
}

/// Where the hologram finger sits, in the camera frame's own coordinates
/// (0...1, top-left origin): the index fingertip joint, and the finger's
/// tip-to-knuckle length as a share of the frame height. Real captures
/// read 27-43%; 40% gives the nail plenty of pixels.
nonisolated enum GuidanceTarget {
    static let tip = CGPoint(x: 0.5, y: 0.28)
    static let length: CGFloat = 0.40
    /// Hand pose's DIP and PIP joints along the tip-to-knuckle line.
    static let dipFraction: CGFloat = 0.27
    static let pipFraction: CGFloat = 0.53

    static func tip(in size: CGSize) -> CGPoint { CGPoint(x: tip.x * size.width, y: tip.y * size.height) }
    static func mcp(in size: CGSize) -> CGPoint { CGPoint(x: tip.x * size.width, y: (tip.y + length) * size.height) }
    static func dip(in size: CGSize) -> CGPoint { CGPoint(x: tip.x * size.width, y: (tip.y + length * dipFraction) * size.height) }
}

// nonisolated: called synchronously from CameraManager's captureOutput on a
// background queue; only let-constant thresholds, no shared mutable state.
nonisolated final class GuidanceEngine {

    // Joint confidence from the Detection Lab (0.75-0.89 on good frames);
    // tilt and bend limits from early device testing, widened a little after
    // first-time users struggled to hold the tighter ones.
    private let minJointConfidence: Float = 0.3
    private let maxLandmarkTiltDegrees: Double = 25
    private let maxPIPBendDegrees: Double = 30

    /// Fit at or above this counts as "in the glove".
    static let alignedFit = 0.65
    /// Mean joint distance from the hologram (as a share of its length)
    /// at which the fit reaches 0.
    private let zeroFitError: Double = 0.35
    private let maxSizeError: Double = 0.20
    private let maxShiftError: Double = 0.15

    /// Looser limits for staying steady once a hold has started. Rotation
    /// is not loosened: a turned hand always stops the hold.
    private let steadyFit = 0.55
    private let steadySizeError: Double = 0.25
    private let steadyShiftError: Double = 0.18

    nonisolated func analyze(landmarks: HandLandmarks?) -> GuidanceResult {
        guard let hand = landmarks, hand.minIndexConfidence >= minJointConfidence else {
            return GuidanceResult(fingerLengthFraction: 0, centerOffset: 0, tiltDegrees: 0, directions: [.noFingerDetected])
        }

        let size = hand.fingerLengthFraction
        let offset = Double(hand.indexDIP.point.x / hand.imageSize.width) - 0.5
        let tilt = hand.tiltFromVerticalDegrees

        // Distances from the hologram's joints, as a share of its length.
        let frame = hand.imageSize
        let targetLength = Double(GuidanceTarget.length * frame.height)
        func error(_ p: CGPoint, _ t: CGPoint) -> Double { Double(hypot(p.x - t.x, p.y - t.y)) / targetLength }
        let meanError = (error(hand.indexTip.point, GuidanceTarget.tip(in: frame))
                         + error(hand.indexDIP.point, GuidanceTarget.dip(in: frame))
                         + error(hand.indexMCP.point, GuidanceTarget.mcp(in: frame))) / 3
        let fit = max(0, min(1, 1 - meanError / zeroFitError))

        let scale = size / Double(GuidanceTarget.length)
        let shift = Double((hand.indexTip.point.x + hand.indexMCP.point.x) / 2 - GuidanceTarget.tip.x * frame.width) / targetLength
        let lift = Double(hand.indexTip.point.y - GuidanceTarget.tip(in: frame).y) / targetLength

        var directions: [GuidanceDirection] = []
        if hand.isClearlyTurned {
            directions.append(.turnToSide)
        }
        if tilt > maxLandmarkTiltDegrees || pipBendDegrees(hand) > maxPIPBendDegrees {
            directions.append(.straighten(degrees: tilt))
        }
        if scale < 1 - maxSizeError {
            directions.append(.moveCloser)
        } else if scale > 1 + maxSizeError {
            directions.append(.moveBack)
        }
        if abs(shift) > maxShiftError {
            directions.append(shift > 0 ? .moveLeft : .moveRight)
        }
        if lift > maxShiftError {
            directions.append(.moveUp)
        } else if lift < -maxShiftError {
            directions.append(.moveHandDown)
        }
        if directions.isEmpty {
            // Each part is close enough; together they may still be off.
            directions = fit >= Self.alignedFit ? [.looksGood] : [abs(shift) >= abs(lift) ? (shift > 0 ? .moveLeft : .moveRight) : (lift > 0 ? .moveUp : .moveHandDown)]
        }
        let steadyEnough = !hand.isClearlyTurned
            && tilt <= maxLandmarkTiltDegrees && pipBendDegrees(hand) <= maxPIPBendDegrees
            && abs(scale - 1) <= steadySizeError && abs(shift) <= steadyShiftError && abs(lift) <= steadyShiftError
            && fit >= steadyFit
        return GuidanceResult(fingerLengthFraction: size, centerOffset: offset, tiltDegrees: tilt, directions: directions,
                              fit: fit, steadyEnough: steadyEnough)
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

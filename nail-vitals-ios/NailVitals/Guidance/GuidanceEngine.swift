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

        // TODO: port the fitLine-equivalent tilt calculation from
        // contour_angle.py / guidance_logic.py. Remember the fix we
        // found: fold the raw angle into a true 0-90 deviation from
        // vertical (min(raw, 180 - raw)), since the line direction's
        // sign is ambiguous and raw arctan2 can wrap around near 180
        // degrees for a perfectly vertical finger.
        let tiltDegrees: Double = 0  // placeholder

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
}

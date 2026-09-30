//
//  DetectedSilhouette.swift
//  NailVitals
//
//  A traced finger outline: produced by FingerMaskSegmenter from the
//  subject mask, consumed by AngleAnalyzer and the confirmation screens.
//  Also compiled into Tools/photo-lab and Tools/angle-harness.
//

import CoreGraphics

nonisolated struct DetectedSilhouette {
    let boundingBox: CGRect      // image pixels, top-left origin
    let contourPoints: [CGPoint] // ordered outline points, image pixels
    let imageSize: CGSize
}

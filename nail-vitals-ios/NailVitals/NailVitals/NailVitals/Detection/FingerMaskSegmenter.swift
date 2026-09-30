//
//  FingerMaskSegmenter.swift
//  NailVitals
//
//  Finger outline for the one captured photo, via Apple's foreground
//  ("lift subject") instance mask. The mask is already a clean hand-vs-
//  background separation, so tracing its edge needs no skin-color,
//  light/dark, or shape-rule filtering. Produces the same
//  DetectedSilhouette that AngleAnalyzer consumes.
//

import Vision
import CoreImage

nonisolated final class FingerMaskSegmenter {

    nonisolated struct Diagnostics {
        var instanceCount = 0
        var chosenInstance = 0
        var maskMs: Double = 0
        var contourMs: Double = 0
        var contourPointCount = 0
    }

    private let context = CIContext()
    private(set) nonisolated(unsafe) var lastDiagnostics = Diagnostics()

    /// - Parameter fingertipHint: image-pixel point (top-left origin) that
    ///   should lie on the finger, used to pick the right subject when the
    ///   mask finds more than one.
    func segment(pixelBuffer: CVPixelBuffer, fingertipHint: CGPoint?) -> DetectedSilhouette? {
        var diag = Diagnostics()
        defer { lastDiagnostics = diag }

        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        var start = CFAbsoluteTimeGetCurrent()
        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([maskRequest])
        } catch {
            print("FingerMaskSegmenter: mask request failed: \(error)")
            return nil
        }
        guard let observation = maskRequest.results?.first, !observation.allInstances.isEmpty else { return nil }
        diag.instanceCount = observation.allInstances.count

        let instance = fingertipHint.flatMap { MaskGeometry.instanceLabel(in: observation.instanceMask, at: $0, imageSize: imageSize) }
            ?? observation.allInstances.first!
        diag.chosenInstance = instance

        guard let mask = try? observation.generateScaledMaskForImage(forInstances: IndexSet(integer: instance), from: handler) else {
            return nil
        }
        diag.maskMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        start = CFAbsoluteTimeGetCurrent()
        let maskImage = CIImage(cvPixelBuffer: mask)
        guard let cgMask = context.createCGImage(maskImage, from: maskImage.extent) else { return nil }

        // Full resolution: the default 512 cap would coarsen the outline
        // AngleAnalyzer measures.
        let candidates = MaskGeometry.contours(of: cgMask, maximumDimension: Int(max(imageSize.width, imageSize.height)), imageSize: imageSize)
        diag.contourMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        guard let points = MaskGeometry.pickContour(candidates, containing: fingertipHint) else { return nil }
        diag.contourPointCount = points.count

        return DetectedSilhouette(boundingBox: MaskGeometry.boundingRect(of: points), contourPoints: points, imageSize: imageSize)
    }
}

/// Mask and outline helpers shared by the measurement segmenter and the
/// live outline.
nonisolated enum MaskGeometry {

    /// Reads the low-resolution instance-label mask (0 = background) at an
    /// image point.
    static func instanceLabel(in labels: CVPixelBuffer, at point: CGPoint, imageSize: CGSize) -> Int? {
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(labels) else { return nil }
        let w = CVPixelBufferGetWidth(labels), h = CVPixelBufferGetHeight(labels)
        let x = min(w - 1, max(0, Int(point.x / imageSize.width * CGFloat(w))))
        let y = min(h - 1, max(0, Int(point.y / imageSize.height * CGFloat(h))))
        let value = base.load(fromByteOffset: y * CVPixelBufferGetBytesPerRow(labels) + x, as: UInt8.self)
        return value == 0 ? nil : Int(value)
    }

    /// Outlines of the white regions of a black-and-white mask, in image
    /// pixels (top-left origin) of an image of `imageSize`.
    static func contours(of mask: CGImage, maximumDimension: Int, imageSize: CGSize) -> [[CGPoint]] {
        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = false  // white subject on black
        request.contrastAdjustment = 1.0
        request.maximumImageDimension = maximumDimension
        do {
            try VNImageRequestHandler(cgImage: mask, options: [:]).perform([request])
        } catch {
            print("MaskGeometry: contour request failed: \(error)")
            return []
        }
        return (request.results?.first?.topLevelContours ?? []).map { contour in
            contour.normalizedPoints.map {
                CGPoint(x: CGFloat($0.x) * imageSize.width, y: (1 - CGFloat($0.y)) * imageSize.height)
            }
        }
    }

    /// The outline containing `hint`, else the largest; ignores tiny specks.
    static func pickContour(_ contours: [[CGPoint]], containing hint: CGPoint?) -> [CGPoint]? {
        let candidates = contours.filter { $0.count > 20 }
        return hint.flatMap { h in candidates.first { contains($0, h) } }
            ?? candidates.max { abs(polygonArea($0)) < abs(polygonArea($1)) }
    }

    static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
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

    static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    static func boundingRect(of points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

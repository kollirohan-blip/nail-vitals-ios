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

    /// The finger's outline from a crop around it, in the full photo's
    /// pixels. The mask model works at a fixed, lower resolution, so on the
    /// whole photo the finger's edge came out 2-3 px off and shifted from
    /// run to run, moving the nail angle by up to 4 degrees on the same
    /// photo. Cropped to the finger, the edge sat 1-1.5 px from the real one
    /// and repeat photos of one finger agreed about twice as closely.
    /// nil when the crop is too small or the mask finds nothing in it.
    func segmentAroundFinger(pixelBuffer: CVPixelBuffer, tip: CGPoint, dip: CGPoint, pip: CGPoint, mcp: CGPoint) -> DetectedSilhouette? {
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let crop = Self.fingerCrop(tip: tip, pip: pip, mcp: mcp, imageSize: imageSize)
        guard crop.width >= 64, crop.height >= 64, let cropBuffer = render(pixelBuffer, cropTo: crop),
              let silhouette = segment(pixelBuffer: cropBuffer, fingertipHint: CGPoint(x: dip.x - crop.minX, y: dip.y - crop.minY))
        else { return nil }
        let points = silhouette.contourPoints.map { CGPoint(x: $0.x + crop.minX, y: $0.y + crop.minY) }
        return DetectedSilhouette(boundingBox: MaskGeometry.boundingRect(of: points), contourPoints: points, imageSize: imageSize)
    }

    func segmentAroundFinger(pixelBuffer: CVPixelBuffer, hand: HandLandmarks) -> DetectedSilhouette? {
        segmentAroundFinger(pixelBuffer: pixelBuffer, tip: hand.indexTip.point, dip: hand.indexDIP.point,
                            pip: hand.indexPIP.point, mcp: hand.indexMCP.point)
    }

    /// Around the finger, whichever way it points: from a quarter of its
    /// length past the tip to a quarter past the middle joint, and 0.35 of
    /// its length to each side. Image pixels, top-left origin.
    static func fingerCrop(tip: CGPoint, pip: CGPoint, mcp: CGPoint, imageSize: CGSize) -> CGRect {
        let length = hypot(tip.x - mcp.x, tip.y - mcp.y)
        let span = max(hypot(pip.x - tip.x, pip.y - tip.y), 1)
        let along = CGVector(dx: (pip.x - tip.x) / span, dy: (pip.y - tip.y) / span)
        let across = CGVector(dx: -along.dy, dy: along.dx)
        let ends = [CGPoint(x: tip.x - along.dx * 0.25 * length, y: tip.y - along.dy * 0.25 * length),
                    CGPoint(x: pip.x + along.dx * 0.25 * length, y: pip.y + along.dy * 0.25 * length)]
        let corners = ends.flatMap { end in
            [-0.35, 0.35].map { CGPoint(x: end.x + across.dx * $0 * length, y: end.y + across.dy * $0 * length) }
        }
        return MaskGeometry.boundingRect(of: corners).integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// A copy of part of the photo (crop in top-left-origin pixels).
    private func render(_ buffer: CVPixelBuffer, cropTo crop: CGRect) -> CVPixelBuffer? {
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        // Core Image counts y from the bottom.
        let rect = CGRect(x: crop.minX, y: height - crop.maxY, width: crop.width, height: crop.height)
        let image = CIImage(cvPixelBuffer: buffer).cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        var output: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(crop.width), Int(crop.height), kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &output)
        guard let output else { return nil }
        context.render(image, to: output)
        return output
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

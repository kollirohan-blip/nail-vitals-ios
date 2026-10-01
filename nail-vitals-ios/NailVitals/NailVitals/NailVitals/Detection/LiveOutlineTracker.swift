//
//  LiveOutlineTracker.swift
//  NailVitals
//
//  The live, glowing finger outline shown while framing a capture. Uses the
//  subject mask's low-resolution instance labels directly (fast enough for
//  a few updates a second), keeps only the index finger's part of the
//  outline, and resamples it to a fixed number of points so the overlay can
//  morph smoothly between updates. Display only -- measurement still uses
//  the full-resolution photo (FingerMaskSegmenter + AngleAnalyzer).
//

import Vision
import CoreGraphics

nonisolated struct FingerOutline: Equatable {
    /// `LiveOutlineTracker.pointCount` points along the finger's edge, from
    /// the middle knuckle on one side, round the tip, to the other side.
    /// Image pixels, top-left origin.
    let points: [CGPoint]
    /// Roughly where the cuticle will be measured, on the nail side.
    let cuticle: CGPoint?
    let imageSize: CGSize
}

nonisolated final class LiveOutlineTracker {
    static let pointCount = 64

    private(set) nonisolated(unsafe) var lastDurationMs: Double = 0

    /// The outline of the raised finger, and the joints it belongs to:
    /// hand pose's, or -- when hand pose missed the raised finger or found
    /// no hand -- joints found from the outline (OutlineFingerFinder).
    func outline(in pixelBuffer: CVPixelBuffer, hand visionHand: HandLandmarks?) -> (outline: FingerOutline?, hand: HandLandmarks?) {
        let start = CFAbsoluteTimeGetCurrent()
        defer { lastDurationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000 }

        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:]).perform([request])
        } catch {
            return (nil, visionHand)
        }
        // The hand's subject: where hand pose saw a finger or thumb, else
        // whatever is in the middle of the frame.
        let hints = [visionHand?.indexDIP.point, visionHand?.thumbTip?.point, CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)]
        guard let observation = request.results?.first,
              let (label, hint) = hints.lazy.compactMap({ hint in
                  hint.flatMap { h in MaskGeometry.instanceLabel(in: observation.instanceMask, at: h, imageSize: imageSize).map { ($0, h) } }
              }).first,
              let mask = binaryMask(observation.instanceMask, keeping: label) else { return (nil, visionHand) }

        let contours = MaskGeometry.contours(of: mask, maximumDimension: max(mask.width, mask.height), imageSize: imageSize)
        guard let contour = MaskGeometry.pickContour(contours, containing: hint),
              let hand = OutlineFingerFinder.resolve(visionHand, contour: contour, imageSize: imageSize),
              let arc = fingerArc(contour, hand: hand) else { return (nil, visionHand) }

        let points = resample(smooth(arc), count: Self.pointCount)
        return (FingerOutline(points: points, cuticle: expectedCuticle(on: points, hand: hand), imageSize: imageSize), hand)
    }

    /// White where the label mask equals `label`, black elsewhere.
    private func binaryMask(_ labels: CVPixelBuffer, keeping label: Int) -> CGImage? {
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(labels) else { return nil }
        let w = CVPixelBufferGetWidth(labels), h = CVPixelBufferGetHeight(labels)
        let rowBytes = CVPixelBufferGetBytesPerRow(labels)
        let target = UInt8(truncatingIfNeeded: label)
        var bytes = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w where row[x] == target {
                bytes[y * w + x] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The stretch of the hand outline that belongs to the index finger:
    /// starting at the apex near the fingertip, walk both ways while points
    /// stay beyond the middle knuckle (PIP) and within a finger's width of
    /// the finger's axis.
    private func fingerArc(_ contour: [CGPoint], hand: HandLandmarks) -> [CGPoint]? {
        let tip = hand.indexTip.point, pip = hand.indexPIP.point
        let length = hypot(tip.x - pip.x, tip.y - pip.y)
        guard length > 10, contour.count > 8 else { return nil }
        let axis = CGVector(dx: (tip.x - pip.x) / length, dy: (tip.y - pip.y) / length)
        func along(_ p: CGPoint) -> CGFloat { (p.x - pip.x) * axis.dx + (p.y - pip.y) * axis.dy }
        func across(_ p: CGPoint) -> CGFloat { abs((p.x - pip.x) * axis.dy - (p.y - pip.y) * axis.dx) }
        func onFinger(_ p: CGPoint) -> Bool { along(p) >= 0 && across(p) <= length * 0.35 }

        let nearTip = contour.indices.filter { hypot(contour[$0].x - tip.x, contour[$0].y - tip.y) <= length * 0.6 }
        guard let apex = nearTip.max(by: { along(contour[$0]) < along(contour[$1]) }) else { return nil }

        let n = contour.count
        func point(_ offset: Int) -> CGPoint { contour[((apex + offset) % n + n) % n] }
        var forward: [CGPoint] = [], backward: [CGPoint] = []
        var k = 1
        while k < n / 2, onFinger(point(k)) { forward.append(point(k)); k += 1 }
        k = 1
        while k < n / 2, onFinger(point(-k)) { backward.append(point(-k)); k += 1 }
        let arc = Array(backward.reversed()) + [contour[apex]] + forward
        return arc.count >= 8 ? arc : nil
    }

    /// Moving average over 5 points; the low-res mask outline is stair-stepped.
    private func smooth(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 4 else { return points }
        return points.indices.map { i in
            let window = points[max(0, i - 2)...min(points.count - 1, i + 2)]
            let n = CGFloat(window.count)
            return CGPoint(x: window.reduce(0) { $0 + $1.x } / n, y: window.reduce(0) { $0 + $1.y } / n)
        }
    }

    /// `count` points evenly spaced by arc length along an open polyline.
    private func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > 1, count > 1 else { return Array(repeating: points.first ?? .zero, count: count) }
        var cumulative: [CGFloat] = [0]
        for i in 1..<points.count {
            cumulative.append(cumulative[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
        }
        let total = cumulative.last!
        guard total > 0 else { return Array(repeating: points[0], count: count) }
        var result: [CGPoint] = []
        var segment = 1
        for i in 0..<count {
            let target = total * CGFloat(i) / CGFloat(count - 1)
            while segment < points.count - 1, cumulative[segment] < target { segment += 1 }
            let span = cumulative[segment] - cumulative[segment - 1]
            let t = span > 0 ? (target - cumulative[segment - 1]) / span : 0
            let a = points[segment - 1], b = points[segment]
            result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return result
    }

    /// On the nail side (away from the thumb), the outline point about 0.42
    /// of the way from the fingertip to the DIP joint -- where the cuticle
    /// sat on real side-view captures. nil when the nail side is unknown.
    private func expectedCuticle(on points: [CGPoint], hand: HandLandmarks) -> CGPoint? {
        let tip = hand.indexTip.point, dip = hand.indexDIP.point
        let length = hypot(dip.x - tip.x, dip.y - tip.y)
        guard length > 0 else { return nil }
        let axis = CGVector(dx: (dip.x - tip.x) / length, dy: (dip.y - tip.y) / length)
        func along(_ p: CGPoint) -> CGFloat { (p.x - tip.x) * axis.dx + (p.y - tip.y) * axis.dy }
        let target = length * 0.42
        return points.filter { hand.isOnNailSide($0) == true }
            .min { abs(along($0) - target) < abs(along($1) - target) }
    }
}

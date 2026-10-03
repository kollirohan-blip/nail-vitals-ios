//
//  EdgeSharpness.swift
//  NailVitals
//
//  How sharp the finger's edge is in the photo, around the nail, where the
//  angles are measured. Across each outline point the brightness steps from
//  the finger to the wall: the steepest one-pixel change divided by the
//  whole step is about 1 for a crisp edge and falls as blur spreads it out
//  (0.1 = spread over about 10 px).
//
//  On repeat photos of one finger (Oct 2026), photos held closer than the
//  camera could focus came out soft (0.10-0.15) and read the nail angle
//  about 2-3 degrees high: blur rounds off the dip at the cuticle. Sharp
//  photos (0.25 and up) agreed within about 1 degree.
//

import CoreGraphics
import CoreVideo

nonisolated enum EdgeSharpness {
    /// Below this the photo is too blurry to measure reliably: retake.
    static let minimum = 0.15

    /// Median edge sharpness along the outline from the fingertip to a bit
    /// past the DIP joint; nil if there's too little edge to judge.
    static func measure(contour: [CGPoint], tip: CGPoint, dip: CGPoint, in pixelBuffer: CVPixelBuffer) -> Double? {
        let n = contour.count
        guard n > 10, CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        func luma(_ x: Int, _ y: Int) -> Double {
            let i = y * rowBytes + x * 4   // B, G, R, A
            return 0.114 * Double(bytes[i]) + 0.587 * Double(bytes[i + 1]) + 0.299 * Double(bytes[i + 2])
        }
        func brightness(_ x: Double, _ y: Double) -> Double? {
            let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
            guard xi >= 0, yi >= 0, xi + 1 < width, yi + 1 < height else { return nil }
            let fx = x - Double(xi), fy = y - Double(yi)
            return luma(xi, yi) * (1 - fx) * (1 - fy) + luma(xi + 1, yi) * fx * (1 - fy)
                + luma(xi, yi + 1) * (1 - fx) * fy + luma(xi + 1, yi + 1) * fx * fy
        }

        let reach = Double(hypot(dip.x - tip.x, dip.y - tip.y)) * 1.3
        var ratios: [Double] = []
        for i in stride(from: 0, to: n, by: 2) {
            let p = contour[i]
            guard Double(hypot(p.x - tip.x, p.y - tip.y)) < reach else { continue }
            let a = contour[(i - 3 + n) % n], b = contour[(i + 3) % n]
            let tl = Double(hypot(b.x - a.x, b.y - a.y))
            guard tl > 0 else { continue }
            let nx = -Double(b.y - a.y) / tl, ny = Double(b.x - a.x) / tl
            func sample(_ t: Double) -> Double? { brightness(Double(p.x) + nx * t, Double(p.y) + ny * t) }
            // The whole step: wall vs finger, 8-12 px either side.
            let outer = (8...12).compactMap { sample(Double($0)) }, inner = (8...12).compactMap { sample(-Double($0)) }
            guard outer.count == 5, inner.count == 5 else { continue }
            let step = abs(outer.reduce(0, +) - inner.reduce(0, +)) / 5
            guard step > 15 else { continue }   // too little contrast to judge here
            var steepest = 0.0
            var t = -8.0
            while t <= 8 {
                if let ahead = sample(t + 0.5), let behind = sample(t - 0.5) { steepest = max(steepest, abs(ahead - behind)) }
                t += 0.5
            }
            ratios.append(steepest / step)
        }
        guard ratios.count >= 20 else { return nil }
        return ratios.sorted()[ratios.count / 2]
    }
}

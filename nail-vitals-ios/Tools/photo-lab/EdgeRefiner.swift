//
//  EdgeRefiner.swift
//  NailVitals
//
//  Snaps the finger outline onto the photo's real edge. Apple's subject
//  mask finds the finger reliably, but its outline is made at a lower
//  resolution and shifts a few pixels from run to run and from device to
//  device; near the cuticle that moved the nail angle by up to 4 degrees on
//  the same photo. Here each outline point moves along its normal, at most
//  a few pixels, onto the strongest brightness step (finger against the
//  wall), and the moves are smoothed. On real captures the outline then sat
//  within about 1 px of the edge (was 2-3 px), and the whole-photo and
//  cropped masks gave the same angle to within about half a degree.
//

import CoreGraphics
import CoreVideo

nonisolated enum EdgeRefiner {

    /// - Parameters:
    ///   - contour: outline points in image pixels (top-left origin), in order.
    ///   - pixelBuffer: the photo they came from (32-bit BGRA).
    ///   - reach: how far a point may move, in pixels.
    static func snap(_ contour: [CGPoint], in pixelBuffer: CVPixelBuffer, reach: CGFloat = 6) -> [CGPoint] {
        let n = contour.count
        guard n > 10, CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return contour }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return contour }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        func luma(_ x: Int, _ y: Int) -> CGFloat {
            let i = y * rowBytes + x * 4   // B, G, R, A
            return 0.114 * CGFloat(bytes[i]) + 0.587 * CGFloat(bytes[i + 1]) + 0.299 * CGFloat(bytes[i + 2])
        }
        /// Bilinear brightness at a point; nil off the image.
        func brightness(_ x: CGFloat, _ y: CGFloat) -> CGFloat? {
            let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
            guard xi >= 0, yi >= 0, xi + 1 < width, yi + 1 < height else { return nil }
            let fx = x - CGFloat(xi), fy = y - CGFloat(yi)
            return luma(xi, yi) * (1 - fx) * (1 - fy) + luma(xi + 1, yi) * fx * (1 - fy)
                + luma(xi, yi + 1) * (1 - fx) * fy + luma(xi + 1, yi + 1) * fx * fy
        }

        // Where along each point's normal the brightness changes most.
        var offsets = [CGFloat](repeating: 0, count: n)
        var normals = [CGVector](repeating: CGVector(dx: 0, dy: 0), count: n)
        for i in 0..<n {
            let p = contour[i], a = contour[(i - 3 + n) % n], b = contour[(i + 3) % n]
            let tl = hypot(b.x - a.x, b.y - a.y)
            guard tl > 0 else { continue }
            let normal = CGVector(dx: -(b.y - a.y) / tl, dy: (b.x - a.x) / tl)
            normals[i] = normal
            var best: CGFloat = 0, bestT: CGFloat = 0
            var t = -reach
            while t <= reach {
                if let ahead = brightness(p.x + normal.dx * (t + 1), p.y + normal.dy * (t + 1)),
                   let behind = brightness(p.x + normal.dx * (t - 1), p.y + normal.dy * (t - 1)) {
                    let step = abs(ahead - behind)
                    if step > best { best = step; bestT = t }
                }
                t += 0.5
            }
            // Too faint to be the finger's edge (soft shadow, flat light): stay put.
            offsets[i] = best >= 6 ? bestT : 0
        }

        // Median of 7 drops single-point jumps; mean of 5 keeps the shape smooth.
        var median = offsets
        for i in 0..<n {
            median[i] = (-3...3).map { offsets[(i + $0 + n) % n] }.sorted()[3]
        }
        var smooth = median
        for i in 0..<n {
            smooth[i] = (-2...2).map { median[(i + $0 + n) % n] }.reduce(0, +) / 5
        }
        return (0..<n).map {
            CGPoint(x: contour[$0].x + normals[$0].dx * smooth[$0], y: contour[$0].y + normals[$0].dy * smooth[$0])
        }
    }
}

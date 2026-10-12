//
//  BackgroundContrast.swift
//  NailVitals
//
//  How different the finger looks from what's behind it, around the nail,
//  where the angles are measured: across each outline point, the CIELAB
//  colour 8-12 px inside the finger against 8-12 px outside it (CIE76
//  colour difference, delta E). A plain light wall is far from skin colour;
//  a skin-coloured background (a wooden table, a beige wall) is not, and
//  then the subject mask's edge wanders: on Oct 5 a wood-table session read
//  the same finger 3.5 degrees apart between phone and Mac.
//  Same sampling as EdgeSharpness.
//

import CoreGraphics
import CoreVideo

nonisolated enum BackgroundContrast {
    /// Below this, ask for a plainer background: retake. On saved captures
    /// the Oct 5 wood-table session scored 20.5-23.0 (readings 160-166 for
    /// a finger that reads ~166 on a wall), and two Sep 30 photos at 23.2
    /// and 23.6 read a false 174; every plain-wall capture scored 25.6 or
    /// more.
    static let minimum = 24.0

    /// Median colour difference (delta E) between the finger and its
    /// background along the outline from the fingertip to a bit past the
    /// DIP joint; nil if there's too little outline to judge.
    static func measure(contour: [CGPoint], tip: CGPoint, dip: CGPoint, in pixelBuffer: CVPixelBuffer) -> Double? {
        let n = contour.count
        guard n > 10, CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        /// Mean CIELAB colour of the pixels at the given points.
        func meanLab(_ points: [(Double, Double)]) -> NailColorAnalyzer.Lab? {
            var l = 0.0, a = 0.0, b = 0.0, count = 0.0
            for (x, y) in points {
                let xi = Int(x.rounded()), yi = Int(y.rounded())
                guard xi >= 0, yi >= 0, xi < width, yi < height else { return nil }
                let i = yi * rowBytes + xi * 4   // B, G, R, A
                let c = NailColorAnalyzer.lab(r: bytes[i + 2], g: bytes[i + 1], b: bytes[i])
                l += c.l; a += c.a; b += c.b; count += 1
            }
            return count > 0 ? NailColorAnalyzer.Lab(l: l / count, a: a / count, b: b / count) : nil
        }

        let reach = Double(hypot(dip.x - tip.x, dip.y - tip.y)) * 1.3
        var differences: [Double] = []
        for i in stride(from: 0, to: n, by: 2) {
            let p = contour[i]
            guard Double(hypot(p.x - tip.x, p.y - tip.y)) < reach else { continue }
            let a = contour[(i - 3 + n) % n], b = contour[(i + 3) % n]
            let tl = Double(hypot(b.x - a.x, b.y - a.y))
            guard tl > 0 else { continue }
            let nx = -Double(b.y - a.y) / tl, ny = Double(b.x - a.x) / tl
            let side1 = (8...12).map { (Double(p.x) + nx * Double($0), Double(p.y) + ny * Double($0)) }
            let side2 = (8...12).map { (Double(p.x) - nx * Double($0), Double(p.y) - ny * Double($0)) }
            guard let c1 = meanLab(side1), let c2 = meanLab(side2) else { continue }
            differences.append(((c1.l - c2.l) * (c1.l - c2.l) + (c1.a - c2.a) * (c1.a - c2.a) + (c1.b - c2.b) * (c1.b - c2.b)).squareRoot())
        }
        guard differences.count >= 20 else { return nil }
        return differences.sorted()[differences.count / 2]
    }
}

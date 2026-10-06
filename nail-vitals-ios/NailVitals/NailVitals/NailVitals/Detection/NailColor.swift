//
//  NailColor.swift
//  NailVitals
//
//  Phase 2 prototype: the color profile along a fingernail seen from the
//  top, for Terry's nails (nail mostly white, with a 0.5-3 mm pink-to-brown
//  band at the tip; Holzberg & Walker 1984) and half-and-half / Lindsay's
//  nails (proximal part white, distal part red, pink or brown, with a sharp
//  line between; Lindsay 1967). Samples a central strip along the finger
//  from the DIP joint past the tip, in CIELAB (L* lightness, a* redness,
//  b* yellowness). Only relative color within one nail is meaningful:
//  lighting and skin tone shift absolute values.
//
//  Plain geometry and color, so Tools/photo-lab can run it on photos.
//

import CoreGraphics
import Foundation

/// An RGBA copy of an image for sampling colors.
nonisolated struct RGBAImage {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = data
    }

    /// CIELAB color at an image point (top-left origin), or nil outside.
    func lab(at p: CGPoint) -> NailColorAnalyzer.Lab? {
        let x = Int(p.x.rounded()), y = Int(p.y.rounded())
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        // The bitmap's first row is the image's top row.
        let i = (y * width + x) * 4
        return NailColorAnalyzer.lab(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2])
    }
}

nonisolated enum NailColorAnalyzer {

    nonisolated struct Lab {
        let l: Double
        let a: Double
        let b: Double
        var chroma: Double { (a * a + b * b).squareRoot() }
    }

    nonisolated struct Sample {
        /// Position along the finger: 0 at the DIP joint, 1 at the tip joint.
        let along: Double
        let color: Lab
    }

    /// Median color of a central strip (`stripFraction` of the finger's
    /// width) at each step along the finger, from the DIP joint to `reach`
    /// tip-to-DIP lengths. The finger's width comes from the hand outline
    /// when there is one, otherwise half the tip-to-DIP length.
    static func profile(_ image: RGBAImage, tip: CGPoint, dip: CGPoint, outline: [CGPoint]?,
                        reach: Double = 1.6, steps: Int = 160, stripFraction: CGFloat = 0.4) -> [Sample] {
        guard let frame = FingerSignsAnalyzer.FingerFrame(tip: tip, dip: dip) else { return [] }
        var samples: [Sample] = []
        for i in 0...steps {
            let along = reach * Double(i) / Double(steps)
            let level = frame.length * CGFloat(along)
            var center: CGFloat = 0, width = frame.length * 0.5
            if let outline,
               let left = FingerSignsAnalyzer.edgePoint(outline, frame, at: level, side: -1),
               let right = FingerSignsAnalyzer.edgePoint(outline, frame, at: level, side: 1) {
                let l = frame.across(left), r = frame.across(right)
                center = (l + r) / 2
                width = r - l
            } else if outline != nil {
                continue  // past the fingertip: nothing to sample
            }
            var colors: [Lab] = []
            for k in 0..<9 {
                let across = center + width * stripFraction * (CGFloat(k) / 8 - 0.5)
                if let c = image.lab(at: frame.point(along: level, across: across)) { colors.append(c) }
            }
            guard colors.count >= 5 else { continue }
            samples.append(Sample(along: along, color: Lab(l: median(colors.map(\.l)), a: median(colors.map(\.a)), b: median(colors.map(\.b)))))
        }
        return samples
    }

    // MARK: - One nail, along a line placed on it

    /// Color along one nail from `start` (where the nail meets the skin at
    /// the cuticle) to `end` (where the pink ends, before the white free
    /// edge): at each step the median of a short strip across the nail, a
    /// quarter of the line's length wide. `along` runs 0 to 1.
    static func nailProfile(_ image: RGBAImage, from start: CGPoint, to end: CGPoint, steps: Int = 40) -> [Sample] {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 4 else { return [] }
        let ux = (end.x - start.x) / length, uy = (end.y - start.y) / length
        var samples: [Sample] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            var colors: [Lab] = []
            for k in 0..<7 {
                let off = length * 0.25 * (CGFloat(k) / 6 - 0.5)
                let p = CGPoint(x: start.x + ux * length * t - uy * off, y: start.y + uy * length * t + ux * off)
                if let c = image.lab(at: p) { colors.append(c) }
            }
            guard colors.count >= 4 else { continue }
            samples.append(Sample(along: Double(t), color: Lab(l: median(colors.map(\.l)), a: median(colors.map(\.a)), b: median(colors.map(\.b)))))
        }
        return samples
    }

    /// What one nail's color profile looks like.
    nonisolated struct NailPattern {
        enum Kind {
            /// About the same color from base to tip.
            case even
            /// Pink with a pale part only at the base: the usual half-moon (lunula).
            case usual
            /// A pale nail with a darker (pink to brown) band at the tip: the
            /// pattern of Terry's and half-and-half nails.
            case paleWithBand
            /// Color changes, but not as one pale part then one band.
            case unclear
        }
        let kind: Kind
        /// The band's share of the nail, from the cuticle to where the pink ends.
        var bandShare: Double? = nil
        /// Where the pale part ends and where the pink ends, 0-1 along the placed line.
        var split: Double? = nil
        var pinkEnd: Double? = nil
        /// Redness (CIELAB a*) of the pale part and of the band.
        var paleRedness: Double? = nil
        var bandRedness: Double? = nil
    }

    /// Smallest redness step (a*) between the pale part and the band that
    /// counts. On the example photos the step was 8-20; across an evenly
    /// colored nail it stays within a few units.
    static let minimumRednessStep = 6.0
    /// A band covering this much of the nail or more means only the base is
    /// pale: the usual half-moon, not a pale nail.
    static let usualBandShare = 0.7
    /// Below this share the band is narrow (Terry's-like); above, toward
    /// half (half-and-half-like). The app's own dividing line for wording,
    /// not a published cut-off.
    static let narrowBandShare = 0.35

    /// Fits "pale, then a redder band" to the nail's redness (a*): the split
    /// that best divides it into two levels. The white free edge past the
    /// pink is left out, and so is the cuticle fold itself.
    static func pattern(_ samples: [Sample]) -> NailPattern {
        let points = samples.filter { $0.along >= 0.05 }
        guard points.count >= 12 else { return NailPattern(kind: .unclear) }
        let raw = points.map(\.color.a)
        let a = raw.indices.map { median(Array(raw[max(0, $0 - 1)...min(raw.count - 1, $0 + 1)])) }
        let sorted = a.sorted()
        let lo = sorted[sorted.count / 10], hi = sorted[sorted.count * 9 / 10]
        guard hi - lo >= minimumRednessStep else { return NailPattern(kind: .even) }

        // The pink ends at the last clearly red point; past it is the free edge.
        let middle = (lo + hi) / 2
        guard let last = a.lastIndex(where: { $0 >= middle }), last >= 7 else { return NailPattern(kind: .unclear) }
        let bed = Array(a[0...last])
        func mean(_ v: ArraySlice<Double>) -> Double { v.reduce(0, +) / Double(v.count) }
        func spread(_ v: ArraySlice<Double>) -> Double { let m = mean(v); return v.reduce(0) { $0 + ($1 - m) * ($1 - m) } }

        var best: (k: Int, sse: Double)?
        for k in 3...(bed.count - 2) where mean(bed[k...]) > mean(bed[..<k]) {
            let sse = spread(bed[..<k]) + spread(bed[k...])
            if best == nil || sse < best!.sse { best = (k, sse) }
        }
        let total = spread(bed[...])
        guard let best, total > 0 else { return NailPattern(kind: .even) }
        let pale = mean(bed[..<best.k]), band = mean(bed[best.k...])
        guard band - pale >= minimumRednessStep else { return NailPattern(kind: .even) }
        // A clean two-level step explains most of the variation; stripes or
        // blotches (Mees' lines, glare) don't.
        let split = (points[best.k - 1].along + points[best.k].along) / 2
        let pinkEnd = points[last].along
        let share = (pinkEnd - split) / pinkEnd
        guard 1 - best.sse / total >= 0.6 else {
            return NailPattern(kind: .unclear, split: split, pinkEnd: pinkEnd)
        }
        return NailPattern(kind: share >= usualBandShare ? .usual : .paleWithBand, bandShare: share,
                           split: split, pinkEnd: pinkEnd, paleRedness: pale, bandRedness: band)
    }

    // MARK: - Color

    /// sRGB (D65) to CIELAB.
    static func lab(r: UInt8, g: UInt8, b: UInt8) -> Lab {
        func linear(_ v: UInt8) -> Double {
            let c = Double(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rl = linear(r), gl = linear(g), bl = linear(b)
        let x = (0.4124 * rl + 0.3576 * gl + 0.1805 * bl) / 0.95047
        let y = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
        let z = (0.0193 * rl + 0.1192 * gl + 0.9505 * bl) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3) : 7.787 * t + 16.0 / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return Lab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

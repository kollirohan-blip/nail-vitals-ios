//
//  SchamrothWindow.swift
//  NailVitals
//
//  Schamroth's window test (beta). With the backs of the two index
//  fingertips pressed together, nail to nail, a small diamond-shaped gap
//  normally shows between the nail beds; in clubbing it is gone (Schamroth,
//  S Afr Med J 1976).
//
//  The window is background showing through, completely surrounded by
//  skin. The subject mask can't be used for it directly: on rendered pairs
//  of the healthy model finger it filled in even a 28 px (0.9 mm) window.
//  So the mask only teaches the colours (skin vs. background); every pixel
//  is then sorted by colour, the background is flooded in from the photo's
//  edges, and background-coloured patches the flood can't reach are
//  enclosed gaps. With both index fingers from hand pose, only a gap on the
//  line where the two fingers meet, between their last joints and tips,
//  counts as the window. When none is found the user can tap the gap, and
//  it's traced by colour from there (`traceTapped`).
//

import Vision
import CoreImage

nonisolated struct SchamrothWindow: Equatable {
    /// The gap's outline, image pixels (top-left origin).
    let outline: [CGPoint]
    /// Along its longest direction and across it, image pixels.
    let length: CGFloat
    let width: CGFloat
    let area: CGFloat
    /// Found by the user's tap rather than automatically.
    var fromTap = false

    var center: CGPoint {
        CGPoint(x: outline.map(\.x).reduce(0, +) / CGFloat(max(outline.count, 1)),
                y: outline.map(\.y).reduce(0, +) / CGFloat(max(outline.count, 1)))
    }

    /// - Parameters:
    ///   - outline: boundary points, any order around the centre.
    ///   - area: pixel count when known; otherwise the outline's area.
    init?(outline: [CGPoint], area: CGFloat? = nil, fromTap: Bool = false) {
        guard outline.count >= 3 else { return nil }
        let n = CGFloat(outline.count)
        let mx = outline.map(\.x).reduce(0, +) / n, my = outline.map(\.y).reduce(0, +) / n
        self.outline = outline.sorted { atan2($0.y - my, $0.x - mx) < atan2($1.y - my, $1.x - mx) }
        self.fromTap = fromTap
        self.area = area ?? abs(MaskGeometry.polygonArea(self.outline))
        // Longest and shortest extent along the points' principal axes.
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in outline { sxx += (p.x - mx) * (p.x - mx); syy += (p.y - my) * (p.y - my); sxy += (p.x - mx) * (p.y - my) }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let ax = CGVector(dx: cos(angle), dy: sin(angle))
        let along = outline.map { ($0.x - mx) * ax.dx + ($0.y - my) * ax.dy }
        let across = outline.map { -($0.x - mx) * ax.dy + ($0.y - my) * ax.dx }
        length = (along.max() ?? 0) - (along.min() ?? 0)
        width = (across.max() ?? 0) - (across.min() ?? 0)
    }
}

nonisolated enum SchamrothFinder {

    nonisolated struct Result {
        /// The window, when one was found.
        var window: SchamrothWindow?
        /// Index fingers hand pose found (the test needs both).
        var indexFingers: [FingerChain] = []
        /// Where the fingers meet: from between their last joints to
        /// between their tips. nil without two index fingers.
        var contactLine: (from: CGPoint, to: CGPoint)?
        /// Every enclosed background-coloured gap, before choosing.
        var gaps: [SchamrothWindow] = []
        /// Typical finger thickness near the tips, image pixels.
        var fingerWidth: CGFloat?
    }

    /// Smallest gap counted, as a share of the finger's thickness (or of
    /// the image's short side without hand pose): a few stray pixels
    /// aren't a window.
    static let minLengthFraction: CGFloat = 0.08
    /// Longest side of the copy the colours are sorted on.
    static let workingSize: CGFloat = 1400
    /// Background seen through a gap matches the background colour: within
    /// this share of the skin-to-background difference. Pixels that are only
    /// "closer to background than to skin" connect regions but don't make a
    /// gap on their own: as gaps they let shine on nails and knuckles
    /// through (12-33 per photo on saved side-view captures), and as walls
    /// shaded background boxed in fake gaps (88 on one photo).
    static var wallMatch = 0.5
    /// Weight of lightness in that match: a gap is often in the fingers'
    /// shadow (darker, same tint), while shine on skin keeps its pink tint.
    static var lightnessWeight = 0.5
    /// Share of a gap's pixels that must match the background colour.
    static let minWallShare = 0.5

    /// - Parameter requireBothFingers: only call a gap the window when hand
    ///   pose found both index fingers (the app); false for test renders,
    ///   which have no hands to find.
    static func find(in pixelBuffer: CVPixelBuffer, requireBothFingers: Bool = true) -> Result {
        var result = Result()
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))

        // Both index fingers: the window sits where they meet.
        let hands = HandPoseDetector().detectFingers(in: pixelBuffer, maxHands: 2)
        result.indexFingers = hands.compactMap { $0.first { $0.name == .index } }
        if result.indexFingers.count == 2 {
            let a = result.indexFingers[0], b = result.indexFingers[1]
            func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
            result.contactLine = (mid(a.dip.point, b.dip.point), mid(a.tip.point, b.tip.point))
            let length = [a, b].map { hypot($0.tip.point.x - $0.dip.point.x, $0.tip.point.y - $0.dip.point.y) }.max() ?? 0
            // Seen from the side, a finger is about 1.8 times as long from
            // the last joint to the tip as it is thick (P1: 25.0 mm, 14.0 mm).
            result.fingerWidth = length / 1.8
        }

        // Skin and background colours from the subject mask.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first,
              let mask = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        else { return result }
        let scale = min(1, workingSize / max(imageSize.width, imageSize.height))
        let w = Int(imageSize.width * scale), h = Int(imageSize.height * scale)
        let context = CIContext()
        guard let photo = rgba(CIImage(cvPixelBuffer: pixelBuffer), width: w, height: h, context: context),
              let maskPixels = rgba(CIImage(cvPixelBuffer: mask), width: w, height: h, context: context) else { return result }
        let gaps = enclosedBackground(photo: photo, mask: maskPixels, width: w, height: h)
        result.gaps = gaps.compactMap { gap in
            SchamrothWindow(outline: gap.boundary.map { CGPoint(x: $0.x / scale, y: $0.y / scale) },
                            area: CGFloat(gap.count) / (scale * scale))
        }

        let reference = result.fingerWidth ?? min(imageSize.width, imageSize.height) * 0.1
        var candidates = result.gaps.filter { $0.length >= reference * minLengthFraction }
        if let line = result.contactLine, let thickness = result.fingerWidth {
            // On the line where the fingers meet, between joints and tips.
            candidates = candidates.filter { distance($0.center, toSegment: line.from, line.to) < thickness * 0.6 }
        } else if requireBothFingers {
            candidates = []
        }
        result.window = candidates.max { $0.area < $1.area }
        return result
    }

    /// Background-coloured patches the background can't reach from the
    /// photo's edges, in working-copy pixels: each one's pixel count and
    /// boundary pixels.
    static func enclosedBackground(photo: [UInt8], mask: [UInt8], width w: Int, height h: Int) -> [(count: Int, boundary: [CGPoint])] {
        func lab(_ i: Int) -> NailColorAnalyzer.Lab {
            NailColorAnalyzer.lab(r: photo[i * 4], g: photo[i * 4 + 1], b: photo[i * 4 + 2])
        }
        // Median skin and background colour, sampled from the mask.
        var fg: [NailColorAnalyzer.Lab] = [], bg: [NailColorAnalyzer.Lab] = []
        for y in stride(from: 0, to: h, by: 4) { for x in stride(from: 0, to: w, by: 4) {
            let i = y * w + x
            if mask[i * 4] > 200 { fg.append(lab(i)) } else if mask[i * 4] < 50 { bg.append(lab(i)) }
        } }
        guard fg.count > 20, bg.count > 20 else { return [] }
        func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
        let skin = (median(fg.map(\.l)), median(fg.map(\.a)), median(fg.map(\.b)))
        let wall = (median(bg.map(\.l)), median(bg.map(\.a)), median(bg.map(\.b)))
        func d(_ c: NailColorAnalyzer.Lab, _ m: (Double, Double, Double)) -> Double {
            ((c.l - m.0) * (c.l - m.0) + (c.a - m.1) * (c.a - m.1) + (c.b - m.2) * (c.b - m.2)).squareRoot()
        }
        // 1 = closer to the background than to skin, 0 = skin; `matches`:
        // the background colour itself.
        let limit = wallMatch * d(NailColorAnalyzer.Lab(l: skin.0, a: skin.1, b: skin.2), wall)
        var cls = [UInt8](repeating: 0, count: w * h)
        var matches = [Bool](repeating: false, count: w * h)
        func tintWeighted(_ c: NailColorAnalyzer.Lab) -> Double {
            let dl = (c.l - wall.0) * lightnessWeight
            return (dl * dl + (c.a - wall.1) * (c.a - wall.1) + (c.b - wall.2) * (c.b - wall.2)).squareRoot()
        }
        for i in 0..<(w * h) {
            let c = lab(i)
            if d(c, wall) < d(c, skin) { cls[i] = 1 }
            matches[i] = tintWeighted(c) < limit
        }

        // Flood the background in from the edges (2 = reached).
        var stack: [Int] = []
        for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
        for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
        while let i = stack.popLast() {
            guard cls[i] == 1 else { continue }
            cls[i] = 2
            let x = i % w, y = i / w
            if x > 0 { stack.append(i - 1) }; if x < w - 1 { stack.append(i + 1) }
            if y > 0 { stack.append(i - w) }; if y < h - 1 { stack.append(i + w) }
        }
        // What's left at 1 is enclosed: group it into patches.
        var gaps: [(count: Int, boundary: [CGPoint])] = []
        for start in 0..<(w * h) where cls[start] == 1 {
            var count = 0, matching = 0, boundary: [CGPoint] = []
            stack = [start]
            while let i = stack.popLast() {
                guard cls[i] == 1 else { continue }
                cls[i] = 3
                count += 1
                if matches[i] { matching += 1 }
                let x = i % w, y = i / w
                var edge = false
                for j in [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1] {
                    if j < 0 { continue }
                    if cls[j] == 1 { stack.append(j) } else if cls[j] == 0 { edge = true }
                }
                if edge { boundary.append(CGPoint(x: x, y: y)) }
            }
            if count >= 6, boundary.count >= 3, Double(matching) >= minWallShare * Double(count) { gaps.append((count, boundary)) }
        }
        return gaps
    }

    /// The gap the user tapped, traced by colour: every pixel connected to
    /// the tap whose colour is within `tolerance` (CIELAB delta E) of the
    /// tapped colour, inside a box `reach` pixels around the tap. nil when
    /// the region runs out of the box (it isn't closed off: that's open
    /// background, not a window) or is too small.
    static func traceTapped(_ image: RGBAImage, at tap: CGPoint, reach: CGFloat, tolerance: Double = 12) -> SchamrothWindow? {
        guard let seed = image.lab(at: tap) else { return nil }
        let x0 = max(0, Int(tap.x - reach)), x1 = min(image.width - 1, Int(tap.x + reach))
        let y0 = max(0, Int(tap.y - reach)), y1 = min(image.height - 1, Int(tap.y + reach))
        let w = x1 - x0 + 1, h = y1 - y0 + 1
        guard w > 2, h > 2 else { return nil }
        var inside = [Bool](repeating: false, count: w * h)
        var stack = [(Int(tap.x) - x0, Int(tap.y) - y0)]
        var count = 0
        while let (x, y) = stack.popLast() {
            guard x >= 0, y >= 0, x < w, y < h, !inside[y * w + x] else { continue }
            guard let c = image.lab(at: CGPoint(x: x + x0, y: y + y0)) else { continue }
            let d = ((c.l - seed.l) * (c.l - seed.l) + (c.a - seed.a) * (c.a - seed.a) + (c.b - seed.b) * (c.b - seed.b)).squareRoot()
            guard d <= tolerance else { continue }
            // Reaching the box's edge: the region is open to the background.
            if x == 0 || y == 0 || x == w - 1 || y == h - 1 { return nil }
            inside[y * w + x] = true
            count += 1
            stack.append(contentsOf: [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
        }
        guard count >= 12 else { return nil }
        var boundary: [CGPoint] = []
        for y in 0..<h { for x in 0..<w where inside[y * w + x] {
            let edge = x == 0 || y == 0 || !inside[y * w + x - 1] || !inside[y * w + x + 1] || !inside[(y - 1) * w + x] || !inside[(y + 1) * w + x]
            if edge { boundary.append(CGPoint(x: x + x0, y: y + y0)) }
        } }
        return SchamrothWindow(outline: boundary, area: CGFloat(count), fromTap: true)
    }

    /// RGBA bytes of an image scaled to width x height, first row = top.
    private static func rgba(_ image: CIImage, width: Int, height: Int, context: CIContext) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width,
                                                             y: CGFloat(height) / image.extent.height))
        guard let cg = context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: width, height: height)),
              let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / max(dx * dx + dy * dy, 1e-9)))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

// Synthetic-finger regression test for AngleAnalyzer. Run from this folder:
//   swiftc -O ../../NailVitals/NailVitals/NailVitals/Detection/AngleAnalyzer.swift main.swift -o /tmp/angle-harness && /tmp/angle-harness
import CoreGraphics
import Foundation

// Stand-in for the app's struct (the real one lives in a UIKit/Vision file).
struct DetectedSilhouette {
    let boundingBox: CGRect
    let contourPoints: [CGPoint]
    let imageSize: CGSize
}

let imageSize = CGSize(width: 1080, height: 1920)

/// Synthetic finger pointing up, seen in profile, image coords (y down).
/// Rounded tip, straight nail plate on the right, then the skin fold bends so the
/// OUTSIDE angle between nail plate and skin fold is `outsideAngle` degrees.
func makeFinger(outsideAngle: Double, tipRadius: CGFloat = 80, nailLength: CGFloat = 150)
    -> (points: [CGPoint], cuticleIndex: Int) {
    let cx: CGFloat = 540, cy: CGFloat = 680
    let r = tipRadius
    var pts: [CGPoint] = []

    func line(_ a: CGPoint, _ b: CGPoint) {
        let n = max(1, Int(hypot(b.x - a.x, b.y - a.y)))
        for i in 1...n {
            let t = CGFloat(i) / CGFloat(n)
            pts.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
    }
    func arc(from t0: Double, to t1: Double) {
        let n = Int(abs(t1 - t0) * Double(r))
        for i in 0...n {
            let t = t0 + (t1 - t0) * Double(i) / Double(n)
            pts.append(CGPoint(x: cx + r * CGFloat(cos(t)), y: cy + r * CGFloat(sin(t))))
        }
    }

    arc(from: -.pi / 2, to: 0)                           // top of tip -> right side
    let nailTop = CGPoint(x: cx + r, y: cy)
    let cuticle = CGPoint(x: cx + r, y: cy + nailLength)
    line(nailTop, cuticle)                                // nail plate
    let cuticleIndex = pts.count - 1
    let phi = (180 - outsideAngle) * .pi / 180            // >0 tilts outward (concave, normal)
    let skinEnd = CGPoint(x: cuticle.x + 300 * CGFloat(sin(phi)), y: cuticle.y + 300 * CGFloat(cos(phi)))
    line(cuticle, skinEnd)                                // proximal nail fold / skin
    line(skinEnd, CGPoint(x: skinEnd.x, y: 1700))
    line(CGPoint(x: skinEnd.x, y: 1700), CGPoint(x: cx - r, y: 1700))
    line(CGPoint(x: cx - r, y: 1700), CGPoint(x: cx - r, y: cy))
    arc(from: .pi, to: 1.5 * .pi)                         // left side -> back to top
    pts.removeLast()                                      // avoid duplicating the start point
    return (pts, cuticleIndex)
}

struct Variant { let name: String; let mirror: Bool; let reverse: Bool; let rotate: Int }
let variants = [
    Variant(name: "nail R, cw ", mirror: false, reverse: false, rotate: 0),
    Variant(name: "nail R, ccw", mirror: false, reverse: true, rotate: 0),
    Variant(name: "nail L, cw ", mirror: true, reverse: true, rotate: 0),
    Variant(name: "nail L, ccw", mirror: true, reverse: false, rotate: 0),
    Variant(name: "nail R, rot", mirror: false, reverse: false, rotate: 777),
]

func apply(_ v: Variant, _ pts: [CGPoint], _ cut: Int) -> ([CGPoint], Int) {
    var p = pts, c = cut
    if v.mirror { p = p.map { CGPoint(x: imageSize.width - $0.x, y: $0.y) } }
    if v.reverse { p.reverse(); c = p.count - 1 - c }
    if v.rotate > 0 {
        let k = v.rotate % p.count
        p = Array(p[k...] + p[..<k]); c = (c - k + p.count) % p.count
    }
    return (p, c)
}

let analyzer = AngleAnalyzer()
var worstMath = 0.0, worstFull = 0.0
print("true  variant       math@cuticle  full-analyze(nail side)  marker-err  other-side")
for truth in [150.0, 160.0, 170.0, 180.0, 190.0, 200.0] {
    let (base, baseCut) = makeFinger(outsideAngle: truth)
    for v in variants {
        let (pts, cut) = apply(v, base, baseCut)
        let n = pts.count
        let sil = DetectedSilhouette(boundingBox: .zero, contourPoints: pts, imageSize: imageSize)
        guard let result = analyzer.analyze(sil) else { print("\(truth) \(v.name) analyze=nil"); continue }
        let fwd = (cut - result.tipIndex + n) % n
        let nailStep = fwd < n / 2 ? 1 : -1
        let math = analyzer.recomputeAngle(points: pts, tipIndex: result.tipIndex, userConfirmedIndex: cut,
                                           step: nailStep, segmentLengthPixels: result.segmentLengthPixels) ?? .nan
        let nailCand = result.candidates.first { $0.step == nailStep }
        let other = result.candidates.first { $0.step != nailStep }
        let err = nailCand.map { hypot($0.inflectionPoint.x - pts[cut].x, $0.inflectionPoint.y - pts[cut].y) } ?? .nan
        worstMath = max(worstMath, abs(math - truth))
        if let a = nailCand?.angleDegrees { worstFull = max(worstFull, abs(a - truth)) }
        print(String(format: "%5.0f %@   %8.1f       %8.1f                %6.1fpx    %6.1f",
                     truth, v.name, math, nailCand?.angleDegrees ?? .nan, err, other?.angleDegrees ?? .nan))
    }
}
print(String(format: "\nworst error: angle math at true cuticle = %.1f deg, full analyze = %.1f deg", worstMath, worstFull))

// MARK: - Realistic stress test: jagged outline, curved nail, different finger sizes
struct LCG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }
var rng = LCG(s: 42)
func gauss() -> CGFloat { CGFloat(sqrt(-2 * log(max(rng.next(), 1e-12))) * cos(2 * .pi * rng.next())) }

func makeRealistic(outsideAngle: Double, r: CGFloat, nailCurveDeg: Double, noise: CGFloat, nailFactor: CGFloat = 1.9) -> ([CGPoint], Int) {
    let cx: CGFloat = 540, cy: CGFloat = 680
    let nailLength = r * nailFactor
    var pts: [CGPoint] = []
    var cur = CGPoint(x: cx, y: cy - r)
    let na = Int(Double.pi / 2 * Double(r))
    for i in 0...na { let t = -Double.pi / 2 + Double.pi / 2 * Double(i) / Double(na)
        pts.append(CGPoint(x: cx + r * CGFloat(cos(t)), y: cy + r * CGFloat(sin(t)))) }
    // curved nail plate: heading goes from `nailCurveDeg` inward to exactly vertical at the cuticle
    cur = pts.last!
    let nn = Int(nailLength)
    for i in 1...nn {
        let h = nailCurveDeg * (1 - Double(i) / Double(nn)) * .pi / 180
        cur = CGPoint(x: cur.x - CGFloat(sin(h)), y: cur.y + CGFloat(cos(h)))
        pts.append(cur)
    }
    let cut = pts.count - 1
    let phi = (180 - outsideAngle) * .pi / 180
    for _ in 1...Int(r * 3.5) { cur = CGPoint(x: cur.x + CGFloat(sin(phi)), y: cur.y + CGFloat(cos(phi))); pts.append(cur) }
    let bx = cur.x
    while cur.y < 1700 { cur.y += 1; pts.append(cur) }
    while cur.x > cx - r { cur.x -= 1; pts.append(cur) }
    while cur.y > cy { cur.y -= 1; pts.append(cur) }
    for i in 0..<na { let t = Double.pi + Double.pi / 2 * Double(i) / Double(na)
        pts.append(CGPoint(x: cx + r * CGFloat(cos(t)), y: cy + r * CGFloat(sin(t)))) }
    _ = bx
    // jitter, then snap to whole pixels like a traced mask
    let jagged = pts.map { CGPoint(x: ($0.x + gauss() * noise).rounded(), y: ($0.y + gauss() * noise).rounded()) }
    return (jagged, cut)
}

print("\nSTRESS (jagged ±\(1.0)px, nail curved 8°, 20 trials each) -- full automatic analyze, nail side")
print("r/nail   true   mean   worst-err  marker-err(mean)  found   math@true-cuticle worst-err")
for (r, nf) in [(CGFloat(80), CGFloat(1.2)), (80, 1.9), (80, 2.5), (110, 1.2), (110, 1.9), (140, 1.5)] {
    for truth in [150.0, 160.0, 170.0, 180.0, 190.0, 200.0] {
        var errs: [Double] = [], markErr: [Double] = [], mathErr: [Double] = [], found = 0
        for _ in 0..<20 {
            let (pts, cut) = makeRealistic(outsideAngle: truth, r: r, nailCurveDeg: 8, noise: 1.0, nailFactor: nf)
            let n = pts.count
            let sil = DetectedSilhouette(boundingBox: .zero, contourPoints: pts, imageSize: imageSize)
            guard let res = analyzer.analyze(sil) else { continue }
            let step = ((cut - res.tipIndex + n) % n) < n / 2 ? 1 : -1
            guard let c = res.candidates.first(where: { $0.step == step }) else { continue }
            found += 1
            if let m = analyzer.recomputeAngle(points: pts, tipIndex: res.tipIndex, userConfirmedIndex: cut, step: step, segmentLengthPixels: res.segmentLengthPixels) { mathErr.append(abs(m - truth)) }
            errs.append(c.angleDegrees - truth)
            markErr.append(Double(hypot(c.inflectionPoint.x - pts[cut].x, c.inflectionPoint.y - pts[cut].y)))
        }
        let mean = errs.isEmpty ? .nan : errs.reduce(0, +) / Double(errs.count) + truth
        let worst = errs.map { abs($0) }.max() ?? .nan
        let mk = markErr.isEmpty ? .nan : markErr.reduce(0, +) / Double(markErr.count)
        print(String(format: "%3.0f/%3.1f  %5.0f  %6.1f   %6.1f      %6.1fpx          %d/20     %6.1f", Double(r), Double(nf), truth, mean, worst, mk, found, mathErr.max() ?? .nan))
    }
}

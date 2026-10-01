// Synthetic-finger regression test for AngleAnalyzer. Run from this folder:
//   swiftc -O ../../NailVitals/NailVitals/NailVitals/Detection/{DetectedSilhouette,AngleAnalyzer,FingerSigns,ClubbingAssessment}.swift main.swift -o angle-harness && ./angle-harness
import CoreGraphics
import Foundation


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

var lastDIP = CGPoint.zero  // where a hand-pose DIP joint would sit for the last generated finger
func makeRealistic(outsideAngle: Double, r: CGFloat, nailCurveDeg: Double, noise: CGFloat, nailFactor: CGFloat = 1.9,
                   taper: CGFloat = 1.0, cuticleFractionOfDIP: CGFloat = 0.7) -> ([CGPoint], Int) {
    let cx: CGFloat = 540, cy: CGFloat = 680 * max(1, r / 80)
    let a = r * taper  // vertical semi-axis of the tip: 1 = round, >1 = pointed
    let nailLength = r * nailFactor
    lastDIP = CGPoint(x: cx, y: cy - a + (a + nailLength) / cuticleFractionOfDIP)
    var pts: [CGPoint] = []
    var cur = CGPoint(x: cx, y: cy - a)
    let na = Int(Double.pi / 2 * Double(max(r, a)))
    for i in 0...na { let t = -Double.pi / 2 + Double.pi / 2 * Double(i) / Double(na)
        pts.append(CGPoint(x: cx + r * CGFloat(cos(t)), y: cy + a * CGFloat(sin(t)))) }
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
        pts.append(CGPoint(x: cx + r * CGFloat(cos(t)), y: cy + a * CGFloat(sin(t)))) }
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


// MARK: - Pointed (real-looking) fingertips at the sizes seen on device
// r=55 ~ the 110px-wide finger in a 1080x1920 video frame; r=150 ~ the same finger in a full-res photo.
let bigImage = CGSize(width: 3024, height: 4032)
func analyzeForTest(_ s: DetectedSilhouette, dip: CGPoint?, tip: CGPoint? = nil) -> LovibondResult? { AngleAnalyzer().analyze(s, dipHint: dip, tipHint: tip) }
func runPointed(label: String, useDIP: Bool) {
    print("\nPOINTED TIP (taper 1.8, jagged, curved nail) -- \(label)")
    print("r/taper/cut% true   mean   worst-err  marker-err(mean)  found")
    for (r, taper, frac) in [(CGFloat(150), CGFloat(1.8), CGFloat(0.35)), (150, 1.8, 0.42), (150, 1.8, 0.5), (150, 1.8, 0.6), (150, 2.4, 0.42), (150, 1.2, 0.42)] {
        for truth in [160.0, 170.0, 180.0, 190.0, 200.0] {
            var errs: [Double] = [], markErr: [Double] = [], found = 0
            for _ in 0..<20 {
                let (pts, cut) = makeRealistic(outsideAngle: truth, r: r, nailCurveDeg: 8, noise: 1.0, nailFactor: 1.2, taper: taper, cuticleFractionOfDIP: frac)
                let n = pts.count
                let sil = DetectedSilhouette(boundingBox: .zero, contourPoints: pts, imageSize: r > 100 ? bigImage : imageSize)
                let apex = pts.min { $0.y < $1.y }!
                let l = hypot(lastDIP.x - apex.x, lastDIP.y - apex.y)
                let dip = CGPoint(x: lastDIP.x + gauss() * l * 0.05, y: lastDIP.y + gauss() * l * 0.05)
                // hand-pose tip sits a little inside the apex, toward the DIP
                let tipHint = CGPoint(x: apex.x + (dip.x - apex.x) * 0.12, y: apex.y + (dip.y - apex.y) * 0.12)
                guard let res = analyzeForTest(sil, dip: useDIP ? dip : nil, tip: useDIP ? tipHint : nil) else { continue }
                let step = ((cut - res.tipIndex + n) % n) < n / 2 ? 1 : -1
                guard let c = res.candidates.first(where: { $0.step == step }) else { continue }
                found += 1
                errs.append(c.angleDegrees - truth)
                markErr.append(Double(hypot(c.inflectionPoint.x - pts[cut].x, c.inflectionPoint.y - pts[cut].y)))
            }
            let mean = errs.isEmpty ? .nan : errs.reduce(0, +) / Double(errs.count) + truth
            let worst = errs.map { abs($0) }.max() ?? .nan
            let mk = markErr.isEmpty ? .nan : markErr.reduce(0, +) / Double(markErr.count)
            print(String(format: "%3.0f/%3.1f/%2.0f  %5.0f  %6.1f   %6.1f      %6.1fpx          %d/20", Double(r), Double(taper), Double(frac * 100), truth, mean, worst, mk, found))
        }
    }
}
runPointed(label: "width-based search (no hint)", useDIP: false)
runPointed(label: "DIP-anchored search (hand-pose hint, jittered ±5%)", useDIP: true)

// MARK: - Manual three-point angle (AngleAnalyzer.outsideAngle)
func polygonContains(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
    var inside = false; var j = poly.count - 1
    for i in 0..<poly.count {
        let a = poly[i], b = poly[j]
        if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        j = i
    }
    return inside
}
print("\nMANUAL 3-POINT (dots placed 60px up the nail / on the cuticle / 80px along the skin)")
print("true  side   inside-by-outline  inside-by-finger-axis  no-inside-info")
var worstManual = 0.0
for truth in [150.0, 160.0, 170.0, 180.0, 190.0, 200.0] {
    for mirror in [false, true] {
        let (raw, cut) = makeFinger(outsideAngle: truth)
        let pts = mirror ? raw.map { CGPoint(x: imageSize.width - $0.x, y: $0.y) } : raw
        let b = pts[cut], a = pts[cut - 60], c = pts[cut + 80]
        let byOutline = AngleAnalyzer.outsideAngle(nailPoint: a, cuticle: b, skinPoint: c) { polygonContains(pts, $0) } ?? .nan
        let byAxis = AngleAnalyzer.outsideAngle(nailPoint: a, cuticle: b, skinPoint: c) { abs($0.x - 540) < abs(b.x - 540) } ?? .nan
        let none = AngleAnalyzer.outsideAngle(nailPoint: a, cuticle: b, skinPoint: c) { _ in nil } ?? .nan
        worstManual = max(worstManual, abs(byOutline - truth), abs(byAxis - truth))
        print(String(format: "%4.0f  %@   %8.1f            %8.1f               %8.1f", truth, mirror ? "left " : "right", byOutline, byAxis, none))
    }
}
print(String(format: "worst manual error (outline or axis) = %.1f deg", worstManual))

// MARK: - Hyponychial angle and depth ratio (FingerSignsAnalyzer)
// Side-view finger pointing up, nail on the right: A (nail-side edge at the
// DIP joint) -> B (cuticle) -> C (nail free edge), then the tip turns in to
// the straight pad side. B's height sets the depth ratio, C's direction the
// hyponychial angle.
func makeSignsFinger(hyponychial: Double, depthRatio: CGFloat, scale: CGFloat, noise: CGFloat)
    -> (points: [CGPoint], tip: CGPoint, dip: CGPoint, cuticle: CGPoint) {
    let cx: CGFloat = 1000, dipY: CGFloat = 2000
    let half = 100 * scale, l = 300 * scale          // half joint thickness, DIP to tip joint
    let a = CGPoint(x: cx + half, y: dipY)
    let b = CGPoint(x: cx - half + 2 * half * depthRatio, y: dipY - 0.62 * l)
    let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
    let turn = atan2(ab.dy, ab.dx) - (hyponychial - 180) * .pi / 180  // convex (above 180) turns toward the axis
    let c = CGPoint(x: b.x + 0.4 * l * cos(turn), y: b.y + 0.4 * l * sin(turn))
    let edgeTurn = turn - 70 * .pi / 180                               // nail free edge
    let d = CGPoint(x: c.x + 0.12 * l * cos(edgeTurn), y: c.y + 0.12 * l * sin(edgeTurn))
    let padTop = CGPoint(x: cx - half, y: d.y + 0.25 * l)
    let bottom = dipY + 1.2 * l
    let belowA = CGPoint(x: a.x - ab.dx * 0.3, y: a.y - ab.dy * 0.3)  // keep AB straight through the joint

    var pts: [CGPoint] = []
    func line(_ p: CGPoint, _ q: CGPoint) {
        let n = max(1, Int(hypot(q.x - p.x, q.y - p.y)))
        for i in 1...n { let t = CGFloat(i) / CGFloat(n); pts.append(CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)) }
    }
    // Counterclockwise on screen: up the pad side, over the tip, down the nail side.
    pts.append(CGPoint(x: cx - half, y: bottom))
    line(pts[0], padTop)
    let n = Int(hypot(d.x - padTop.x, d.y - padTop.y) * 1.5)
    let ctrl = CGPoint(x: padTop.x, y: min(padTop.y, d.y) - 0.35 * l)
    for i in 1...n {  // quadratic curve over the fingertip
        let t = CGFloat(i) / CGFloat(n), u = 1 - t
        pts.append(CGPoint(x: u * u * padTop.x + 2 * u * t * ctrl.x + t * t * d.x, y: u * u * padTop.y + 2 * u * t * ctrl.y + t * t * d.y))
    }
    line(d, c); line(c, b); line(b, a); line(a, belowA)
    line(belowA, CGPoint(x: belowA.x, y: bottom))
    line(CGPoint(x: belowA.x, y: bottom), CGPoint(x: cx - half, y: bottom + 1))
    let jagged = pts.map { CGPoint(x: ($0.x + gauss() * noise).rounded(), y: ($0.y + gauss() * noise).rounded()) }
    // Hand-pose tip joint sits inside the pad, a little short of the apex.
    let apexY = pts.map(\.y).min()!
    return (jagged, CGPoint(x: cx, y: apexY + 0.12 * (dipY - apexY)), CGPoint(x: cx, y: dipY), b)
}

print("\nFINGER SIGNS (jagged ±1px, joints jittered ±3% of finger length, 20 trials each, both nail sides)")
print("scale  true-hypo  mean   worst-err   true-ratio  mean    worst-err")
var worstHypo = 0.0, worstRatio = 0.0
for scale in [CGFloat(1), 2] {
    for (hypo, ratio) in [(175.0, CGFloat(0.85)), (185.0, 0.95), (195.0, 1.1), (180.0, 1.0), (200.0, 0.9)] {
        var hs: [Double] = [], rs: [Double] = []
        for trial in 0..<20 {
            let mirror = trial % 2 == 1
            var (pts, tip, dip, cut) = makeSignsFinger(hyponychial: hypo, depthRatio: ratio, scale: scale, noise: 1)
            let l = hypot(tip.x - dip.x, tip.y - dip.y)
            tip = CGPoint(x: tip.x + gauss() * l * 0.03, y: tip.y + gauss() * l * 0.03)
            dip = CGPoint(x: dip.x + gauss() * l * 0.03, y: dip.y + gauss() * l * 0.03)
            if mirror {
                let flip = { (p: CGPoint) in CGPoint(x: 2000 - p.x, y: p.y) }
                pts = pts.map(flip).reversed(); tip = flip(tip); dip = flip(dip); cut = flip(cut)
            }
            let signs = FingerSignsAnalyzer.measure(contour: pts, tip: tip, dip: dip, cuticle: cut, lovibond: nil,
                                                    isNailSide: { mirror ? $0.x < 1000 : $0.x > 1000 })
            if let h = signs.hyponychial { hs.append(h) }
            if let r = signs.depthRatio { rs.append(r) }
        }
        let hMean = hs.reduce(0, +) / Double(max(1, hs.count)), rMean = rs.reduce(0, +) / Double(max(1, rs.count))
        let hWorst = hs.map { abs($0 - hypo) }.max() ?? .nan, rWorst = rs.map { abs($0 - Double(ratio)) }.max() ?? .nan
        worstHypo = max(worstHypo, hWorst); worstRatio = max(worstRatio, rWorst)
        print(String(format: "%3.0fx   %6.0f    %6.1f   %5.1f  (%d/20)  %5.2f     %5.3f   %5.3f  (%d/20)",
                     Double(scale), hypo, hMean, hWorst, hs.count, Double(ratio), rMean, rWorst, rs.count))
    }
}
print(String(format: "worst: hyponychial %.1f deg, depth ratio %.3f", worstHypo, worstRatio))

// MARK: - Combined result (ClubbingAssessment)
print("\nCOMBINED RESULT (cut-offs 176° / 192° / 1.0, ±3° / ±0.03 counts as close)")
func verdict(_ readings: [(Double?, Double?, Double?)]) -> ClubbingAssessment.Verdict {
    ClubbingAssessment(readings: readings.map { FingerSigns(lovibond: $0.0, hyponychial: $0.1, depthRatio: $0.2) }).verdict
}
let cases: [(String, [(Double?, Double?, Double?)], ClubbingAssessment.Verdict)] = [
    ("healthy", [(168, 179, 0.85)], .typical),
    ("clubbed, all three", [(185, 200, 1.1)], .worthDiscussing),
    ("two of three", [(182, 196, 0.9)], .worthDiscussing),
    ("one sign above", [(170, 197, 0.85)], .measureAgain),
    ("one sign close to a cut-off", [(174.5, 180, 0.85)], .typical),
    ("two signs close to cut-offs", [(174.5, 190, 0.85)], .measureAgain),
    ("one close, one above", [(174.5, 194, 0.85)], .measureAgain),
    ("only profile, typical", [(168, nil, nil)], .typical),
    ("only profile, above", [(185, nil, nil)], .measureAgain),
    ("implausible values ignored", [(168, 260, 3.0)], .typical),
    ("one outlier of three", [(168, 179, 0.85), (183, 199, 1.08), (169, 180, 0.86)], .typical),
    ("steady clubbing", [(184, 197, 1.05), (186, 199, 1.1), (181, 195, 1.02)], .worthDiscussing),
]
var failures = 0
for (name, readings, expected) in cases {
    let got = verdict(readings)
    if got != expected { failures += 1 }
    print("\(got == expected ? "ok  " : "FAIL") \(name): \(got.label)")
}
print("combined-result failures: \(failures)")

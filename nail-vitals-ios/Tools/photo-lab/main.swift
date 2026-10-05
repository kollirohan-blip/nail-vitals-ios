// Runs the app's real measurement pipeline (hand pose -> subject-mask outline
// -> AngleAnalyzer) on photos from disk, on the Mac. From this folder:
//   swiftc -O ../../NailVitals/NailVitals/NailVitals/Detection/{DetectedSilhouette,AngleAnalyzer,HandPoseDetector,FingerMaskSegmenter,FingerSigns,ClubbingAssessment,OutlineFingerFinder,HumanLabel,NailColor,EdgeSharpness}.swift main.swift Report.swift NailLab.swift EdgeRefiner.swift -o photo-lab
//   ./photo-lab photo.jpg [more.jpg ...] [--out folder] [--truth x,y]
// --truth is the real cuticle in image pixels (e.g. from a saved capture's
// manual dot 2); the report then includes how far the automatic marker missed.

import AppKit
import CoreImage
import CoreGraphics
import ImageIO


func loadUpright(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    var image = CIImage(contentsOf: URL(fileURLWithPath: path)) ?? CIImage()
    image = image.oriented(CGImagePropertyOrientation(rawValue: raw) ?? .up)
    image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    return CIContext().createCGImage(image, from: image.extent)
}

func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA,
                        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
    guard let buffer else { return nil }
    CIContext().render(CIImage(cgImage: image), to: buffer)
    return buffer
}

func writeAnnotated(_ image: CGImage, silhouette: DetectedSilhouette?, hand: HandLandmarks?,
                    result: LovibondResult?, truth: CGPoint?, signs: FingerSigns?, labels: [HumanLabel] = [], to path: String) {
    let w = image.width, h = image.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    // Image-pixel coordinates are top-left origin; CGContext is bottom-left.
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    let unit = CGFloat(max(w, h)) / 1000

    if let s = silhouette, let first = s.contourPoints.first {
        ctx.setStrokeColor(CGColor(red: 0.2, green: 1, blue: 0.3, alpha: 1)); ctx.setLineWidth(1.5 * unit)
        ctx.move(to: first); s.contourPoints.dropFirst().forEach { ctx.addLine(to: $0) }; ctx.closePath(); ctx.strokePath()
    }
    func dot(_ p: CGPoint, _ c: CGColor, _ r: CGFloat, filled: Bool = true) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
        if filled { ctx.setFillColor(c); ctx.fillEllipse(in: rect) } else { ctx.setStrokeColor(c); ctx.setLineWidth(2 * unit); ctx.strokeEllipse(in: rect) }
    }
    if let hand {
        for j in [hand.indexTip, hand.indexDIP, hand.indexPIP, hand.indexMCP] { dot(j.point, CGColor(red: 0, green: 0.8, blue: 1, alpha: 1), 5 * unit) }
    }
    if let result {
        dot(result.fingertip, CGColor(gray: 1, alpha: 1), 5 * unit)
        for c in result.candidates {
            dot(c.inflectionPoint, c.side == "left" ? CGColor(red: 1, green: 0.85, blue: 0, alpha: 1) : CGColor(red: 1, green: 0.4, blue: 0.7, alpha: 1), 12 * unit, filled: false)
        }
    }
    if let truth { dot(truth, CGColor(red: 1, green: 0, blue: 0, alpha: 1), 4 * unit) }
    if let signs {
        // Hyponychial angle A-B-C in magenta, depth slices in orange.
        if let a = signs.crease, let b = signs.cuticle, let c = signs.hyponychium {
            ctx.setStrokeColor(CGColor(red: 1, green: 0.2, blue: 1, alpha: 1)); ctx.setLineWidth(1.5 * unit)
            ctx.move(to: a); ctx.addLine(to: b); ctx.addLine(to: c); ctx.strokePath()
            for p in [a, b, c] { dot(p, CGColor(red: 1, green: 0.2, blue: 1, alpha: 1), 4 * unit) }
        }
        for slice in [signs.nailBedSlice, signs.jointSlice].compactMap({ $0 }) {
            ctx.setStrokeColor(CGColor(red: 1, green: 0.55, blue: 0, alpha: 1)); ctx.setLineWidth(1.5 * unit)
            ctx.move(to: slice.a); ctx.addLine(to: slice.b); ctx.strokePath()
        }
    }

    // People's Label-mode points: white squares and lines (hyponychial
    // C-B-A, profile N-B-S, and the two across lines).
    for label in labels {
        let p = label.placedPoints
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95)); ctx.setLineWidth(1.2 * unit)
        ctx.setLineDash(phase: 0, lengths: [6 * unit, 4 * unit])
        for chain in [[HumanLabel.Point.freeEdge, .cuticle, .crease], [.nail, .cuticle, .skin], [.cuticle, .cuticleAcross], [.crease, .creaseAcross]] {
            let pts = chain.compactMap { p[$0] }
            guard pts.count == chain.count else { continue }
            ctx.move(to: pts[0]); pts.dropFirst().forEach { ctx.addLine(to: $0) }; ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])
        for (_, q) in p {
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: q.x - 3.5 * unit, y: q.y - 3.5 * unit, width: 7 * unit, height: 7 * unit))
        }
    }

    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
}

var args = Array(CommandLine.arguments.dropFirst())
var outDir = FileManager.default.currentDirectoryPath
var truth: CGPoint?
if let i = args.firstIndex(of: "--out"), i + 1 < args.count { outDir = args[i + 1]; args.removeSubrange(i...i + 1) }
func pointArg(_ flag: String) -> CGPoint? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    let v = args[i + 1].split(separator: ",").compactMap { Double($0) }
    args.removeSubrange(i...i + 1)
    return v.count == 2 ? CGPoint(x: v[0], y: v[1]) : nil
}
truth = pointArg("--truth")
// For photos where hand pose finds no hand (e.g. a single cropped finger):
// hand-placed fingertip and DIP joint in image pixels.
let manualTip = pointArg("--tip")
let manualDIP = pointArg("--dip")
// For photos where hand pose finds the wrong hand or finger: which side of
// the image the nail is on (left or right of the DIP joint).
// Profile turn (degrees) that marks the nail's free edge for the drawn
// hyponychial angle and the result line (default: the app's).
var drawTurn = 30.0
if let i = args.firstIndex(of: "--turn"), i + 1 < args.count, let t = Double(args[i + 1]) { drawTurn = t; args.removeSubrange(i...i + 1) }
// --estimate-cuticle f: also measure with the cuticle taken f of the way
// from the fingertip to the DIP joint (no dip needed), to test that
// estimate against the found or hand-placed cuticle.
var estimateFraction: Double?
if let i = args.firstIndex(of: "--estimate-cuticle"), i + 1 < args.count { estimateFraction = Double(args[i + 1]); args.removeSubrange(i...i + 1) }
// --imagej file.csv (repeatable): an independent rater's hand measurements
// made in ImageJ, as columns capture,rater,profile,hyponychial,depth_ratio
// (capture = the capture folder's name, e.g. 20261005-141502). Added to the
// report as "<rater> (ImageJ)". See Tools/validation/ for the protocol.
var imageJ: [String: [String: [SignKind: Double]]] = [:]   // capture -> rater -> values
while let i = args.firstIndex(of: "--imagej"), i + 1 < args.count {
    let file = args[i + 1]
    args.removeSubrange(i...i + 1)
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { print("Couldn't read \(file)"); continue }
    var lines = text.split(whereSeparator: \.isNewline).map(String.init)
    let header = lines.isEmpty ? [] : lines.removeFirst().lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    func column(_ name: String) -> Int? { header.firstIndex(of: name) }
    guard let c = column("capture"), let r = column("rater") else { print("\(file): needs capture and rater columns"); continue }
    for line in lines {
        let cells = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count > max(c, r), !cells[c].isEmpty else { continue }
        var values: [SignKind: Double] = [:]
        for (kind, key) in [(SignKind.lovibond, "profile"), (.hyponychial, "hyponychial"), (.depthRatio, "depth_ratio")] {
            if let k = column(key), k < cells.count, let v = Double(cells[k]) { values[kind] = v }
        }
        imageJ[cells[c], default: [:]][cells[r] + " (ImageJ)"] = values
    }
}
// --whole: the outline from the whole photo only (the app before Oct 2026;
// the app now tries a crop around the finger first, as below).
let wholeOnly = args.contains("--whole")
args.removeAll { $0 == "--whole" }
// --snap (experiment, not in the app): move the outline onto the photo's
// real edge (EdgeRefiner.swift). Went wrong on busy backgrounds and next to
// the nail's own edge on darker skin, so the app doesn't use it.
let useSnap = args.contains("--snap")
args.removeAll { $0 == "--snap" }
// --nails: the phase 2 nail color prototype instead (see NailLab.swift).
if args.contains("--nails") {
    args.removeAll { $0 == "--nails" }
    runNailLab(args, outDir: outDir)
    exit(0)
}
// --report: compare the app with Label-mode labels (see Report.swift).
let makeReport = args.contains("--report")
args.removeAll { $0 == "--report" }
var reportRows: [ReportRow] = []
var manualNailSide: String?
if let i = args.firstIndex(of: "--nail-side"), i + 1 < args.count { manualNailSide = args[i + 1]; args.removeSubrange(i...i + 1) }

/// A folder saved by the app's CaptureRecorder: photo.jpg + capture.json. The
/// user's manual dot 2 (the cuticle) becomes the ground truth.
func loadCaptureFolder(_ dir: String) -> (photo: String, truth: CGPoint?, summary: String, confirmedAngle: Double?)? {
    let photo = (dir as NSString).appendingPathComponent("photo.jpg")
    guard FileManager.default.fileExists(atPath: photo) else { return nil }
    // Newer captures keep the user's confirmation in confirmation.json; the
    // first few stored everything in capture.json.
    func readJSON(_ file: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: (dir as NSString).appendingPathComponent(file))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    guard let json = readJSON("confirmation.json") ?? readJSON("capture.json") else { return (photo, nil, "", nil) }
    var truth: CGPoint?
    if let dots = json["manualDots"] as? [[Double]], dots.count == 3 { truth = CGPoint(x: dots[1][0], y: dots[1][1]) }
    var summary = ""
    var confirmedAngle: Double?
    if let c = json["confirmed"] as? [String: Any], let side = c["side"] as? String, let angle = c["angle"] as? Double {
        summary = String(format: "  on phone: confirmed %@ %.1f°", side, angle)
        if truth != nil { summary += "  (manual dots = ground truth)" }
        confirmedAngle = angle
    }
    return (photo, truth, summary, confirmedAngle)
}

for path in args {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    let name = isDir.boolValue ? URL(fileURLWithPath: path).lastPathComponent : URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    var imagePath = path
    var truth = truth
    var savedSummary = ""
    var confirmedAngle: Double?
    if isDir.boolValue {
        guard let folder = loadCaptureFolder(path) else { print("\(name): no photo.jpg"); continue }
        imagePath = folder.photo
        truth = folder.truth ?? truth
        savedSummary = folder.summary
        confirmedAngle = folder.confirmedAngle
    }
    guard let image = loadUpright(imagePath), let buffer = pixelBuffer(from: image) else { print("\(name): could not load"); continue }
    let visionHand = HandPoseDetector().detect(in: buffer)
    let segmenter = FingerMaskSegmenter()
    let fullSize = CGSize(width: image.width, height: image.height)
    // Same as the app (CaptureFlowView.runAnalysis): the outline from a crop
    // around hand pose's finger, used when it measures on that same finger;
    // otherwise the whole photo, where hand pose's index finger is checked
    // against the raised finger in the outline (rings, an OK-sign hand).
    var silhouette: DetectedSilhouette?
    var hand: HandLandmarks?
    var cropped = false
    if !wholeOnly, manualTip == nil, manualDIP == nil, let v = visionHand,
       let s = segmenter.segmentAroundFinger(pixelBuffer: buffer, hand: v) {
        let h = OutlineFingerFinder.resolve(v, contour: s.contourPoints, imageSize: fullSize)
        if h?.fromOutline == false, AngleAnalyzer().analyze(s, dipHint: h?.indexDIP.point, tipHint: h?.indexTip.point) != nil {
            silhouette = s
            hand = h
            cropped = true
        }
    }
    if silhouette == nil {
        silhouette = segmenter.segment(pixelBuffer: buffer, fingertipHint: manualDIP ?? visionHand?.indexDIP.point)
        hand = OutlineFingerFinder.resolve(visionHand, contour: silhouette?.contourPoints, imageSize: fullSize)
    }
    if useSnap, let s = silhouette {
        let points = EdgeRefiner.snap(s.contourPoints, in: buffer)
        silhouette = DetectedSilhouette(boundingBox: MaskGeometry.boundingRect(of: points), contourPoints: points, imageSize: s.imageSize)
    }
    let tipPoint = manualTip ?? hand?.indexTip.point
    let dipPoint = manualDIP ?? hand?.indexDIP.point
    let result = silhouette.flatMap { AngleAnalyzer().analyze($0, dipHint: dipPoint, tipHint: tipPoint) }

    print("== \(name)  \(image.width)x\(image.height)")
    print(cropped ? "  outline: crop around the finger" : "  outline: whole photo")
    if !savedSummary.isEmpty { print(savedSummary) }
    if visionHand?.isClearlyTurned == true { print("  -> hand clearly turned: the app asks for a retake (no measurement)") }
    // Same blur check as the app (EdgeSharpness), on the measured outline.
    let sharpness = silhouette.flatMap { s in hand.flatMap { h in
        EdgeSharpness.measure(contour: s.contourPoints, tip: h.indexTip.point, dip: h.indexDIP.point, in: buffer) } }
    let blurry = (sharpness ?? 1) < EdgeSharpness.minimum
    if let sharpness {
        print(String(format: "  sharpness %.3f%@", sharpness, blurry ? "  -> blurry: the app asks for a retake (no measurement)" : ""))
    }
    if let hand {
        print(String(format: "  hand: conf %.2f  tip (%.0f,%.0f)  dip (%.0f,%.0f)  finger length %.0f%% of height",
                     hand.minIndexConfidence, hand.indexTip.point.x, hand.indexTip.point.y,
                     hand.indexDIP.point.x, hand.indexDIP.point.y, hand.fingerLengthFraction * 100))
        print(String(format: "  turn cue: knuckle spread %.2f (little-finger knuckle conf %.2f)",
                     hand.knuckleSpread ?? .nan, hand.littleMCP?.confidence ?? 0))
    } else { print("  hand: none") }
    if manualTip != nil || manualDIP != nil { print("  using hand-placed tip/DIP") }
    if let contour = silhouette?.contourPoints, let f = OutlineFingerFinder.raisedFinger(in: contour), let v = visionHand {
        print(String(format: "  outline finger: apex (%.0f,%.0f) base (%.0f,%.0f) width %.0f | hand pose tip (%.0f,%.0f) dip (%.0f,%.0f)",
                     f.apex.x, f.apex.y, f.base.x, f.base.y, f.width, v.indexTip.point.x, v.indexTip.point.y, v.indexDIP.point.x, v.indexDIP.point.y))
    }
    if hand?.fromOutline == true {
        print(String(format: "  hand pose missed the raised finger (index conf %.2f): joints from the outline%@",
                     visionHand?.minIndexConfidence ?? 0, hand?.thumbTip == nil ? ", no thumb (nail side unknown)" : ""))
    }
    // Calibration: where hand pose's joints sit along the outline's finger.
    if let v = visionHand, !(hand?.fromOutline ?? true), let contour = silhouette?.contourPoints,
       let f = OutlineFingerFinder.raisedFinger(in: contour) {
        func frac(_ p: CGPoint) -> CGFloat { ((f.apex.x - p.x) * f.axis.dx + (f.apex.y - p.y) * f.axis.dy) / f.length }
        print(String(format: "  calib: finger %.0f px long, %.0f wide; joints at tip %.2f dip %.2f pip %.2f mcp %.2f",
                     f.length, f.width, frac(v.indexTip.point), frac(v.indexDIP.point), frac(v.indexPIP.point), frac(v.indexMCP.point)))
    }
    let d = segmenter.lastDiagnostics
    print("  mask: instances \(d.instanceCount)  outline points \(d.contourPointCount)  \(Int(d.maskMs + d.contourMs)) ms  \(silhouette == nil ? "NO OUTLINE" : "")")
    if let result, let dip = dipPoint {
        let apex = result.fingertip
        let l = hypot(dip.x - apex.x, dip.y - apex.y)
        for c in result.candidates {
            let frac = hypot(c.inflectionPoint.x - apex.x, c.inflectionPoint.y - apex.y) / l
            let nailSide = hand?.isOnNailSide(c.inflectionPoint).map { $0 ? "NAIL side" : "pad side" } ?? "side unknown"
            var line = String(format: "  %@ marker (%@): %.1f°  at (%.0f,%.0f) = %.2f of tip-to-DIP", c.side, nailSide, c.angleDegrees, c.inflectionPoint.x, c.inflectionPoint.y, frac)
            if let truth { line += String(format: "  miss %.0f px", hypot(c.inflectionPoint.x - truth.x, c.inflectionPoint.y - truth.y)) }
            print(line)
        }
        // Mirrors CaptureFlowView.foundNoCuticleDip.
        let shown = result.candidates.filter { hand?.isOnNailSide($0.inflectionPoint) != false }
        if !shown.isEmpty, shown.allSatisfy({ $0.angleDegrees >= 180 }) {
            print("  -> no cuticle dip on the nail side: app asks for manual dots instead of showing a number")
        }
    } else if result == nil { print("  analyzer: no result") }

    // The three clubbing signs, at the confirmed cuticle (the manual dot when
    // there is one, else the nail-side automatic marker).
    var signs: FingerSigns?
    let nailMarker = result?.candidates.first { hand?.isOnNailSide($0.inflectionPoint) == true }
    // Same as the app: no cuticle dip on the nail side -> the cuticle is
    // estimated and the profile angle counts as obliterated (180).
    let shownMarkers = result?.candidates.filter { hand?.isOnNailSide($0.inflectionPoint) != false } ?? []
    let noDip = !shownMarkers.isEmpty && shownMarkers.allSatisfy { $0.angleDegrees >= 180 }
    var estimated: CGPoint?
    if noDip, truth == nil, let result, let silhouette, let hand, let tip = tipPoint, let dip = dipPoint {
        estimated = FingerSignsAnalyzer.estimatedCuticle(contour: silhouette.contourPoints, apex: result.fingertip, tip: tip, dip: dip,
                                                         isNailSide: { hand.isOnNailSide($0) })
        if estimated != nil { print("  -> app estimates the cuticle and asks for one confirmation") }
    }
    if let silhouette, let tip = tipPoint, let dip = dipPoint, let cuticle = truth ?? estimated ?? nailMarker?.inflectionPoint {
        var isNailSide: ((CGPoint) -> Bool?)? = hand.map { h in { h.isOnNailSide($0) } }
        if let side = manualNailSide { isNailSide = { ($0.x > dip.x) == (side == "right") } }
        var line = "  signs:"
        for turn in [30.0, 45.0, 60.0] {
            let s = FingerSignsAnalyzer.measure(contour: silhouette.contourPoints, tip: tip, dip: dip, cuticle: cuticle,
                                                lovibond: nailMarker?.angleDegrees, isNailSide: isNailSide, turnDegrees: turn)
            if turn == drawTurn {
                signs = s
                if estimated != nil { signs?.noCuticleDip = true; signs?.lovibond = 180 }
            }
            line += String(format: "  hyponychial(turn %.0f) %.1f°", turn, s.hyponychial ?? .nan)
        }
        line += String(format: "  depth ratio %.3f", signs?.depthRatio ?? .nan)
        print(line)
        if let f = estimateFraction, let result {
            let apex = result.fingertip
            let est = CGPoint(x: apex.x + (dip.x - apex.x) * f, y: apex.y + (dip.y - apex.y) * f)
            let e = FingerSignsAnalyzer.measure(contour: silhouette.contourPoints, tip: tip, dip: dip, cuticle: est,
                                                lovibond: nil, isNailSide: isNailSide, turnDegrees: drawTurn)
            let along = { (q: CGPoint) in hypot(q.x - apex.x, q.y - apex.y) / hypot(dip.x - apex.x, dip.y - apex.y) }
            // Profile angle at the estimated cuticle: the local angle there.
            if let b = e.cuticle, let nailCandidate = result.candidates.first(where: { hand?.isOnNailSide($0.inflectionPoint) == true }) {
                let pts = result.contourPoints
                let i = pts.indices.min { hypot(pts[$0].x - b.x, pts[$0].y - b.y) < hypot(pts[$1].x - b.x, pts[$1].y - b.y) }!
                let p = AngleAnalyzer().recomputeAngle(points: pts, tipIndex: result.tipIndex, userConfirmedIndex: i,
                                                       step: nailCandidate.step, segmentLengthPixels: result.segmentLengthPixels)
                print(String(format: "  estimated cuticle profile angle: %.1f°  (found/used: %.1f°)", p ?? .nan, nailMarker?.angleDegrees ?? .nan))
            }
            print(String(format: "  estimated cuticle (%.2f): hyponychial %.1f°  depth ratio %.3f  | used cuticle at %.2f: hyponychial %.1f°  depth ratio %.3f",
                         f, e.hyponychial ?? .nan, e.depthRatio ?? .nan, along(cuticle), signs?.hyponychial ?? .nan, signs?.depthRatio ?? .nan))
        }
        if var s = signs {
            // The confirmed profile angle when the user confirmed one on the phone.
            if let confirmed = confirmedAngle, !s.noCuticleDip { s.lovibond = confirmed }
            let how = s.noCuticleDip ? "  (no cuticle dip: profile counted as 180+, cuticle estimated)"
                : (confirmedAngle == nil ? "  (profile angle from the automatic marker)" : "")
            print(String(format: "  app: profile %@  hyponychial %.1f°  depth ratio %.3f", s.noCuticleDip ? "no dip (180+)" : String(format: "%.1f°", s.lovibond ?? .nan), s.hyponychial ?? .nan, s.depthRatio ?? .nan))
            print("  result: \(ClubbingAssessment(readings: [s]).verdict.label)" + how)
        }
    }
    let outPath = (outDir as NSString).appendingPathComponent("\(name)-annotated.png")
    let labels = isDir.boolValue ? Array(Report.labels(in: path).values) : []
    writeAnnotated(image, silhouette: silhouette, hand: hand, result: result, truth: truth, signs: signs, labels: labels, to: outPath)
    print("  annotated: \(outPath)")

    if makeReport {
        // The app's own automatic measurement (not the user's confirmation).
        var app: [SignKind: Double] = [:]
        var status = "failed"
        let shown = result?.candidates.filter { hand?.isOnNailSide($0.inflectionPoint) != false } ?? []
        if visionHand?.isClearlyTurned == true {
            status = "retake (turned)"
        } else if blurry {
            status = "retake (blurry)"
        } else if let result, let silhouette, let hand, let marker = nailMarker {
            if noDip {
                status = estimated == nil ? "needs dots" : "auto (no dip)"
                if let s = signs, estimated != nil {
                    app[.lovibond] = 180
                    app[.hyponychial] = SignKind.hyponychial.value(in: s)
                    app[.depthRatio] = SignKind.depthRatio.value(in: s)
                }
            } else {
                status = "auto"
                let s = FingerSignsAnalyzer.measure(contour: silhouette.contourPoints, tip: hand.indexTip.point, dip: hand.indexDIP.point,
                                                    cuticle: marker.inflectionPoint, lovibond: marker.angleDegrees,
                                                    isNailSide: { hand.isOnNailSide($0) }, turnDegrees: drawTurn)
                for kind in SignKind.allCases { app[kind] = kind.value(in: s) }
            }
            _ = result
        }
        var meta: [String: Any] = [:]
        if isDir.boolValue, let data = try? Data(contentsOf: URL(fileURLWithPath: (path as NSString).appendingPathComponent("capture.json"))),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { meta = json }
        var humans = isDir.boolValue ? Report.labels(in: path).mapValues(Report.values) : [:]
        // Also each label with its points snapped onto the finger's outline
        // (where along the edge stays the person's choice), as "<name>+edge".
        if let contour = silhouette?.contourPoints, isDir.boolValue {
            for (name, label) in Report.labels(in: path) {
                var snapped: [HumanLabel.Point: CGPoint] = [:]
                for (k, q) in label.placedPoints {
                    let nearest = contour.min { hypot($0.x - q.x, $0.y - q.y) < hypot($1.x - q.x, $1.y - q.y) }!
                    snapped[k] = hypot(nearest.x - q.x, nearest.y - q.y) < 40 ? nearest : q
                }
                humans[name + "+edge"] = Report.values(HumanLabel(labeler: name, points: snapped))
            }
        }
        for (rater, values) in imageJ[name] ?? [:] { humans[rater] = values }
        if isDir.boolValue { for (rater, values) in Report.imageJLabels(in: path) { humans[rater] = values } }
        reportRows.append(ReportRow(capture: name, participant: meta["participant"] as? String, skinTone: meta["skinTone"] as? String,
                                    hand: meta["measuredHand"] as? String, lighting: meta["lighting"] as? String,
                                    torchOn: meta["torchOn"] as? Bool, appStatus: status, app: app, humans: humans))
    }
}
if makeReport {
    Report.write(reportRows, to: (outDir as NSString).appendingPathComponent("report"))
}

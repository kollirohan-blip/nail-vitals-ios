// Runs the app's real measurement pipeline (hand pose -> subject-mask outline
// -> AngleAnalyzer) on photos from disk, on the Mac. From this folder:
//   swiftc -O ../../NailVitals/NailVitals/NailVitals/Detection/{DetectedSilhouette,AngleAnalyzer,HandPoseDetector,FingerMaskSegmenter}.swift main.swift -o photo-lab
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
                    result: LovibondResult?, truth: CGPoint?, to path: String) {
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

/// A folder saved by the app's CaptureRecorder: photo.jpg + capture.json. The
/// user's manual dot 2 (the cuticle) becomes the ground truth.
func loadCaptureFolder(_ dir: String) -> (photo: String, truth: CGPoint?, summary: String)? {
    let photo = (dir as NSString).appendingPathComponent("photo.jpg")
    guard FileManager.default.fileExists(atPath: photo) else { return nil }
    // Newer captures keep the user's confirmation in confirmation.json; the
    // first few stored everything in capture.json.
    func readJSON(_ file: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: (dir as NSString).appendingPathComponent(file))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    guard let json = readJSON("confirmation.json") ?? readJSON("capture.json") else { return (photo, nil, "") }
    var truth: CGPoint?
    if let dots = json["manualDots"] as? [[Double]], dots.count == 3 { truth = CGPoint(x: dots[1][0], y: dots[1][1]) }
    var summary = ""
    if let c = json["confirmed"] as? [String: Any], let side = c["side"] as? String, let angle = c["angle"] as? Double {
        summary = String(format: "  on phone: confirmed %@ %.1f°", side, angle)
        if truth != nil { summary += "  (manual dots = ground truth)" }
    }
    return (photo, truth, summary)
}

for path in args {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    let name = isDir.boolValue ? URL(fileURLWithPath: path).lastPathComponent : URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    var imagePath = path
    var truth = truth
    var savedSummary = ""
    if isDir.boolValue {
        guard let folder = loadCaptureFolder(path) else { print("\(name): no photo.jpg"); continue }
        imagePath = folder.photo
        truth = folder.truth ?? truth
        savedSummary = folder.summary
    }
    guard let image = loadUpright(imagePath), let buffer = pixelBuffer(from: image) else { print("\(name): could not load"); continue }
    let hand = HandPoseDetector().detect(in: buffer)
    let tipPoint = manualTip ?? hand?.indexTip.point
    let dipPoint = manualDIP ?? hand?.indexDIP.point
    let segmenter = FingerMaskSegmenter()
    let silhouette = segmenter.segment(pixelBuffer: buffer, fingertipHint: dipPoint)
    let result = silhouette.flatMap { AngleAnalyzer().analyze($0, dipHint: dipPoint, tipHint: tipPoint) }

    print("== \(name)  \(image.width)x\(image.height)")
    if !savedSummary.isEmpty { print(savedSummary) }
    if let hand {
        print(String(format: "  hand: conf %.2f  tip (%.0f,%.0f)  dip (%.0f,%.0f)  finger length %.0f%% of height",
                     hand.minIndexConfidence, hand.indexTip.point.x, hand.indexTip.point.y,
                     hand.indexDIP.point.x, hand.indexDIP.point.y, hand.fingerLengthFraction * 100))
    } else { print("  hand: none") }
    if manualTip != nil || manualDIP != nil { print("  using hand-placed tip/DIP") }
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
    let outPath = (outDir as NSString).appendingPathComponent("\(name)-annotated.png")
    writeAnnotated(image, silhouette: silhouette, hand: hand, result: result, truth: truth, to: outPath)
    print("  annotated: \(outPath)")
}

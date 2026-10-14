// photo-lab --schamroth photo.jpg [...] [--tap x,y]: runs the app's
// Schamroth window finder (SchamrothFinder) on photos of two index fingers
// pressed nail to nail. Prints the enclosed background-coloured gaps and the
// one taken as the window, and writes <name>-schamroth.png with the gaps in
// blue, the window in green and where the fingers meet (hand pose) in yellow.
// --tap traces the gap from that point by colour, as the app does when the
// user taps a window the mask filled in.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func runSchamroth(_ paths: [String], outDir: String, tap: CGPoint?, requireHands: Bool) {
    for path in paths {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard let image = loadUpright(path), let buffer = pixelBuffer(from: image) else { print("\(name): could not load"); continue }
        let result = SchamrothFinder.find(in: buffer, requireBothFingers: requireHands)
        print("\(name) (\(image.width)x\(image.height))")
        print("  index fingers found by hand pose: \(result.indexFingers.count)" +
              (result.fingerWidth.map { String(format: ", finger thickness about %.0f px", $0) } ?? ""))
        let sorted = result.gaps.sorted { $0.area > $1.area }
        print("  enclosed gaps: \(sorted.count)" + (sorted.isEmpty ? "" : ", largest: " +
              sorted.prefix(3).map { String(format: "%.0fx%.0f px at (%.0f, %.0f)", $0.length, $0.width, $0.center.x, $0.center.y) }.joined(separator: "; ")))
        if let w = result.window {
            let rel = result.fingerWidth.map { String(format: " = %.2f x %.2f finger thicknesses", w.length / $0, w.width / $0) } ?? ""
            print(String(format: "  WINDOW: %.0f x %.0f px%@, area %.0f px²", w.length, w.width, rel, w.area))
        } else {
            print("  no window found")
        }
        var tapped: SchamrothWindow?
        if let tap, let rgba = RGBAImage(image) {
            let reach = (result.fingerWidth ?? CGFloat(min(image.width, image.height)) * 0.1) * 1.5
            tapped = SchamrothFinder.traceTapped(rgba, at: tap, reach: reach)
            print(tapped.map { String(format: "  tap at (%.0f, %.0f): closed gap %.0f x %.0f px", tap.x, tap.y, $0.length, $0.width) }
                  ?? String(format: "  tap at (%.0f, %.0f): no closed gap there (open to the background, or too small)", tap.x, tap.y))
        }
        writeSchamroth(image, result: result, tapped: tapped, to: (outDir as NSString).appendingPathComponent("\(name)-schamroth.png"))
    }
}

private func writeSchamroth(_ image: CGImage, result: SchamrothFinder.Result, tapped: SchamrothWindow?, to path: String) {
    let w = image.width, h = image.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    // Image pixels are top-left; CoreGraphics is bottom-left.
    func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x, y: CGFloat(h) - q.y) }
    func stroke(_ outline: [CGPoint], _ color: CGColor, _ width: CGFloat) {
        guard let first = outline.first else { return }
        ctx.beginPath(); ctx.move(to: p(first)); for q in outline.dropFirst() { ctx.addLine(to: p(q)) }; ctx.closePath()
        ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.strokePath()
    }
    let lw = CGFloat(max(w, h)) / 600
    for gap in result.gaps { stroke(gap.outline, CGColor(red: 0.1, green: 0.4, blue: 1, alpha: 0.9), lw) }
    if let window = result.window { stroke(window.outline, CGColor(red: 0, green: 0.8, blue: 0.2, alpha: 1), lw * 2) }
    if let tapped { stroke(tapped.outline, CGColor(red: 1, green: 0.2, blue: 0.6, alpha: 1), lw * 2) }
    if let line = result.contactLine {
        ctx.beginPath(); ctx.move(to: p(line.from)); ctx.addLine(to: p(line.to))
        ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0, alpha: 0.9)); ctx.setLineWidth(lw); ctx.strokePath()
    }
    for finger in result.indexFingers {
        for joint in [finger.tip, finger.dip] {
            ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: p(joint.point).x - lw * 3, y: p(joint.point).y - lw * 3, width: lw * 6, height: lw * 6))
        }
    }
    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
}

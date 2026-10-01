// photo-lab --nails: phase 2 prototype for Terry's and half-and-half nails.
// For each photo: finds every hand and finger, samples the color profile
// along each finger (NailColorAnalyzer), and writes
//   <name>-nails.png     the photo with each finger's sampled strip
//   <name>-profiles.png  one chart per finger: L* (lightness), a* (redness)
//                        and b* (yellowness) from the DIP joint (0) past the
//                        tip joint (1)
// so the patterns can be looked at before any detection rules are written.

import AppKit
import CoreGraphics

func runNailLab(_ arguments: [String], outDir: String) {
    // --axis x1,y1,x2,y2 (repeatable): a nail's line placed by hand, from
    // where the nail starts at the cuticle to the end of its free edge.
    // Used for photos where hand pose can't place nails (fists, crops).
    var args = arguments
    var axes: [(CGPoint, CGPoint)] = []
    while let i = args.firstIndex(of: "--axis"), i + 1 < args.count {
        let v = args[i + 1].split(separator: ",").compactMap { Double($0) }
        if v.count == 4 { axes.append((CGPoint(x: v[0], y: v[1]), CGPoint(x: v[2], y: v[3]))) }
        args.removeSubrange(i...i + 1)
    }
    if !axes.isEmpty, let path = args.first {
        runAxisProfiles(path, axes: axes, outDir: outDir)
        return
    }
    for path in args {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard let image = loadUpright(path), let buffer = pixelBuffer(from: image), let rgba = RGBAImage(image) else {
            print("\(name): could not load"); continue
        }
        let hands = HandPoseDetector().detectFingers(in: buffer, maxHands: 2)
        print("== \(name)  \(image.width)x\(image.height)  hands: \(hands.count)")
        var drawn: [(FingerChain, [NailColorAnalyzer.Sample], [CGPoint]?)] = []
        for (h, fingers) in hands.enumerated() {
            let hint = fingers.first(where: { $0.name == .middle })?.dip.point ?? fingers.first?.dip.point
            let outline = FingerMaskSegmenter().segment(pixelBuffer: buffer, fingertipHint: hint)?.contourPoints
            for finger in fingers {
                let samples = NailColorAnalyzer.profile(rgba, tip: finger.tip.point, dip: finger.dip.point, outline: outline)
                drawn.append((finger, samples, outline))
                let summary = stride(from: 0, to: samples.count, by: max(1, samples.count / 8)).map { s in
                    String(format: "%.2f:L%.0f a%.0f b%.0f", samples[s].along, samples[s].color.l, samples[s].color.a, samples[s].color.b)
                }.joined(separator: "  ")
                print(String(format: "  hand %d %@ (conf %.2f): %d samples  %@", h, finger.name.rawValue,
                             min(finger.tip.confidence, finger.dip.confidence), samples.count, summary))
            }
        }
        writeNailOverlay(image, drawn, to: (outDir as NSString).appendingPathComponent("\(name)-nails.png"))
        writeProfiles(drawn, title: name, to: (outDir as NSString).appendingPathComponent("\(name)-profiles.png"))
    }
}

private func writeNailOverlay(_ image: CGImage, _ fingers: [(FingerChain, [NailColorAnalyzer.Sample], [CGPoint]?)], to path: String) {
    let w = image.width, h = image.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    let unit = CGFloat(max(w, h)) / 1000
    for (finger, _, _) in fingers {
        guard let frame = FingerSignsAnalyzer.FingerFrame(tip: finger.tip.point, dip: finger.dip.point) else { continue }
        // The sampled range along the finger (DIP to 1.6x past), and the tip joint.
        ctx.setStrokeColor(CGColor(red: 0, green: 0.9, blue: 1, alpha: 0.9)); ctx.setLineWidth(1.5 * unit)
        ctx.move(to: frame.point(along: 0, across: 0)); ctx.addLine(to: frame.point(along: frame.length * 1.6, across: 0)); ctx.strokePath()
        for (p, c) in [(finger.dip.point, CGColor(red: 0, green: 0.9, blue: 1, alpha: 1)), (finger.tip.point, CGColor(red: 1, green: 0.3, blue: 0.8, alpha: 1))] {
            ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: p.x - 4 * unit, y: p.y - 4 * unit, width: 8 * unit, height: 8 * unit))
        }
        let label = finger.name.rawValue as NSString
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true); NSGraphicsContext.current = ns
        label.draw(at: frame.point(along: frame.length * 1.65, across: 0),
                   withAttributes: [.font: NSFont.boldSystemFont(ofSize: 12 * unit), .foregroundColor: NSColor.cyan])
    }
    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
}

/// One panel per finger: L* (white), a* (red), b* (yellow) against position
/// along the finger. a* and b* share a -10...50 axis, L* uses 0...100.
private func writeProfiles(_ fingers: [(FingerChain, [NailColorAnalyzer.Sample], [CGPoint]?)], title: String, to path: String) {
    guard !fingers.isEmpty else { return }
    let panelW = 420, panelH = 220, cols = 2
    let rows = (fingers.count + cols - 1) / cols
    let w = panelW * cols, h = panelH * rows + 40
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false); NSGraphicsContext.current = ns
    (title as NSString).draw(at: NSPoint(x: 10, y: h - 28), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.white])
    for (i, (finger, samples, _)) in fingers.enumerated() {
        let ox = Double((i % cols) * panelW) + 40, oy = Double(h - 40 - (i / cols + 1) * panelH) + 30
        let pw = Double(panelW) - 60, ph = Double(panelH) - 50
        func px(_ along: Double) -> Double { ox + along / 1.6 * pw }
        ctx.setStrokeColor(CGColor(gray: 0.35, alpha: 1)); ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: ox, y: oy, width: pw, height: ph))
        for x in [0.0, 0.5, 1.0, 1.5] {
            ctx.move(to: CGPoint(x: px(x), y: oy)); ctx.addLine(to: CGPoint(x: px(x), y: oy + ph)); ctx.strokePath()
            (String(format: "%.1f", x) as NSString).draw(at: NSPoint(x: px(x) - 8, y: oy - 16),
                                                        withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.lightGray])
        }
        func line(_ value: (NailColorAnalyzer.Lab) -> Double, lo: Double, hi: Double, _ color: CGColor) {
            ctx.setStrokeColor(color); ctx.setLineWidth(2)
            for (k, s) in samples.enumerated() {
                let p = CGPoint(x: px(s.along), y: oy + (value(s.color) - lo) / (hi - lo) * ph)
                if k == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
            }
            ctx.strokePath()
        }
        line({ $0.l }, lo: 0, hi: 100, CGColor(gray: 0.95, alpha: 1))
        line({ $0.a }, lo: -10, hi: 50, CGColor(red: 1, green: 0.35, blue: 0.35, alpha: 1))
        line({ $0.b }, lo: -10, hi: 50, CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
        (finger.name.rawValue + "  (white L*, red a*, yellow b*; 0 = DIP, 1 = tip joint)" as NSString)
            .draw(at: NSPoint(x: ox, y: oy + ph + 4), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
    }
    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
}

/// Profiles along hand-placed nail lines: 0 = where the nail starts at the
/// cuticle, 1 = the end of the free edge.
private func runAxisProfiles(_ path: String, axes: [(CGPoint, CGPoint)], outDir: String) {
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    guard let image = loadUpright(path), let rgba = RGBAImage(image) else { print("\(name): could not load"); return }
    print("== \(name) (hand-placed nail lines)")
    for (n, (start, end)) in axes.enumerated() {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 4 else { continue }
        let ax = CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
        var line = String(format: "  nail %d (%.0f px):", n + 1, length)
        for k in 0...20 {
            let t = CGFloat(k) / 20
            var colors: [NailColorAnalyzer.Lab] = []
            for j in 0..<7 {
                let off = length * 0.12 * (CGFloat(j) / 6 - 0.5)
                let p = CGPoint(x: start.x + ax.dx * length * t - ax.dy * off, y: start.y + ax.dy * length * t + ax.dx * off)
                if let c = rgba.lab(at: p) { colors.append(c) }
            }
            guard !colors.isEmpty else { continue }
            let l = NailColorAnalyzer.median(colors.map(\.l)), a = NailColorAnalyzer.median(colors.map(\.a)), b = NailColorAnalyzer.median(colors.map(\.b))
            line += String(format: "\n     %.2f  L %5.1f  a %5.1f  b %5.1f  %@", Double(t), l, a, b, String(repeating: "#", count: max(0, Int((a + 10) / 2))))
        }
        print(line)
    }
}

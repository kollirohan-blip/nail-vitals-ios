// photo-lab --report: how well the app agrees with people, how repeatable
// it is, and whether any skin-tone group does worse. Reads the app's own
// automatic measurement of each capture (replayed here) and every
// label-<initials>.json from Label mode. Writes report.txt, report.csv and
// one Bland-Altman chart per sign (app minus person against their mean).

import AppKit
import CoreGraphics

struct ReportRow {
    let capture: String
    let participant: String?
    let skinTone: String?
    let hand: String?
    /// "auto" = the app showed a number; "needs dots" = no cuticle dip, so
    /// the app asked for manual dots; "failed" = no measurement.
    let appStatus: String
    let app: [SignKind: Double]
    let humans: [String: [SignKind: Double]]
}

enum Report {
    /// Labels in a capture folder, by labeler.
    static func labels(in folder: String) -> [String: HumanLabel] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        var result: [String: HumanLabel] = [:]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in files where file.hasPrefix("label-") && file.hasSuffix(".json") {
            let url = URL(fileURLWithPath: (folder as NSString).appendingPathComponent(file))
            if let data = try? Data(contentsOf: url), let label = try? decoder.decode(HumanLabel.self, from: data) {
                result[label.labeler] = label
            }
        }
        return result
    }

    /// The three signs from a label's points, recomputed with the current
    /// formulas.
    static func values(_ label: HumanLabel) -> [SignKind: Double] {
        let s = HumanLabel.signs(label.placedPoints)
        var v: [SignKind: Double] = [:]
        v[.lovibond] = s.profile
        v[.hyponychial] = s.hyponychial
        v[.depthRatio] = s.depthRatio
        return v
    }

    // MARK: - Statistics

    struct Agreement {
        let n: Int
        let bias: Double
        let sd: Double
        var lower: Double { bias - 1.96 * sd }
        var upper: Double { bias + 1.96 * sd }
        let meanAbs: Double
        let icc: Double?
    }

    /// Bland-Altman bias and limits, mean absolute difference, and
    /// ICC(2,1) (two-way random, absolute agreement, single measures).
    static func agreement(_ pairs: [(Double, Double)]) -> Agreement? {
        guard pairs.count >= 2 else { return nil }
        let d = pairs.map { $0.0 - $0.1 }
        let n = Double(pairs.count)
        let bias = d.reduce(0, +) / n
        let sd = sqrt(d.map { ($0 - bias) * ($0 - bias) }.reduce(0, +) / (n - 1))
        let meanAbs = d.map(abs).reduce(0, +) / n
        return Agreement(n: pairs.count, bias: bias, sd: sd, meanAbs: meanAbs, icc: icc21(pairs))
    }

    static func icc21(_ pairs: [(Double, Double)]) -> Double? {
        let n = Double(pairs.count), k = 2.0
        guard n >= 3 else { return nil }
        let rows = pairs.map { ($0.0 + $0.1) / 2 }
        let col0 = pairs.map(\.0).reduce(0, +) / n, col1 = pairs.map(\.1).reduce(0, +) / n
        let grand = (col0 + col1) / 2
        let msr = k * rows.map { ($0 - grand) * ($0 - grand) }.reduce(0, +) / (n - 1)
        let msc = n * ((col0 - grand) * (col0 - grand) + (col1 - grand) * (col1 - grand)) / (k - 1)
        var sse = 0.0
        for (i, p) in pairs.enumerated() {
            for (x, col) in [(p.0, col0), (p.1, col1)] {
                let r = x - rows[i] - col + grand
                sse += r * r
            }
        }
        let mse = sse / ((n - 1) * (k - 1))
        let denominator = msr + (k - 1) * mse + k * (msc - mse) / n
        return denominator > 0 ? (msr - mse) / denominator : nil
    }

    /// Pooled within-person SD over people with 2+ readings.
    static func withinPersonSD(_ groups: [[Double]]) -> (sd: Double, people: Int, readings: Int)? {
        let used = groups.filter { $0.count >= 2 }
        guard !used.isEmpty else { return nil }
        var ss = 0.0, df = 0
        for g in used {
            let m = g.reduce(0, +) / Double(g.count)
            ss += g.map { ($0 - m) * ($0 - m) }.reduce(0, +)
            df += g.count - 1
        }
        return (sqrt(ss / Double(df)), used.count, used.map(\.count).reduce(0, +))
    }

    // MARK: - Output

    static func write(_ rows: [ReportRow], to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let labelers = Array(Set(rows.flatMap { $0.humans.keys })).sorted()
        var text = "NAIL VITALS REPORT  (\(rows.count) captures, labelers: \(labelers.isEmpty ? "none yet" : labelers.joined(separator: ", ")))\n"
        let auto = rows.filter { $0.appStatus == "auto" }
        text += "App: \(auto.count) measured automatically, \(rows.filter { $0.appStatus == "needs dots" }.count) asked for manual dots, \(rows.filter { $0.appStatus == "failed" }.count) failed.\n"

        func fmt(_ kind: SignKind, _ v: Double) -> String { kind == .depthRatio ? String(format: "%.3f", v) : String(format: "%.1f", v) }

        for kind in SignKind.allCases {
            text += "\n== \(kind.title)\n"
            let appValues = auto.compactMap { $0.app[kind] }
            if appValues.count >= 2 {
                let m = appValues.reduce(0, +) / Double(appValues.count)
                let sd = sqrt(appValues.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(appValues.count - 1))
                text += "  App, all automatic readings: n \(appValues.count), mean \(fmt(kind, m)), SD \(fmt(kind, sd)), range \(fmt(kind, appValues.min()!))-\(fmt(kind, appValues.max()!))\n"
            }
            // Repeatability: same person, same hand.
            var groups: [String: [Double]] = [:]
            for r in auto { if let p = r.participant, let v = r.app[kind] { groups["\(p)/\(r.hand ?? "?")", default: []].append(v) } }
            if let w = withinPersonSD(Array(groups.values)) {
                text += "  App repeatability: within-person SD \(fmt(kind, w.sd)) (\(w.people) people, \(w.readings) readings); repeat readings differ by less than \(fmt(kind, 2.77 * w.sd)) 95% of the time\n"
            } else {
                text += "  App repeatability: needs participant codes and 2+ readings per person\n"
            }
            for labeler in labelers {
                let pairs = auto.compactMap { r -> (Double, Double)? in
                    guard let a = r.app[kind], let h = r.humans[labeler]?[kind] else { return nil }
                    return (a, h)
                }
                if let ag = agreement(pairs) {
                    text += "  App vs \(labeler): n \(ag.n), bias \(fmt(kind, ag.bias)), 95% limits \(fmt(kind, ag.lower)) to \(fmt(kind, ag.upper)), mean |diff| \(fmt(kind, ag.meanAbs)), ICC \(ag.icc.map { String(format: "%.2f", $0) } ?? "-")\n"
                    chart(kind: kind, pairs: pairs, agreement: ag, title: "\(kind.title): app vs \(labeler)",
                          path: (dir as NSString).appendingPathComponent("bland-altman-\(kind)-\(labeler).png"))
                }
            }
            for (i, a) in labelers.enumerated() {
                for b in labelers[(i + 1)...] {
                    let pairs = rows.compactMap { r -> (Double, Double)? in
                        guard let x = r.humans[a]?[kind], let y = r.humans[b]?[kind] else { return nil }
                        return (x, y)
                    }
                    if let ag = agreement(pairs) {
                        text += "  \(a) vs \(b) (person vs person): n \(ag.n), bias \(fmt(kind, ag.bias)), 95% limits \(fmt(kind, ag.lower)) to \(fmt(kind, ag.upper)), ICC \(ag.icc.map { String(format: "%.2f", $0) } ?? "-")\n"
                    }
                }
            }
            // By skin-tone group: app vs the average of the people who labeled it.
            var byTone: [String: [Double]] = [:]
            for r in auto {
                guard let a = r.app[kind] else { continue }
                let hs = r.humans.values.compactMap { $0[kind] }
                guard !hs.isEmpty else { continue }
                byTone[r.skinTone ?? "not recorded", default: []].append(abs(a - hs.reduce(0, +) / Double(hs.count)))
            }
            if !byTone.isEmpty {
                text += "  App vs people by skin-tone group (mean |diff|): " + byTone.keys.sorted().map { key in
                    let v = byTone[key]!
                    return "\(key) \(fmt(kind, v.reduce(0, +) / Double(v.count))) (n \(v.count))"
                }.joined(separator: ", ") + "\n"
            }
        }

        // Result per person: the app's verdict from the middle of each
        // person's readings, as the result screen shows it.
        var perPerson: [String: [FingerSigns]] = [:]
        for r in auto {
            guard let p = r.participant else { continue }
            perPerson["\(p)/\(r.hand ?? "?")", default: []].append(
                FingerSigns(lovibond: r.app[.lovibond], hyponychial: r.app[.hyponychial], depthRatio: r.app[.depthRatio]))
        }
        if !perPerson.isEmpty {
            text += "\n== Result per person (middle of their readings)\n"
            for key in perPerson.keys.sorted() {
                text += "  \(key): \(ClubbingAssessment(readings: perPerson[key]!).verdict.label) (\(perPerson[key]!.count) readings)\n"
            }
        }
        let single = auto.map { ClubbingAssessment(readings: [FingerSigns(lovibond: $0.app[.lovibond], hyponychial: $0.app[.hyponychial], depthRatio: $0.app[.depthRatio])]).verdict.label }
        text += "\nSingle-photo results: " + Set(single).sorted().map { v in "\(v) \(single.filter { $0 == v }.count)" }.joined(separator: ", ") + "\n"
        text += "Published healthy reference: hyponychial 178.9 (SD 4.7), Husarik 2002; depth ratio cut-off 1.0 (healthy fingers stay below it), Myers & Farquhar 2001.\n"

        try? text.write(toFile: (dir as NSString).appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        print(text)

        var csv = "capture,participant,skin_tone,hand,app_status,app_profile,app_hyponychial,app_depth_ratio"
        for l in labelers { csv += ",\(l)_profile,\(l)_hyponychial,\(l)_depth_ratio" }
        csv += "\n"
        func cell(_ v: Double?) -> String { v.map { String(format: "%.3f", $0) } ?? "" }
        for r in rows {
            csv += [r.capture, r.participant ?? "", r.skinTone ?? "", r.hand ?? "", r.appStatus,
                    cell(r.app[.lovibond]), cell(r.app[.hyponychial]), cell(r.app[.depthRatio])].joined(separator: ",")
            for l in labelers {
                csv += "," + [cell(r.humans[l]?[.lovibond]), cell(r.humans[l]?[.hyponychial]), cell(r.humans[l]?[.depthRatio])].joined(separator: ",")
            }
            csv += "\n"
        }
        try? csv.write(toFile: (dir as NSString).appendingPathComponent("report.csv"), atomically: true, encoding: .utf8)
        print("Wrote report.txt, report.csv\(labelers.isEmpty ? "" : " and Bland-Altman charts") to \(dir)")
    }

    /// Bland-Altman chart: each capture's difference against the mean of the
    /// two readings, with the bias and 95% limits.
    static func chart(kind: SignKind, pairs: [(Double, Double)], agreement ag: Agreement, title: String, path: String) {
        let w = 900, h = 600, left = 90.0, right = 30.0, top = 60.0, bottom = 70.0
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let means = pairs.map { ($0.0 + $0.1) / 2 }, diffs = pairs.map { $0.0 - $0.1 }
        let pad = kind == .depthRatio ? 0.02 : 2.0
        let x0 = means.min()! - pad, x1 = means.max()! + pad
        let yMax = max(abs(ag.lower), abs(ag.upper), diffs.map(abs).max()!) + pad
        func px(_ x: Double) -> Double { left + (x - x0) / (x1 - x0) * (Double(w) - left - right) }
        func py(_ y: Double) -> Double { bottom + (y + yMax) / (2 * yMax) * (Double(h) - top - bottom) }

        func text(_ s: String, _ x: Double, _ y: Double, size: CGFloat = 16, bold: Bool = false) {
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = ns
            (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
                .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])
        }
        func hline(_ y: Double, _ color: CGColor, dash: Bool) {
            ctx.setStrokeColor(color); ctx.setLineWidth(2); ctx.setLineDash(phase: 0, lengths: dash ? [8, 6] : [])
            ctx.move(to: CGPoint(x: left, y: py(y))); ctx.addLine(to: CGPoint(x: Double(w) - right, y: py(y))); ctx.strokePath()
        }
        ctx.setStrokeColor(CGColor(gray: 0.4, alpha: 1)); ctx.setLineWidth(1); ctx.setLineDash(phase: 0, lengths: [])
        ctx.stroke(CGRect(x: left, y: bottom, width: Double(w) - left - right, height: Double(h) - top - bottom))
        hline(0, CGColor(gray: 0.7, alpha: 1), dash: false)
        hline(ag.bias, CGColor(red: 0, green: 0.45, blue: 0.85, alpha: 1), dash: false)
        hline(ag.lower, CGColor(red: 0.85, green: 0.3, blue: 0.3, alpha: 1), dash: true)
        hline(ag.upper, CGColor(red: 0.85, green: 0.3, blue: 0.3, alpha: 1), dash: true)
        ctx.setFillColor(CGColor(red: 0, green: 0.55, blue: 0.4, alpha: 0.85))
        for (m, d) in zip(means, diffs) { ctx.fillEllipse(in: CGRect(x: px(m) - 6, y: py(d) - 6, width: 12, height: 12)) }

        func f(_ v: Double) -> String { kind == .depthRatio ? String(format: "%.3f", v) : String(format: "%.1f°", v) }
        text(title, left, Double(h) - 40, size: 20, bold: true)
        text("bias \(f(ag.bias))", Double(w) - 260, py(ag.bias) + 4, size: 14)
        text("+1.96 SD \(f(ag.upper))", Double(w) - 260, py(ag.upper) + 4, size: 14)
        text("-1.96 SD \(f(ag.lower))", Double(w) - 260, py(ag.lower) - 20, size: 14)
        text("Mean of app and person", Double(w) / 2 - 90, 20, size: 15)
        text(f(x0), left - 10, bottom - 25, size: 13); text(f(x1), Double(w) - right - 50, bottom - 25, size: 13)
        text("App minus person", 8, Double(h) / 2, size: 15)
        text("n = \(pairs.count)", left + 10, Double(h) - top - 25, size: 14)

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

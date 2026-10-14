//
//  QualityPanel.swift
//  NailVitals
//
//  Under a result: which checks the readings passed, how far the readings
//  spread, and how much a scan on another day usually moves (measured,
//  see Repeatability). No overall score: each line is a real check.
//

import SwiftUI

struct QualityPanel: View {
    let readings: [FingerSigns]

    private struct Row: Identifiable {
        let id: String
        let label: String
        let passed: Int
        let failed: Int
    }

    /// One row per check that was measured on at least one reading.
    private var rows: [Row] {
        var rows = ReadingQuality.Check.allCases.compactMap { check -> Row? in
            let results = readings.compactMap { $0.quality?.passed(check) }
            guard !results.isEmpty else { return nil }
            return Row(id: check.rawValue, label: check.label,
                       passed: results.filter { $0 }.count, failed: results.filter { !$0 }.count)
        }
        // Readings 2 and 3 against the first (FingerIdentity); a mismatch
        // isn't counted unless the user started over with that finger.
        let prints = readings.compactMap(\.identity)
        if prints.count >= 2 {
            let failed = prints.dropFirst().filter { FingerIdentity.mismatch(first: prints[0], later: $0) != nil }.count
            rows.append(Row(id: "same", label: "Same finger each time", passed: prints.count - failed, failed: failed))
        }
        return rows
    }

    var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Measurement checks")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .textCase(.uppercase)
                Spacer()
                if !rows.isEmpty {
                    let passed = rows.filter { $0.failed == 0 }.count
                    Text("\(passed) of \(rows.count) passed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(passed == rows.count ? Theme.aligned : Theme.adjusting)
                }
            }
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(row.failed == 0 ? Theme.aligned : Theme.adjusting)
                    Text(row.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(row.failed == 0
                         ? (row.passed == 1 ? "passed" : "all \(row.passed)")
                         : "\(row.failed) of \(row.passed + row.failed) not")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
            }
            if rows.isEmpty {
                Text("Saved before the app recorded its checks.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
            if let estimated = estimatedJoints {
                Text(estimated)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
            Divider().opacity(0.5)
            if let spread = spreadText {
                Text(spread)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(repeatText)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// How far apart this session's readings are, per sign.
    private var spreadText: String? {
        guard readings.count >= 2 else { return nil }
        func spread(_ kind: SignKind) -> String? {
            let values = readings.compactMap { r -> Double? in
                kind == .lovibond && r.noCuticleDip ? nil : kind.value(in: r)
            }
            guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return nil }
            return kind == .depthRatio ? String(format: "ratio %.2f", hi - lo) : String(format: "%@ %.1f°", kind.plainName.lowercased(), hi - lo)
        }
        let parts = SignKind.allCases.compactMap(spread)
        guard !parts.isEmpty else { return nil }
        return "Spread of your \(readings.count) readings: " + parts.joined(separator: " · ")
    }

    /// The measured session-to-session range (Repeatability).
    private var repeatText: String {
        let parts = SignKind.allCases.compactMap { kind -> String? in
            guard let r = Repeatability.range95[kind] else { return nil }
            return kind == .depthRatio ? String(format: "ratio ±%.2f", r) : String(format: "%@ ±%.0f°", kind.plainName.lowercased(), r)
        }
        return "A scan on another day usually lands within \(parts.joined(separator: " · ")) of this result (measured over \(Repeatability.sessions) repeat sessions)."
    }

    private var estimatedJoints: String? {
        let n = readings.filter { $0.quality?.jointsFromHandPose == false }.count
        guard n > 0 else { return nil }
        return "Finger joints estimated from the outline in \(n) reading\(n == 1 ? "" : "s") (hand pose didn't find them)."
    }
}

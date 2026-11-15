//
//  QualityPanel.swift
//  NailVitals
//
//  The checks behind a result (CheckSummary): which passed and, one tap
//  away, each check's measured number against the threshold it had to
//  meet. No overall score: each line is a real check of the measurement,
//  and none of them says anything about health.
//

import SwiftUI

struct QualityPanel: View {
    let readings: [FingerSigns]

    @State private var showNumbers = false

    var body: some View {
        let summary = CheckSummary(readings: readings)
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    title
                    Spacer()
                    badge(summary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    badge(summary)
                }
            }
            ForEach(summary.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Image(systemName: row.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(row.failed == 0 ? Theme.aligned : Theme.adjusting)
                        Text(row.label)
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        Text(row.failed == 0
                             ? (row.passed == 1 ? "passed" : "all \(row.passed)")
                             : "\(row.failed) of \(row.passed + row.failed) not")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if showNumbers, let detail = row.detail {
                        Text(detail)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.leading, 30)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if summary.rows.isEmpty {
                Text("Saved before the app recorded its checks.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showNumbers.toggle() }
                } label: {
                    Label(showNumbers ? "Hide the numbers" : "Show the numbers behind each check",
                          systemImage: showNumbers ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            if let estimated = estimatedJoints {
                Text(estimated)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var title: some View {
        Text("Measurement checks")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func badge(_ summary: CheckSummary) -> some View {
        if let text = summary.badge {
            Text(text.replacingOccurrences(of: " checks", with: ""))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(summary.passedCount == summary.rows.count ? Theme.aligned : Theme.adjusting)
        }
    }

    private var estimatedJoints: String? {
        let n = readings.filter { $0.quality?.jointsFromHandPose == false }.count
        guard n > 0 else { return nil }
        return "Finger joints estimated from the outline in \(n) reading\(n == 1 ? "" : "s") (hand pose didn't find them)."
    }

    /// How far apart this session's readings are, per sign.
    static func spreadText(_ readings: [FingerSigns]) -> String? {
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
    static var repeatText: String {
        let parts = SignKind.allCases.compactMap { kind -> String? in
            guard let r = Repeatability.range95[kind] else { return nil }
            return kind == .depthRatio ? String(format: "ratio ±%.2f", r) : String(format: "%@ ±%.0f°", kind.plainName.lowercased(), r)
        }
        return "A scan on another day usually lands within \(parts.joined(separator: " · ")) of this result (measured over \(Repeatability.sessions) repeat sessions)."
    }
}

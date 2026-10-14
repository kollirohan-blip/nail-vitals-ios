//
//  NormsPanel.swift
//  NailVitals
//
//  Under a result: each sign against healthy fingers in published studies
//  (a percentile, PublishedNorms) and the Nail Vitals Index. Descriptive
//  only; the verdict above comes from the published cut-offs.
//

import SwiftUI

struct NormsPanel: View {
    /// Each sign's value (the session's middle values).
    let values: [SignKind: Double]
    /// No cuticle dip: the nail angle is 180 or more, so its percentile and
    /// the index are lower bounds.
    var noDip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compared with healthy fingers")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
                .textCase(.uppercase)
            ForEach(SignKind.allCases, id: \.self) { kind in
                if let value = values[kind] { row(kind, value) }
            }
            if let index = PublishedNorms.index(values) {
                Divider().opacity(0.5)
                HStack(alignment: .firstTextBaseline) {
                    Text("Nail Vitals Index")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text((noDip ? "≥ " : "") + String(format: "%+.1f", index))
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(.primary)
                Text("How far your finger sits from the healthy average in the studies above: 0 is average, and each 1 is one standard deviation. It describes; it has no cut-off and isn't a diagnosis.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Percentile: the share of healthy fingers with a lower value.")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.6))
        }
    }

    private func row(_ kind: SignKind, _ value: Double) -> some View {
        let norm = PublishedNorms.norms[kind]
        let shown = kind == .lovibond && noDip ? "≥180°" : kind.formatted(value)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.plainName)
                    .font(.system(size: 15, weight: .medium))
                Text(shown)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                Text(standing(kind, value))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color(kind, value))
            }
            .foregroundStyle(.primary)
            Text(norm.map { "Healthy average \(kind.formatted($0.mean)) (SD \(String(format: "%.1f", $0.sd))) · \($0.source)" }
                 ?? "No published healthy spread to compare with; healthy fingers stay below \(kind.formattedThreshold).")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func standing(_ kind: SignKind, _ value: Double) -> String {
        if let p = PublishedNorms.percentile(kind, value) {
            return (kind == .lovibond && noDip ? ">99th" : PublishedNorms.percentileText(p)) + " percentile"
        }
        return value < kind.threshold ? "below \(kind.formattedThreshold)" : "at or above \(kind.formattedThreshold)"
    }

    /// Green inside the middle 95% of healthy fingers (or under the
    /// cut-off), amber outside it.
    private func color(_ kind: SignKind, _ value: Double) -> Color {
        if kind == .lovibond && noDip { return Theme.adjusting }
        if let p = PublishedNorms.percentile(kind, value) { return p <= 97.5 ? Theme.aligned : Theme.adjusting }
        return value < kind.threshold ? Theme.aligned : Theme.adjusting
    }
}

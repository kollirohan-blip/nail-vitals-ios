//
//  NormsPanel.swift
//  NailVitals
//
//  Under a result: each sign against healthy fingers in published studies
//  (its place on the study's bell curve, PublishedNorms) and the Nail
//  Vitals Index. Descriptive only; the verdict comes from the published
//  limits. Nothing here is colored like a pass or fail: a high percentile
//  is not a good score, it is the high end of normal.
//

import SwiftUI

struct NormsPanel: View {
    /// Each sign's value (the session's middle values).
    let values: [SignKind: Double]
    /// No cuticle dip: the nail angle is 180 or more, so its percentile and
    /// the index are lower bounds.
    var noDip = false

    @State private var showIndexMethod = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.normal) {
            Text("Compared with healthy fingers")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(SignKind.allCases, id: \.self) { kind in
                if let value = values[kind] { row(kind, value) }
            }
            if let index = PublishedNorms.index(values) {
                Divider().opacity(0.5)
                indexRow(index)
            }
            Text("Percentile: the share of healthy fingers with a lower value. A high percentile means closer to the limit, not a better score.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ kind: SignKind, _ value: Double) -> some View {
        let shown = kind == .lovibond && noDip ? "≥180°" : kind.formatted(value)
        return VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(kind.plainName)  \(shown)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    standing(kind, value)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(kind.plainName)  \(shown)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    standing(kind, value)
                }
            }
            if let norm = PublishedNorms.norms[kind] {
                DistributionCurve(mean: norm.mean, sd: norm.sd, value: value, limit: kind.threshold)
                Text("Healthy average \(kind.formatted(norm.mean)) (SD \(String(format: "%.1f", norm.sd))) · \(norm.source). The tick is the \(kind.formattedThreshold) limit.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No published healthy spread to compare with. Healthy fingers stay below \(kind.formattedThreshold).")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The percentile as plain text: neutral, never a pass or fail color.
    private func standing(_ kind: SignKind, _ value: Double) -> some View {
        let text: String
        if let p = PublishedNorms.percentile(kind, value) {
            text = (kind == .lovibond && noDip ? ">99th" : PublishedNorms.percentileText(p)) + " percentile"
        } else {
            text = value < kind.threshold ? "below \(kind.formattedThreshold)" : "at or above \(kind.formattedThreshold)"
        }
        return Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .fixedSize()
    }

    /// The index as a bar from the healthy average (0), with its method
    /// one tap away.
    private func indexRow(_ index: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nail Vitals Index")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text((noDip ? "≥ " : "") + String(format: "%+.1f", index))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                let w = geo.size.width, mid = w / 2
                let x = mid + CGFloat(min(max(index, -3), 3) / 3) * mid
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10)).frame(height: 6).offset(y: 5)
                    Capsule().fill(Color.primary.opacity(0.45))
                        .frame(width: max(abs(x - mid), 2), height: 6)
                        .offset(x: min(x, mid), y: 5)
                    Capsule().fill(Color.primary.opacity(0.6)).frame(width: 2, height: 16).offset(x: mid - 1)
                    Circle().fill(Theme.text).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                        .offset(x: min(max(x - 6, 0), w - 12), y: 2)
                }
            }
            .frame(height: 16)
            .accessibilityHidden(true)
            HStack {
                Text("−3")
                Spacer()
                Text("0 = healthy average")
                Spacer()
                Text("+3")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showIndexMethod.toggle() }
            } label: {
                Label("How it's calculated", systemImage: showIndexMethod ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44, alignment: .leading)
            }
            if showIndexMethod {
                Text("For each angle: (your value − the healthy average) ÷ the standard deviation, using Bentley 1976 for the nail angle and Husarik 2002 for the fingertip angle. The index is the average of those two numbers. 0 is the healthy average and each 1 is one standard deviation. It is this app's own description of your finger's shape. It has no cut-off, hasn't been validated as a score, and isn't a diagnosis.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

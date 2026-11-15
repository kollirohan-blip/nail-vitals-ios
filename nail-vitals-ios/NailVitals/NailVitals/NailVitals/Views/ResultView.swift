//
//  ResultView.swift
//  NailVitals
//
//  Shared pieces of the clubbing result: the wording for each verdict and
//  the dial for the profile angle (each sign's number line is RangeBar). The result
//  screens themselves are ReportCardView and SignDetailView. Every result
//  screen MUST show the "screening aid, not a diagnosis" line (SafetyNote):
//  a legal and ethical requirement from the project spec, not optional copy.
//
//  With 3 or more readings in a session, each sign's middle value is used:
//  single readings of the same finger vary by a few degrees with pose.
//

import SwiftUI

enum ResultView {
    static func color(for verdict: ClubbingAssessment.Verdict) -> Color {
        SignState(verdict).color
    }

    static func color(for status: SignStatus) -> Color {
        SignState(status).color
    }

    /// What the verdict means, in a sentence or two. `steady`: from enough
    /// readings to use the middle values. Used by the report card and the sign page.
    static func verdictDetail(_ a: ClubbingAssessment, steady: Bool, noDip: Bool) -> String {
        let detail: String
        switch a.verdict {
        case .typical:
            detail = a.nearCount > 0
                ? "The measured signs are in the healthy range. One is close to its cut-off, which single photos of healthy fingers often are."
                : "The measured signs are in the range seen in healthy fingers."
        case .measureAgain where steady:
            detail = a.aboveCount == 1
                ? "One sign stays above its usual range. One sign alone isn't a clear pattern, but you can mention it at your next doctor's visit."
                : "Two signs stay close to their cut-offs. You can mention it at your next doctor's visit."
        case .measureAgain:
            detail = a.aboveCount == 1
                ? "One sign is above its usual range, and single photos vary. Measure again so the app can use the middle values."
                : "Two signs are close to their cut-offs, and single photos vary by a few degrees. Measure again to confirm."
        case .worthDiscussing:
            detail = "Two or more signs are in the range where clubbing is considered. Clubbing has many causes, and some people are born with it, so only a doctor can say what it means. Mention any symptoms you've noticed."
        }
        return noDip
            ? detail + " No cuticle dip was found: clubbing does this, and so can a finger turned toward the camera."
            : detail
    }
}

/// The dial for the profile angle, from 140° to 220°: three zones around
/// the 176° limit (typical, within measurement error of it, past it), tick
/// labels so it reads as a scale, a shaded band for how far a scan usually
/// moves from day to day, and a dot for the value. A dot on a scale, not a
/// needle swinging toward a red zone: the reading is the same, without the
/// alarm.
struct ResultGauge: View, Animatable {
    static let minAngle = 140.0
    static let maxAngle = 220.0

    @Environment(\.colorScheme) private var scheme

    var angle: Double
    /// Half-width of the day-to-day band, in degrees (Repeatability).
    var uncertainty: Double = 0
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height - 22)
            let radius = min(geo.size.width / 2 - 34, geo.size.height - 44)
            let kind = SignKind.lovibond
            let low = kind.threshold - kind.margin, high = kind.threshold + kind.margin
            ZStack {
                zone(from: Self.minAngle, to: low, color: Theme.aligned, center: center, radius: radius)
                zone(from: low, to: high, color: Theme.adjusting, center: center, radius: radius)
                zone(from: high, to: Self.maxAngle, color: Theme.attention, center: center, radius: radius)

                // Minor ticks every 10 degrees.
                ForEach(Array(stride(from: Self.minAngle, through: Self.maxAngle, by: 10)), id: \.self) { value in
                    Path { p in
                        p.move(to: point(value, center, radius + 10))
                        p.addLine(to: point(value, center, radius + 14))
                    }
                    .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                tickLabel("140°", at: Self.minAngle, center, radius)
                tickLabel("220°", at: Self.maxAngle, center, radius)

                // The published limit.
                Path { p in
                    p.move(to: point(kind.threshold, center, radius - 12))
                    p.addLine(to: point(kind.threshold, center, radius + 14))
                }
                .stroke(Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Text("limit \(kind.formattedThreshold)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize()
                    .position(point(kind.threshold, center, radius + 30))

                // How far a scan usually moves from day to day.
                if uncertainty > 0 {
                    arc(from: angle - uncertainty, to: angle + uncertainty, center: center, radius: radius)
                        .stroke(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 24, lineCap: .butt))
                }

                let color = SignState(kind.status(of: angle)).color
                Circle()
                    .fill(color)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 3))
                    .position(point(angle, center, radius))
            }
        }
    }

    /// Dial angle: 140° sits at the left end, 220° at the right end.
    private func point(_ value: Double, _ center: CGPoint, _ radius: CGFloat) -> CGPoint {
        let clamped = min(max(value, Self.minAngle), Self.maxAngle)
        let theta = Double.pi + (clamped - Self.minAngle) / (Self.maxAngle - Self.minAngle) * Double.pi
        return CGPoint(x: center.x + radius * CGFloat(cos(theta)), y: center.y + radius * CGFloat(sin(theta)))
    }

    private func arc(from a: Double, to b: Double, center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            let steps = 30
            for i in 0...steps {
                let pt = point(a + (b - a) * Double(i) / Double(steps), center, radius)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }

    private func zone(from a: Double, to b: Double, color: Color, center: CGPoint, radius: CGFloat) -> some View {
        // Stronger on white, where pale zones wash out.
        arc(from: a, to: b, center: center, radius: radius)
            .stroke(color.opacity(scheme == .light ? 0.55 : 0.45), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
    }

    private func tickLabel(_ text: String, at value: Double, _ center: CGPoint, _ radius: CGFloat) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize()
            .position(x: point(value, center, radius).x, y: center.y + 14)
    }
}

/// What the dial's and the bars' three zones mean.
struct ZoneLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.normal) { items }
            VStack(alignment: .leading, spacing: 4) { items }
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var items: some View {
        item(Theme.aligned, "typical")
        item(Theme.adjusting, "close to the limit")
        item(Theme.attention, "past the limit")
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.7)).frame(width: 12, height: 6)
            Text(text).lineLimit(1).fixedSize()
        }
    }
}

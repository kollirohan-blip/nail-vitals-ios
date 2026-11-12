//
//  ResultView.swift
//  NailVitals
//
//  Shared pieces of the clubbing result: the wording for each verdict, the
//  chip for one sign, and the dial for the profile angle. The result
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
                ? "One sign stays above its usual range. One sign alone isn't a clear pattern, but you can mention it at your next checkup."
                : "Two signs stay close to their cut-offs. You can mention it at your next checkup."
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

/// One sign: its value, a status icon, and the published cut-off.
struct SignChip: View {
    let kind: SignKind
    let value: Double?
    /// Shown instead of the number (e.g. "≥180°" for no cuticle dip).
    var valueText: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            if let value {
                let status = kind.status(of: value)
                Image(systemName: icon(for: status))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ResultView.color(for: status))
                Text(valueText ?? kind.formatted(value))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            } else {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("—")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Text(kind.plainName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.75))
            Text(value == nil ? "not measured" : "\(kind.shortTitle) · limit \(kind.formattedThreshold)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .tileBackground(cornerRadius: 14)
    }

    private func icon(for status: SignStatus) -> String {
        switch status {
        case .typical: return "checkmark.circle.fill"
        case .nearThreshold: return "circle.lefthalf.filled"
        case .above: return "exclamationmark.circle.fill"
        }
    }
}

/// Semicircular dial from 140° to 220° for the profile angle, with zones
/// around the 176° cut-off (typical, within measurement error, above) and
/// a needle.
struct ResultGauge: View, Animatable {
    static let minAngle = 140.0
    static let maxAngle = 220.0

    @Environment(\.colorScheme) private var scheme

    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height - 12)
            let radius = min(geo.size.width / 2, geo.size.height) - 16
            let kind = SignKind.lovibond
            let low = kind.threshold - kind.margin, high = kind.threshold + kind.margin
            ZStack {
                zone(from: Self.minAngle, to: low, color: Theme.aligned, center: center, radius: radius)
                zone(from: low, to: high, color: Theme.adjusting, center: center, radius: radius)
                zone(from: high, to: Self.maxAngle, color: Theme.attention, center: center, radius: radius)

                Path { p in
                    p.move(to: point(kind.threshold, center, radius - 16))
                    p.addLine(to: point(kind.threshold, center, radius + 12))
                }
                .stroke(Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Text(kind.formattedThreshold)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.7))
                    .position(point(kind.threshold, center, radius + 24))

                let color = ResultView.color(for: kind.status(of: angle))
                Path { p in
                    p.move(to: center)
                    p.addLine(to: point(angle, center, radius - 22))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .position(center)
            }
        }
    }

    /// Dial angle: 140° sits at the left end, 220° at the right end.
    private func point(_ value: Double, _ center: CGPoint, _ radius: CGFloat) -> CGPoint {
        let clamped = min(max(value, Self.minAngle), Self.maxAngle)
        let theta = Double.pi + (clamped - Self.minAngle) / (Self.maxAngle - Self.minAngle) * Double.pi
        return CGPoint(x: center.x + radius * CGFloat(cos(theta)), y: center.y + radius * CGFloat(sin(theta)))
    }

    private func zone(from a: Double, to b: Double, color: Color, center: CGPoint, radius: CGFloat) -> some View {
        Path { p in
            let steps = 30
            for i in 0...steps {
                let v = a + (b - a) * Double(i) / Double(steps)
                let pt = point(v, center, radius)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
        // Stronger on white (Classic), where pale zones wash out.
        .stroke(color.opacity(scheme == .light ? 0.55 : 0.35), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
    }
}

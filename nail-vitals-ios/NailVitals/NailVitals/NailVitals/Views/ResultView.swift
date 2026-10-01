//
//  ResultView.swift
//  NailVitals
//
//  Shows the result after capture: the profile (Lovibond) angle on the
//  dial, the combined verdict from all three signs (ClubbingAssessment), and
//  a row with each sign against its published cut-off. MUST include the
//  "screening aid, not a diagnosis" framing every time -- this is a
//  legal and ethical requirement stated in the project spec, not
//  optional copy.
//
//  With 3 or more readings in a session, each sign's middle value is used:
//  single readings of the same finger vary by a few degrees with pose.
//

import SwiftUI

struct ResultView: View {
    /// This session's readings, oldest first, ending with the one just taken.
    let readings: [FingerSigns]

    @State private var shown: Double = ResultGauge.minAngle
    @State private var showAbout = false

    private var assessment: ClubbingAssessment { ClubbingAssessment(readings: readings) }
    private var steady: Bool { readings.count >= ClubbingAssessment.readingsForSteadyResult }
    private var headline: Double? { assessment.values[.lovibond] }

    var body: some View {
        VStack(spacing: 18) {
            if headline != nil {
                VStack(spacing: 14) {
                    if steady {
                        Text("Middle of \(readings.count) readings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    ResultGauge(angle: shown)
                        .frame(width: 260, height: 150)
                    VStack(spacing: 2) {
                        CountingAngle(value: shown)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                        Text("Profile (Lovibond) angle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    verdict
                    signRow
                    Button {
                        showAbout = true
                    } label: {
                        Label("About these measurements", systemImage: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.searching)
                    }
                    if !steady {
                        Text(steadierHint)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
                .glassPanel(cornerRadius: 24)
            } else {
                VStack(spacing: 10) {
                    Text("Couldn't get a reliable measurement")
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("Please retake the photo with your finger turned sideways.")
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .glassPanel(cornerRadius: 24)
            }

            Text("This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showAbout) { AboutMeasurementsView() }
        .onAppear {
            guard let headline else { return }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.8)) {
                shown = headline
            }
        }
        .onChange(of: headline) { _, newValue in
            guard let newValue else { return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { shown = newValue }
        }
    }

    private var steadierHint: String {
        let remaining = ClubbingAssessment.readingsForSteadyResult - readings.count
        return "For a steadier result, measure \(remaining) more time\(remaining == 1 ? "" : "s"). The app will use the middle values."
    }

    static func color(for verdict: ClubbingAssessment.Verdict) -> Color {
        switch verdict {
        case .typical: return Theme.aligned
        case .measureAgain: return Theme.adjusting
        case .worthDiscussing: return Theme.attention
        }
    }

    static func color(for status: SignStatus) -> Color {
        switch status {
        case .typical: return Theme.aligned
        case .nearThreshold: return Theme.adjusting
        case .above: return Theme.attention
        }
    }

    private var verdict: some View {
        let a = assessment
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
        return VStack(spacing: 6) {
            Text(a.verdict.label)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Self.color(for: a.verdict))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var signRow: some View {
        HStack(spacing: 8) {
            ForEach(SignKind.allCases, id: \.self) { kind in
                SignChip(kind: kind, value: assessment.values[kind])
            }
        }
    }
}

/// One sign: its value, a status icon, and the published cut-off.
private struct SignChip: View {
    let kind: SignKind
    let value: Double?

    private var shortTitle: String {
        switch kind {
        case .lovibond: return "Profile"
        case .hyponychial: return "Hyponychial"
        case .depthRatio: return "Depth ratio"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            if let value {
                let status = kind.status(of: value)
                Image(systemName: icon(for: status))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ResultView.color(for: status))
                Text(kind.formatted(value))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.white)
            } else {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("—")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Text(shortTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            Text(value == nil ? "not measured" : "limit \(kind.formattedThreshold)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func icon(for status: SignStatus) -> String {
        switch status {
        case .typical: return "checkmark.circle.fill"
        case .nearThreshold: return "circle.lefthalf.filled"
        case .above: return "exclamationmark.circle.fill"
        }
    }
}

/// The reading as text, counting smoothly while it animates.
private struct CountingAngle: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(String(format: "%.1f°", value))
            .monospacedDigit()
    }
}

/// Semicircular dial from 140° to 220° for the profile angle, with zones
/// around the 176° cut-off (typical, within measurement error, above) and
/// a needle.
struct ResultGauge: View, Animatable {
    static let minAngle = 140.0
    static let maxAngle = 220.0

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
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Text(kind.formattedThreshold)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .position(point(kind.threshold, center, radius + 24))

                let color = ResultView.color(for: kind.status(of: angle))
                Path { p in
                    p.move(to: center)
                    p.addLine(to: point(angle, center, radius - 22))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .shadow(color: color.opacity(0.8), radius: 6)
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .shadow(color: color, radius: 6)
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
        .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
    }
}

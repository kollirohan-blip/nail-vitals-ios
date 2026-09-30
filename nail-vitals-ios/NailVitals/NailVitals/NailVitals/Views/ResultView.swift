//
//  ResultView.swift
//  NailVitals
//
//  Shows the measured Lovibond angle after capture. MUST include the
//  "screening aid, not a diagnosis" framing every time -- this is a
//  legal and ethical requirement stated in the project spec, not
//  optional copy.
//
//  With 3 or more readings in a session, the middle value is the headline:
//  single readings of the same finger vary by a few degrees with pose.
//

import SwiftUI

struct ResultView: View {
    let candidate: LovibondCandidate
    /// Every plausible reading this session, including this one.
    let sessionReadings: [Double]

    private static let readingsForSteadyResult = 3

    @State private var shown: Double = ResultGauge.minAngle

    private var headline: Double {
        sessionReadings.count >= Self.readingsForSteadyResult ? median(sessionReadings) : candidate.angleDegrees
    }

    var body: some View {
        VStack(spacing: 18) {
            if AngleAnalyzer.plausibleRange.contains(candidate.angleDegrees) {
                VStack(spacing: 14) {
                    if sessionReadings.count >= Self.readingsForSteadyResult {
                        Text("Middle of \(sessionReadings.count) readings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    ResultGauge(angle: shown)
                        .frame(width: 260, height: 150)
                    CountingAngle(value: shown)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    interpretation
                    if sessionReadings.count > 1 {
                        Text("This session: " + sessionReadings.map { String(format: "%.1f°", $0) }.joined(separator: ", "))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if sessionReadings.count < Self.readingsForSteadyResult {
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
                        .font(.system(size: 22, weight: .bold, design: .rounded))
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
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.8)) {
                shown = headline
            }
        }
        .onChange(of: headline) { _, newValue in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { shown = newValue }
        }
    }

    private var steadierHint: String {
        let remaining = Self.readingsForSteadyResult - sessionReadings.count
        return "For a steadier result, measure \(remaining) more time\(remaining == 1 ? "" : "s"). The app will use the middle value."
    }

    /// Short label for a reading, shared with the Q&A screen. Reference
    /// context around the widely cited 180° threshold (Lovibond: normal
    /// fingers measure well below 180°; clubbing reaches or exceeds it).
    /// Readings shift a few degrees between photos, so values just under
    /// 180° ask for a re-measure rather than reading as clear.
    static func rangeLabel(for angle: Double) -> String {
        switch angle {
        case ..<175: return "Typical range"
        case ..<180: return "Close to 180°"
        default: return "At or above 180°"
        }
    }

    static func rangeColor(for angle: Double) -> Color {
        switch angle {
        case ..<175: return Theme.aligned
        case ..<180: return Theme.adjusting
        default: return Theme.attention
        }
    }

    private var interpretation: some View {
        let detail: String
        switch headline {
        case ..<175:
            detail = "Healthy fingers measure below 180°."
        case ..<180:
            detail = "Readings this close to 180° can shift by a few degrees. Measure again to confirm."
        default:
            detail = "This is the range where clubbing is considered. Worth mentioning to a doctor, along with any symptoms you've noticed."
        }
        return VStack(spacing: 6) {
            Text(Self.rangeLabel(for: headline))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(Self.rangeColor(for: headline))
            Text(detail)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
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

/// Semicircular dial from 140° to 220° with colored zones, a 180° tick and
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
            ZStack {
                zone(from: Self.minAngle, to: 175, color: Theme.aligned, center: center, radius: radius)
                zone(from: 175, to: 180, color: Theme.adjusting, center: center, radius: radius)
                zone(from: 180, to: Self.maxAngle, color: Theme.attention, center: center, radius: radius)

                Path { p in
                    p.move(to: point(180, center, radius - 16))
                    p.addLine(to: point(180, center, radius + 12))
                }
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Text("180°")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .position(point(180, center, radius + 24))

                let color = ResultView.rangeColor(for: angle)
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

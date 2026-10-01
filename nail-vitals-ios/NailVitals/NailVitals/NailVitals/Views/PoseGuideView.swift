//
//  PoseGuideView.swift
//  NailVitals
//
//  "How to hold your finger": shown once after the first launch and from
//  the "?" button on the camera screen. The reference study (Husarik 2002)
//  fixed the finger's position to avoid rotation; a home user has only
//  these instructions, so they are part of the measurement.
//

import SwiftUI

struct PoseGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        ("hand.point.up.left.fill", "Use your right index finger. The left is fine too; switch it at the top of the camera screen."),
        ("rectangle.portrait", "Point it straight up in front of a plain, light wall, in good light."),
        ("circle.circle", "Rings can stay on. If the app can't find your finger, try taking off rings on that finger."),
        ("flashlight.on.fill", "In dim light or with harsh shadows, tap the light button at the top."),
        ("rotate.3d", "Turn your hand so the camera sees the side of your finger. The nail should look like a thin edge, not a flat surface."),
        ("hand.raised", "Keep the finger straight and steady. Resting your elbow on a table helps."),
        ("checkmark.circle", "When the outline turns green, hold still: the photo takes itself when the ring fills. Measure 3 times for a steadier result."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("How to hold your finger")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 28)

                HStack(spacing: 14) {
                    example(good: true, caption: "Side view: nail seen edge-on") {
                        FingerProfileShape()
                            .stroke(Theme.aligned, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            .shadow(color: Theme.aligned.opacity(0.6), radius: 8)
                    }
                    example(good: false, caption: "Nail facing the camera") {
                        FingerFrontShape()
                            .stroke(Theme.attention, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            .shadow(color: Theme.attention.opacity(0.5), radius: 8)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: step.0)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Theme.searching)
                                .frame(width: 26)
                            Text(step.1)
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(18)
                .glassPanel(cornerRadius: 20)

                Button("Got it") { dismiss() }
                    .buttonStyle(GlowButtonStyle(color: Theme.searching))
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func example(good: Bool, caption: String, @ViewBuilder drawing: () -> some View) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                drawing()
                    .frame(width: 90, height: 110)
                    .padding(12)
                Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, good ? Theme.aligned : Theme.attention)
            }
            Text(caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(height: 34, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// A finger pointing up with the nail facing the viewer: the flat nail
/// plate shows, which hides the profile the app measures.
private struct FingerFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.22, 1.0))
        path.addLine(to: p(0.22, 0.3))
        path.addCurve(to: p(0.78, 0.3), control1: p(0.22, -0.05), control2: p(0.78, -0.05))
        path.addLine(to: p(0.78, 1.0))
        // The nail plate
        path.addRoundedRect(in: CGRect(x: rect.minX + 0.33 * rect.width, y: rect.minY + 0.1 * rect.height,
                                       width: 0.34 * rect.width, height: 0.32 * rect.height),
                            cornerSize: CGSize(width: 0.14 * rect.width, height: 0.12 * rect.height))
        return path
    }
}

#Preview {
    PoseGuideView()
}

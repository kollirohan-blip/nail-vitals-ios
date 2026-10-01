//
//  LabelGuideView.swift
//  NailVitals
//
//  "Where do the points go?" for Label mode: a drawn side view of a
//  fingertip with all seven points marked. A drawing, not a photo, so it
//  can't steer where a labeler taps on the real pictures.
//

import SwiftUI

struct LabelGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    LabelGuideDiagram()
                        .frame(width: 300, height: 380)
                    VStack(alignment: .leading, spacing: 10) {
                        tip("Cuticle", "where the nail meets the skin fold, on the nail's edge.")
                        tip("Nail", "on the nail's edge, about halfway from the cuticle to the tip.")
                        tip("Skin", "on the skin's edge below the cuticle, about as far as the nail point is above it.")
                        tip("Crease", "the wrinkle lines across the back of the finger over the last knuckle, usually 1 to 1½ nail-lengths below the cuticle. Tap the finger's edge level with them, not the middle of the finger. No wrinkles visible? Use where the finger would bend at that joint.")
                        tip("Nail tip", "on the nail side, where the nail ends at the fingertip.")
                        tip("Across", "the opposite edge of the finger, straight across from the cuticle, then from the crease.")
                    }
                    .padding(16)
                    .glassPanel(cornerRadius: 18)
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Where the points go")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func tip(_ name: String, _ text: String) -> some View {
        (Text(name + ": ").bold() + Text(text))
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Side view of a fingertip pointing up, nail on the right, with the seven
/// label points.
struct LabelGuideDiagram: View {
    // Unit coordinates (x across, y down) in the drawing's box.
    private static let freeEdge = CGPoint(x: 0.66, y: 0.12)
    private static let nail = CGPoint(x: 0.70, y: 0.22)
    private static let cuticle = CGPoint(x: 0.72, y: 0.33)
    private static let skin = CGPoint(x: 0.735, y: 0.43)
    private static let crease = CGPoint(x: 0.75, y: 0.62)
    private static let cuticleAcross = CGPoint(x: 0.24, y: 0.33)
    private static let creaseAcross = CGPoint(x: 0.24, y: 0.62)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            let p: (CGPoint) -> CGPoint = { CGPoint(x: $0.x * s.width, y: $0.y * s.height) }
            ZStack {
                // Finger outline.
                Path { path in
                    path.move(to: p(CGPoint(x: 0.24, y: 1.0)))
                    path.addLine(to: p(CGPoint(x: 0.24, y: 0.2)))
                    path.addQuadCurve(to: p(CGPoint(x: 0.45, y: 0.04)), control: p(CGPoint(x: 0.25, y: 0.04)))
                    path.addQuadCurve(to: p(Self.freeEdge), control: p(CGPoint(x: 0.62, y: 0.04)))
                    path.addLine(to: p(Self.nail))
                    path.addLine(to: p(Self.cuticle))
                    path.addLine(to: p(Self.skin))
                    path.addQuadCurve(to: p(Self.crease), control: p(CGPoint(x: 0.745, y: 0.53)))
                    path.addQuadCurve(to: p(CGPoint(x: 0.76, y: 1.0)), control: p(CGPoint(x: 0.77, y: 0.8)))
                }
                .stroke(Theme.searching, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                // Nail plate seen edge-on, and the skin fold over it.
                Path { path in
                    path.move(to: p(Self.freeEdge))
                    path.addLine(to: p(Self.nail))
                    path.addLine(to: p(Self.cuticle))
                    path.addLine(to: p(CGPoint(x: 0.665, y: 0.34)))
                    path.addLine(to: p(CGPoint(x: 0.64, y: 0.22)))
                    path.addLine(to: p(CGPoint(x: 0.61, y: 0.13)))
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(0.25))

                // Wrinkles over the last knuckle.
                Path { path in
                    for y in [0.585, 0.62, 0.655] {
                        path.move(to: p(CGPoint(x: 0.6, y: y + 0.01)))
                        path.addQuadCurve(to: p(CGPoint(x: 0.745, y: y)), control: p(CGPoint(x: 0.67, y: y - 0.012)))
                    }
                }
                .stroke(Color.white.opacity(0.55), lineWidth: 1.5)

                // Measurement lines.
                Path { path in
                    path.move(to: p(Self.cuticle)); path.addLine(to: p(Self.cuticleAcross))
                    path.move(to: p(Self.crease)); path.addLine(to: p(Self.creaseAcross))
                }
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                marker(p(Self.freeEdge), "Nail tip", .orange, dx: 46)
                marker(p(Self.nail), "Nail", .yellow, dx: 34)
                marker(p(Self.cuticle), "Cuticle", .pink, dx: 44)
                marker(p(Self.skin), "Skin", .cyan, dx: 32)
                marker(p(Self.crease), "Crease", Theme.aligned, dx: 42)
                marker(p(Self.cuticleAcross), "Across", .white, dx: -38)
                marker(p(Self.creaseAcross), "Across", .white, dx: -38)
            }
        }
    }

    private func marker(_ at: CGPoint, _ name: String, _ color: Color, dx: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                .frame(width: 11, height: 11)
                .position(at)
            Text(name)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
                .fixedSize()
                .position(x: at.x + dx, y: at.y)
        }
    }
}

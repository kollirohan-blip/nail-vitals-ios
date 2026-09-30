//
//  CaptureGuideOverlay.swift
//  NailVitals
//
//  Live capture overlay: corner brackets that follow the real fingertip
//  (from the hand-pose joints), colored by capture state -- cyan searching,
//  amber adjusting, green aligned (brackets tighten and a check appears).
//  With no hand in view, the brackets rest in the middle as a target.
//

import SwiftUI
import UIKit  // UIImpactFeedbackGenerator

enum CaptureState {
    case searching
    case adjusting
    case aligned
}

struct CaptureGuideOverlay: View {
    let state: CaptureState
    let instructionText: String
    let subText: String
    let hand: HandLandmarks?
    /// Live glowing finger outline; when nil, the corner brackets show.
    var outline: FingerOutline? = nil

    private var color: Color { Theme.color(for: state) }

    var body: some View {
        ZStack {
            // Same full-screen coordinate space as the aspect-fill preview,
            // so the brackets line up with the finger on screen.
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.25)
                    if let outline {
                        let mapping = PreviewMapping(imageSize: outline.imageSize, viewSize: geometry.size)
                        LiveFingerOutline(points: outline.points.map(mapping.toView),
                                          cuticle: outline.cuticle.map(mapping.toView),
                                          state: state)
                            .transition(.opacity)
                    } else {
                        reticle(in: targetRect(viewSize: geometry.size))
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: outline == nil)
            }
            .ignoresSafeArea()

            VStack {
                if state != .aligned {
                    poseHint.padding(.top, 12)
                }
                Spacer()
                VStack(spacing: 6) {
                    Text(instructionText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(color == Theme.searching ? .white : color)
                    Text(subText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassPanel(cornerRadius: 20)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .animation(.easeInOut(duration: 0.25), value: state)
        }
        .onChange(of: state) { _, newValue in
            if newValue == .aligned {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    private func reticle(in rect: CGRect) -> some View {
        let aligned = state == .aligned
        return ZStack(alignment: .topTrailing) {
            CornerBrackets(armLength: min(30, rect.width * 0.28))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.7), radius: 8)
            if aligned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.aligned)
                    .offset(x: 13, y: -13)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: rect.width, height: rect.height)
        .scaleEffect(aligned ? 0.92 : 1)
        .phaseAnimator([1.0, 0.45]) { content, phase in
            content.opacity(state == .searching ? phase : 1)
        } animation: { _ in .easeInOut(duration: 1.1) }
        .position(x: rect.midX, y: rect.midY)
        .animation(.easeOut(duration: 0.25), value: rect)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: aligned)
    }

    /// Box around the fingertip's end segment (tip to DIP joint, extended a
    /// little past the tip since the tip joint sits inside the pad), mapped
    /// with the preview's aspect-fill scaling. A centered target when no
    /// hand is found.
    private func targetRect(viewSize: CGSize) -> CGRect {
        guard let hand else {
            let size = CGSize(width: 150, height: 220)
            return CGRect(x: (viewSize.width - size.width) / 2, y: viewSize.height * 0.4 - size.height / 2,
                          width: size.width, height: size.height)
        }
        let mapping = PreviewMapping(imageSize: hand.imageSize, viewSize: viewSize)
        let tip = mapping.toView(hand.indexTip.point), dip = mapping.toView(hand.indexDIP.point)
        let length = max(hypot(tip.x - dip.x, tip.y - dip.y), 40)
        let top = min(tip.y, dip.y) - length * 0.45
        let bottom = max(tip.y, dip.y) + length * 0.3
        let width = max(length * 1.15, 90)
        return CGRect(x: (tip.x + dip.x) / 2 - width / 2, y: top, width: width, height: bottom - top)
    }

    private var poseHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 15))
            Text("Side view: nail edge facing left or right")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.opacity)
    }
}

/// Four L-shaped corners of a rectangle.
private struct CornerBrackets: Shape {
    let armLength: CGFloat

    func path(in rect: CGRect) -> Path {
        let a = min(armLength, rect.width / 2, rect.height / 2)
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x + a * dx, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + a * dy))
        }
        return path
    }
}

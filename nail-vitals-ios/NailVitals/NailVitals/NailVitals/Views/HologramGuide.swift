//
//  HologramGuide.swift
//  NailVitals
//
//  The hologram "glove": a glowing ghost finger, seen from the side, at the
//  position and size every capture should have (GuidanceTarget). People
//  slide their finger into it instead of reading instructions. Its edge
//  fills in as the finger fits better, it turns green when the fit is good,
//  and an arrow beside it says which way to move.
//

import SwiftUI

struct HologramGuide: View {
    let state: CaptureState
    /// 0...1, how well the finger fills the hologram.
    let fit: Double
    /// Draw the nail on the right edge (else the left), to match the hand.
    let nailOnRight: Bool
    /// The most useful next move, or nil.
    let direction: GuidanceDirection?
    /// The camera frame's size, for mapping the target onto the screen.
    let frameSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch state {
        case .searching: return Theme.searching
        case .adjusting: return fit > 0.45 ? Theme.searching : Theme.adjusting
        case .aligned: return Theme.aligned
        }
    }

    var body: some View {
        GeometryReader { geo in
            let mapping = PreviewMapping(imageSize: frameSize, viewSize: geo.size)
            let tip = mapping.toView(GuidanceTarget.tip(in: frameSize))
            let mcp = mapping.toView(GuidanceTarget.mcp(in: frameSize))
            let length = mcp.y - tip.y
            // The drawn finger runs a little past the tip joint (which sits
            // inside the pad) and below the knuckle.
            let rect = CGRect(x: tip.x - length * 0.13, y: tip.y - length * 0.09,
                              width: length * 0.26, height: length * 1.14)
            let shape = HologramFingerShape(nailOnRight: nailOnRight)

            ZStack {
                // Body: soft gradient fill with drifting scan lines.
                shape
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        TimelineView(.animation(paused: reduceMotion)) { timeline in
                            let t = timeline.date.timeIntervalSinceReferenceDate
                            ScanLines(offset: CGFloat((t * 18).truncatingRemainder(dividingBy: 9)))
                                .stroke(color.opacity(0.18), lineWidth: 1)
                                .clipShape(shape)
                        }
                    }
                // Outline, glow, and the fit "progress" tracing round it.
                shape
                    .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .blur(radius: 6)
                shape
                    .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: state == .searching ? [8, 6] : []))
                shape
                    .trim(from: 0, to: state == .searching ? 0 : fit)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: color, radius: 8)
                    .animation(.easeOut(duration: 0.35), value: fit)
                // Nail plate and joint creases, as hints of the side view.
                HologramDetails(nailOnRight: nailOnRight)
                    .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .opacity(state == .searching && !reduceMotion ? 0.85 : 1)
            .phaseAnimator([1.0, 0.75]) { content, phase in
                content.opacity(state == .searching && !reduceMotion ? phase : 1)
            } animation: { _ in .easeInOut(duration: 1.2) }
            .scaleEffect(state == .aligned ? 1.03 : 1, anchor: .center)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: state == .aligned)

            if let direction, state != .aligned, let cue = DirectionCue(direction) {
                DirectionArrow(cue: cue, color: color)
                    .position(x: rect.maxX + 44 > geo.size.width - 30 ? rect.minX - 44 : rect.maxX + 44,
                              y: rect.minY + rect.height * 0.32)
                    .transition(.opacity.combined(with: .scale))
                    .id(cue.symbol)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A finger seen from the side, pointing up, in a unit-proportioned rect:
/// rounded tip, nail side with knuckle bumps at the DIP and PIP joints,
/// pad side straight. The path starts at the bottom of the pad side so a
/// trim traces up and round the tip.
struct HologramFingerShape: Shape {
    let nailOnRight: Bool

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (nailOnRight ? x : 1 - x) * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.10, 1.0))
        path.addLine(to: p(0.08, 0.40))
        path.addQuadCurve(to: p(0.10, 0.14), control: p(0.06, 0.22))
        path.addCurve(to: p(0.86, 0.12), control1: p(0.16, -0.03), control2: p(0.80, -0.03))
        path.addLine(to: p(0.90, 0.26))
        path.addQuadCurve(to: p(0.91, 0.36), control: p(0.96, 0.31))   // DIP knuckle
        path.addLine(to: p(0.90, 0.56))
        path.addQuadCurve(to: p(0.92, 0.68), control: p(0.99, 0.62))   // PIP knuckle
        path.addLine(to: p(0.92, 1.0))
        return path
    }
}

/// Nail plate along the nail side near the tip, and short creases at the
/// two joints on the pad side.
private struct HologramDetails: Shape {
    let nailOnRight: Bool

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (nailOnRight ? x : 1 - x) * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.66, 0.05))
        path.addQuadCurve(to: p(0.74, 0.25), control: p(0.74, 0.12))
        path.addLine(to: p(0.88, 0.25))
        for y in [0.32, 0.60] {
            path.move(to: p(0.08, y))
            path.addLine(to: p(0.26, y + 0.01))
        }
        return path
    }
}

private struct ScanLines: Shape {
    let offset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var y = rect.minY - offset
        while y < rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += 9
        }
        return path
    }
}

/// An icon for the next move.
struct DirectionCue {
    let symbol: String
    let nudge: CGSize

    init?(_ direction: GuidanceDirection) {
        switch direction {
        case .moveLeft: symbol = "arrow.left"; nudge = CGSize(width: -6, height: 0)
        case .moveRight: symbol = "arrow.right"; nudge = CGSize(width: 6, height: 0)
        case .moveUp: symbol = "arrow.up"; nudge = CGSize(width: 0, height: -6)
        case .moveHandDown: symbol = "arrow.down"; nudge = CGSize(width: 0, height: 6)
        case .moveCloser: symbol = "arrow.up.left.and.arrow.down.right"; nudge = .zero
        case .moveBack: symbol = "arrow.down.right.and.arrow.up.left"; nudge = .zero
        case .turnToSide: symbol = "rotate.3d"; nudge = .zero
        case .straighten: symbol = "hand.point.up.left.fill"; nudge = .zero
        case .noFingerDetected, .looksGood: return nil
        }
    }
}

private struct DirectionArrow: View {
    let cue: DirectionCue
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: cue.symbol)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.black)
            .frame(width: 48, height: 48)
            .background(Circle().fill(color))
            .shadow(color: color.opacity(0.8), radius: 10)
            .phaseAnimator([CGSize.zero, cue.nudge]) { content, offset in
                content.offset(reduceMotion ? .zero : offset)
            } animation: { _ in .easeInOut(duration: 0.6) }
    }
}

//
//  HologramGuide.swift
//  NailVitals
//
//  The landing zone: a faint, still target showing where the finger goes
//  (GuidanceTarget) -- thin corner marks around the finger's place and a
//  small crosshair where the fingertip should sit. It fades out as the
//  finger moves in and the glove (FingerGlove) takes over.
//

import SwiftUI

struct LandingZone: View {
    /// 0...1, how well the finger fills the target; the zone fades as it rises.
    let fit: Double
    /// Shows "Hold your index finger up here" under the zone.
    let searching: Bool
    /// The camera frame's size, for mapping the target onto the screen.
    let frameSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let mapping = PreviewMapping(imageSize: frameSize, viewSize: geo.size)
            let tip = mapping.toView(GuidanceTarget.tip(in: frameSize))
            let mcp = mapping.toView(GuidanceTarget.mcp(in: frameSize))
            let length = mcp.y - tip.y
            // About as wide as a side-on finger, a little past the tip.
            let rect = CGRect(x: tip.x - length * 0.2, y: tip.y - length * 0.12,
                              width: length * 0.4, height: length * 1.12)

            ZStack {
                CornerMarks(arm: min(28, rect.width * 0.25))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                Crosshair()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .position(tip)
            }
            .opacity(0.3 + (searching ? 0.15 : 0))
            .opacity(1 - min(1, fit))

            if searching {
                Text("Hold your index finger up here")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .phaseAnimator([1.0, 0.55]) { content, phase in
                        content.opacity(reduceMotion ? 1 : phase)
                    } animation: { _ in .easeInOut(duration: 1.1) }
                    .position(x: rect.midX, y: min(rect.maxY + 34, geo.size.height - 150))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: searching)
        .animation(.easeOut(duration: 0.3), value: fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Four L-shaped corners of the rect.
private struct CornerMarks: Shape {
    let arm: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        return path
    }
}

/// A small ring with ticks, where the fingertip goes.
private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.width * 0.28
        path.addEllipse(in: CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY)); path.addLine(to: CGPoint(x: rect.midX - r, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX + r, y: rect.midY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - r))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY + r)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// An icon for the next move.
struct DirectionCue {
    let symbol: String

    init?(_ direction: GuidanceDirection) {
        switch direction {
        case .moveLeft: symbol = "arrow.left"
        case .moveRight: symbol = "arrow.right"
        case .moveUp: symbol = "arrow.up"
        case .moveHandDown: symbol = "arrow.down"
        case .moveCloser: symbol = "arrow.up.left.and.arrow.down.right"
        case .moveBack: symbol = "arrow.down.right.and.arrow.up.left"
        case .turnToSide: symbol = "rotate.3d"
        case .straighten: symbol = "hand.point.up.left.fill"
        case .noFingerDetected, .looksGood: return nil
        }
    }
}

//
//  LiveFingerOutline.swift
//  NailVitals
//
//  The glowing line that hugs the finger while framing a capture. The
//  outline's points are animatable, so each update (a few per second)
//  morphs smoothly into the next instead of jumping.
//

import SwiftUI

struct LiveFingerOutline: View {
    /// Outline points in view coordinates (fixed count, see LiveOutlineTracker).
    let points: [CGPoint]
    let cuticle: CGPoint?
    let state: CaptureState

    private var color: Color { Theme.color(for: state) }
    private var aligned: Bool { state == .aligned }

    var body: some View {
        let shape = OutlineShape(points: AnimatablePoints(points))
        ZStack {
            // Soft glow underneath, stronger once aligned.
            shape
                .stroke(color.opacity(aligned ? 0.85 : 0.55), style: StrokeStyle(lineWidth: aligned ? 16 : 10, lineCap: .round, lineJoin: .round))
                .blur(radius: aligned ? 10 : 7)
            shape
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            // A short bright highlight that travels along the line.
            TimelineView(.animation) { timeline in
                let phase = CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2)
                shape
                    .trim(from: max(0, phase - 0.12), to: phase)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .blur(radius: 1)
            }
            if let cuticle {
                CuticleMarker(color: color)
                    .position(cuticle)
            }
        }
        .animation(.easeOut(duration: 0.3), value: AnimatablePoints(points))
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: aligned)
        .animation(.easeOut(duration: 0.3), value: cuticle)
        .allowsHitTesting(false)
    }
}

/// Pulsing dot where the cuticle will be measured.
private struct CuticleMarker: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 22, height: 22)
                .phaseAnimator([0.6, 1.0]) { ring, phase in
                    ring.scaleEffect(phase).opacity(1.4 - phase)
                } animation: { _ in .easeInOut(duration: 0.9) }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color, radius: 6)
        }
    }
}

/// Smooth curve through the points (midpoint quadratic smoothing).
private struct OutlineShape: Shape {
    var points: AnimatablePoints

    var animatableData: AnimatablePoints {
        get { points }
        set { points = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = points.cgPoints
        var path = Path()
        guard p.count > 2 else { return path }
        path.move(to: p[0])
        for i in 1..<(p.count - 1) {
            let mid = CGPoint(x: (p[i].x + p[i + 1].x) / 2, y: (p[i].y + p[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: p[i])
        }
        path.addLine(to: p[p.count - 1])
        return path
    }
}

/// A list of points SwiftUI can interpolate between (x0, y0, x1, y1, ...).
struct AnimatablePoints: VectorArithmetic {
    var values: [CGFloat]

    init(_ points: [CGPoint]) {
        values = points.flatMap { [$0.x, $0.y] }
    }

    private init(values: [CGFloat]) {
        self.values = values
    }

    var cgPoints: [CGPoint] {
        stride(from: 0, to: values.count - 1, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) }
    }

    static var zero: AnimatablePoints { AnimatablePoints(values: []) }

    static func + (lhs: AnimatablePoints, rhs: AnimatablePoints) -> AnimatablePoints {
        combine(lhs, rhs, +)
    }

    static func - (lhs: AnimatablePoints, rhs: AnimatablePoints) -> AnimatablePoints {
        combine(lhs, rhs, -)
    }

    mutating func scale(by rate: Double) {
        values = values.map { $0 * CGFloat(rate) }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + Double($1 * $1) }
    }

    /// Element-wise; an empty side (the zero vector) acts as all zeros.
    private static func combine(_ lhs: AnimatablePoints, _ rhs: AnimatablePoints,
                                _ op: (CGFloat, CGFloat) -> CGFloat) -> AnimatablePoints {
        if lhs.values.isEmpty { return AnimatablePoints(values: rhs.values.map { op(0, $0) }) }
        if rhs.values.isEmpty { return lhs }
        let count = min(lhs.values.count, rhs.values.count)
        return AnimatablePoints(values: (0..<count).map { op(lhs.values[$0], rhs.values[$0]) })
    }
}

//
//  FingerGlove.swift
//  NailVitals
//
//  The hologram glove: the live outline of the user's own finger, drawn as
//  a glowing translucent sleeve that molds to it as it moves (soft fill,
//  drifting scan lines, a thin rim and a light sweeping up the finger).
//  A small pill above the fingertip says what to do. When everything lines
//  up it locks: the glove turns green, nodes snap onto the fingertip,
//  cuticle and knuckle crease, and a line draws through them.
//

import SwiftUI

struct FingerGlove: View {
    /// Outline points in view coordinates (fixed count, see LiveOutlineTracker).
    let points: [CGPoint]
    let tip: CGPoint?
    let cuticle: CGPoint?
    let crease: CGPoint?
    let color: Color
    let locked: Bool
    /// What to do next, and its icon; hidden when empty.
    let instruction: String
    let symbol: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineProgress: CGFloat
    @State private var nodePop: Bool

    init(points: [CGPoint], tip: CGPoint?, cuticle: CGPoint?, crease: CGPoint?, color: Color,
         locked: Bool, instruction: String, symbol: String?) {
        self.points = points
        self.tip = tip
        self.cuticle = cuticle
        self.crease = crease
        self.color = color
        self.locked = locked
        self.instruction = instruction
        self.symbol = symbol
        // Already locked when it appears: show the nodes and line straight away.
        _lineProgress = State(initialValue: locked ? 1 : 0)
        _nodePop = State(initialValue: locked)
    }

    var body: some View {
        let glove = GloveShape(points: AnimatablePoints(points), closed: true)
        let rim = GloveShape(points: AnimatablePoints(points), closed: false)
        ZStack {
            // Sleeve: fill, scan lines, a sweep of light and the rim, fading
            // out toward the base so it reads as a glove, not a cut-out.
            ZStack {
                glove
                    .fill(color.opacity(locked ? 0.26 : 0.18))
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let phase = CGFloat((t / 2.0).truncatingRemainder(dividingBy: 1))
                    ZStack {
                        GloveScanLines(offset: CGFloat((t * 20).truncatingRemainder(dividingBy: 8)))
                            .stroke(color.opacity(0.16), lineWidth: 1)
                        // Travels from the base up past the tip every 2 s.
                        LinearGradient(colors: [.clear, color.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(width: bounds.width + 40, height: 70)
                            .position(x: bounds.midX, y: bounds.maxY + 35 - (bounds.height + 70) * phase)
                    }
                    .clipShape(glove)
                }
                // Rim: soft glow under a thin bright line, open across the base.
                rim
                    .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .blur(radius: 7)
                rim
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .mask { baseFade }

            // On lock: the line through the three anchor points, then the nodes.
            if locked, let tip, let cuticle {
                let anchors = [tip, cuticle] + (crease.map { [$0] } ?? [])
                Path { $0.addLines(anchors) }
                    .trim(from: 0, to: lineProgress)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
                    .shadow(color: color, radius: 4)
                ForEach(Array(anchors.enumerated()), id: \.offset) { _, point in
                    GloveNode(color: color)
                        .scaleEffect(nodePop ? 1 : 0.2)
                        .opacity(nodePop ? 1 : 0)
                        .position(point)
                }
            }

            if !instruction.isEmpty, let tip {
                InstructionPill(text: instruction, symbol: symbol, color: color)
                    .position(x: tip.x, y: max(tip.y - 52, 40))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .id(instruction)
            }
        }
        .animation(.easeOut(duration: 0.3), value: AnimatablePoints(points))
        .animation(.easeInOut(duration: 0.25), value: instruction)
        .onChange(of: locked) { _, isLocked in
            if isLocked {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { nodePop = true }
                withAnimation(.easeOut(duration: 0.5).delay(0.1)) { lineProgress = 1 }
            } else {
                nodePop = false
                lineProgress = 0
            }
        }
        .allowsHitTesting(false)
    }
}

extension FingerGlove {
    /// The outline's bounding box.
    private var bounds: CGRect {
        guard let first = points.first else { return .zero }
        return points.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    /// Opaque from the tip to most of the way down, clear at the base (the
    /// middle of the outline's two ends).
    private var baseFade: some View {
        GeometryReader { geo in
            if let first = points.first, let last = points.last, let top = tip ?? points.min(by: { $0.y < $1.y }),
               geo.size.width > 0, geo.size.height > 0 {
                let base = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                       .init(color: .clear, location: 1)],
                               startPoint: UnitPoint(x: top.x / geo.size.width, y: top.y / geo.size.height),
                               endPoint: UnitPoint(x: base.x / geo.size.width, y: base.y / geo.size.height))
            }
        }
    }
}

/// "Move closer" with an arrow, in a small dark capsule.
struct InstructionPill: View {
    let text: String
    let symbol: String?
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
            }
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundColor(color)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

private struct GloveNode: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.5)
                .frame(width: 18, height: 18)
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
                .shadow(color: color, radius: 6)
        }
    }
}

/// The finger outline, smoothed; closed across its base for the fill.
private struct GloveShape: Shape {
    var points: AnimatablePoints
    let closed: Bool

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
        if closed { path.closeSubpath() }
        return path
    }
}

private struct GloveScanLines: Shape {
    let offset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var y = rect.minY - offset
        while y < rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += 8
        }
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

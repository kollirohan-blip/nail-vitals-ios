//
//  ManualAngleView.swift
//  NailVitals
//
//  Safety-net measurement: the user drags three dots onto the photo -- on
//  the nail plate, at the cuticle corner, on the skin behind it -- and the
//  Lovibond angle is computed from them. Used when automatic detection fails
//  or the user prefers to place the points themselves.
//

import SwiftUI

struct ManualAngleView: View {
    let image: UIImage
    let silhouette: DetectedSilhouette?
    let landmarks: HandLandmarks?
    /// Automatic cuticle marker to start from, if the user picked one.
    let suggestion: LovibondCandidate?
    let segmentLengthPixels: Double?
    /// Why the user was sent here, shown above the instructions.
    var note: String? = nil
    /// The confirmed reading plus the three dots (nail, cuticle, skin).
    let onConfirm: (LovibondCandidate, [CGPoint]) -> Void
    let onCancel: () -> Void

    // Image-pixel coordinates: [nail, cuticle, skin].
    @State private var points: [CGPoint] = []
    @State private var dragging: Int?
    @State private var grabOffset = CGSize.zero
    // Only used when neither the outline nor hand pose can say which side
    // is inside the finger.
    @State private var flipped = false

    private let colors: [Color] = [.yellow, .pink, .cyan]
    private let loupeSize: CGFloat = 150
    private let loupeZoom: CGFloat = 4
    private let snapRadiusPoints: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(dragNearestDot(viewSize: geo.size))

                if points.count == 3 {
                    Path { path in path.addLines(points.map { toView($0, geo.size) }) }
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    ForEach(0..<3, id: \.self) { i in
                        dot(i, viewSize: geo.size)
                    }
                }

                VStack {
                    if let i = dragging, points.count == 3 {
                        loupe(center: points[i], viewSize: geo.size)
                            .padding(.top, 12)
                    } else {
                        Text((note.map { $0 + "\n" } ?? "") + "On the nail edge: 1 about a quarter of the way up the nail, 2 exactly on the cuticle, 3 on the skin the same distance below 2")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .padding(14)
                            .glassPanel(cornerRadius: 16)
                            .padding(.top, 20)
                            .padding(.horizontal, 16)
                    }
                    Spacer()
                    controls.padding(.bottom, 40)
                }
            }
            .onAppear { if points.isEmpty { points = initialPoints() } }
        }
        .background(AppBackground())
    }

    // MARK: - Angle

    private var hasInsideInfo: Bool { silhouette != nil || landmarks != nil }

    private var angle: Double? {
        guard points.count == 3 else { return nil }
        return AngleAnalyzer.outsideAngle(nailPoint: points[0], cuticle: points[1], skinPoint: points[2], isInsideFinger: isInsideFinger)
    }

    private var isPlausible: Bool { angle.map { AngleAnalyzer.plausibleRange.contains($0) } ?? false }

    private func isInsideFinger(_ p: CGPoint) -> Bool? {
        if let contour = silhouette?.contourPoints { return contains(contour, p) }
        if let hand = landmarks {
            // Moving toward the finger's tip-to-DIP axis = moving inward.
            return distanceToAxis(p, hand) < distanceToAxis(points[1], hand)
        }
        return flipped
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            if let angle {
                Text("\(angle, specifier: "%.1f")°")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(isPlausible ? .primary : Theme.attention)
                    .monospacedDigit()
            }
            if angle != nil && !isPlausible {
                Text("That angle isn't realistic. Check the order along the edge: 1 on the nail, 2 at the cuticle, 3 further down the skin.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.attention)
                    .multilineTextAlignment(.center)
            }
            if !hasInsideInfo {
                Button(flipped ? "Nail fold bulges outward (tap to flip)" : "Nail fold dips inward (tap to flip)") {
                    flipped.toggle()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.adjusting)
            }
            HStack(spacing: 12) {
                Button("Retake", action: onCancel)
                    .buttonStyle(GhostButtonStyle())
                Button("Confirm", action: confirm)
                    .buttonStyle(GlowButtonStyle())
                    .disabled(!isPlausible)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 24)
        .padding(.horizontal, 16)
    }

    private func confirm() {
        guard let angle, isPlausible else { return }
        onConfirm(LovibondCandidate(side: "manual", angleDegrees: angle, inflectionPoint: points[1], inflectionIndex: 0, step: 0), points)
    }

    // MARK: - Dots and loupe

    private func dot(_ i: Int, viewSize: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(colors[i])
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                .frame(width: 12, height: 12)
            Text("\(i + 1)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(colors[i])
                .shadow(color: .black, radius: 2)
                .offset(x: 13, y: -13)
        }
        .position(toView(points[i], viewSize))
        .allowsHitTesting(false)
    }

    /// One gesture for all dots: grabs whichever dot is nearest the touch
    /// (stacked dots each had their own touch area, so the top one blocked
    /// the others), and keeps the finger's offset from the dot so the finger
    /// doesn't cover it.
    private func dragNearestDot(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil {
                    guard let i = nearestDot(to: value.startLocation, viewSize: viewSize) else { return }
                    dragging = i
                    let dot = toView(points[i], viewSize)
                    grabOffset = CGSize(width: dot.x - value.startLocation.x, height: dot.y - value.startLocation.y)
                }
                guard let i = dragging else { return }
                let target = CGPoint(x: value.location.x + grabOffset.width, y: value.location.y + grabOffset.height)
                points[i] = snapToOutline(toImage(target, viewSize), viewSize: viewSize)
            }
            .onEnded { _ in dragging = nil }
    }

    private func nearestDot(to location: CGPoint, viewSize: CGSize) -> Int? {
        guard points.count == 3 else { return nil }
        let distances = points.map { p -> CGFloat in
            let v = toView(p, viewSize)
            return hypot(v.x - location.x, v.y - location.y)
        }
        guard let best = distances.indices.min(by: { distances[$0] < distances[$1] }), distances[best] <= 60 else { return nil }
        return best
    }

    /// Magnified view around the dot being dragged, so a fingertip doesn't
    /// hide where it lands.
    private func loupe(center: CGPoint, viewSize: CGSize) -> some View {
        let scale = fitTransform(viewSize).scale * loupeZoom
        func toLoupe(_ p: CGPoint) -> CGPoint {
            CGPoint(x: loupeSize / 2 + (p.x - center.x) * scale, y: loupeSize / 2 + (p.y - center.y) * scale)
        }
        return ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .offset(x: loupeSize / 2 - center.x * scale, y: loupeSize / 2 - center.y * scale)
            Path { path in path.addLines(points.map(toLoupe)) }
                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(colors[i], lineWidth: 2)
                    .frame(width: 10, height: 10)
                    .position(toLoupe(points[i]))
            }
            Path { path in
                path.move(to: CGPoint(x: loupeSize / 2, y: loupeSize / 2 - 12))
                path.addLine(to: CGPoint(x: loupeSize / 2, y: loupeSize / 2 + 12))
                path.move(to: CGPoint(x: loupeSize / 2 - 12, y: loupeSize / 2))
                path.addLine(to: CGPoint(x: loupeSize / 2 + 12, y: loupeSize / 2))
            }
            .stroke(Color.white, lineWidth: 1)
        }
        .frame(width: loupeSize, height: loupeSize, alignment: .topLeading)
        .clipped()
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 3))
        .shadow(radius: 6)
    }

    // MARK: - Placement

    /// Start around the suggested cuticle on the outline when there is one,
    /// otherwise spread along the finger (hand pose) so the dots are never
    /// stacked on top of each other.
    private func initialPoints() -> [CGPoint] {
        if let s = suggestion, s.step != 0, let contour = silhouette?.contourPoints, contour.indices.contains(s.inflectionIndex) {
            // Dots 1 and 3 about one fit window from the cuticle -- the
            // stretch the automatic angle uses, about a quarter of the nail
            // -- but never closer than 60 px (shorter baselines made the
            // hand-placed angle jumpy on device).
            let d = max(60, (segmentLengthPixels ?? 60) * 1.2)
            return [walk(contour, from: s.inflectionIndex, step: -s.step, distance: d),
                    contour[s.inflectionIndex],
                    walk(contour, from: s.inflectionIndex, step: s.step, distance: d)]
        }
        if let hand = landmarks {
            let t = hand.indexTip.point, d = hand.indexDIP.point
            let onAxis = [0.28, 0.42, 0.56].map { f in CGPoint(x: t.x + (d.x - t.x) * f, y: t.y + (d.y - t.y) * f) }
            // Known nail side (thumb found): start from just outside the
            // finger on that side and snap onto the nail edge.
            let length = hypot(d.x - t.x, d.y - t.y)
            if silhouette != nil, length > 0 {
                var normal = CGVector(dx: -(d.y - t.y) / length, dy: (d.x - t.x) / length)
                let probe = CGPoint(x: onAxis[1].x + normal.dx * length, y: onAxis[1].y + normal.dy * length)
                if let nailSide = hand.isOnNailSide(probe) {
                    if !nailSide { normal = CGVector(dx: -normal.dx, dy: -normal.dy) }
                    return onAxis.map { p in
                        snapToOutline(CGPoint(x: p.x + normal.dx * length * 0.6, y: p.y + normal.dy * length * 0.6), maxDistance: .infinity)
                    }
                }
            }
            // Snap the middle dot to whichever edge is nearer, then push the
            // other two toward that same edge before snapping them.
            let middle = snapToOutline(onAxis[1], maxDistance: .infinity)
            let side = CGVector(dx: middle.x - onAxis[1].x, dy: middle.y - onAxis[1].y)
            return onAxis.enumerated().map { i, p in
                i == 1 ? middle : snapToOutline(CGPoint(x: p.x + side.dx, y: p.y + side.dy), maxDistance: .infinity)
            }
        }
        let s = image.size
        return [0.4, 0.47, 0.54].map { f in CGPoint(x: s.width / 2, y: s.height * f) }
    }

    private func walk(_ contour: [CGPoint], from index: Int, step: Int, distance: Double) -> CGPoint {
        let n = contour.count, start = contour[index]
        for k in 1..<n {
            let p = contour[((index + step * k) % n + n) % n]
            if Double(hypot(p.x - start.x, p.y - start.y)) >= distance { return p }
        }
        return start
    }

    /// Lovibond points all sit on the finger's edge, so a dragged dot snaps
    /// to the nearest outline point when it's close to one.
    private func snapToOutline(_ p: CGPoint, viewSize: CGSize) -> CGPoint {
        snapToOutline(p, maxDistance: snapRadiusPoints / fitTransform(viewSize).scale)
    }

    private func snapToOutline(_ p: CGPoint, maxDistance: CGFloat) -> CGPoint {
        guard let contour = silhouette?.contourPoints,
              let nearest = contour.min(by: { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }),
              hypot(nearest.x - p.x, nearest.y - p.y) <= maxDistance else { return p }
        return nearest
    }

    // MARK: - Geometry helpers

    private func distanceToAxis(_ p: CGPoint, _ hand: HandLandmarks) -> CGFloat {
        let a = hand.indexTip.point, b = hand.indexDIP.point
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)) / length
    }

    private func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // Aspect-fit mapping, same as InflectionPointConfirmation.
    private func fitTransform(_ viewSize: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        let s = image.size
        let scale = min(viewSize.width / s.width, viewSize.height / s.height)
        return (scale, CGPoint(x: (viewSize.width - s.width * scale) / 2, y: (viewSize.height - s.height * scale) / 2))
    }

    private func toView(_ p: CGPoint, _ viewSize: CGSize) -> CGPoint {
        let t = fitTransform(viewSize)
        return CGPoint(x: p.x * t.scale + t.offset.x, y: p.y * t.scale + t.offset.y)
    }

    private func toImage(_ p: CGPoint, _ viewSize: CGSize) -> CGPoint {
        let t = fitTransform(viewSize)
        return CGPoint(x: (p.x - t.offset.x) / t.scale, y: (p.y - t.offset.y) / t.scale)
    }
}

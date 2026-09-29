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
    let onConfirm: (LovibondCandidate) -> Void
    let onCancel: () -> Void

    // Image-pixel coordinates: [nail, cuticle, skin].
    @State private var points: [CGPoint] = []
    // Only used when neither the outline nor hand pose can say which side
    // is inside the finger.
    @State private var flipped = false

    private let labels = ["1", "2", "3"]
    private let colors: [Color] = [.yellow, .pink, .cyan]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)

                if points.count == 3 {
                    Path { path in path.addLines(points.map { toView($0, geo.size) }) }
                        .stroke(Color.white, lineWidth: 2)
                    ForEach(0..<3, id: \.self) { i in
                        dot(i, viewSize: geo.size)
                    }
                }

                VStack {
                    Text("Drag 1 onto the nail, 2 onto the cuticle corner, 3 onto the skin just behind it")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .padding(.top, 20)
                        .padding(.horizontal, 16)
                    Spacer()
                    controls.padding(.bottom, 40)
                }
            }
            .onAppear { if points.isEmpty { points = initialPoints() } }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var hasInsideInfo: Bool { silhouette != nil || landmarks != nil }

    private var angle: Double? {
        guard points.count == 3 else { return nil }
        return AngleAnalyzer.outsideAngle(nailPoint: points[0], cuticle: points[1], skinPoint: points[2], isInsideFinger: isInsideFinger)
    }

    private func isInsideFinger(_ p: CGPoint) -> Bool? {
        if let contour = silhouette?.contourPoints { return contains(contour, p) }
        if let hand = landmarks {
            // Moving toward the finger's tip-to-DIP axis = moving inward.
            return distanceToAxis(p, hand) < distanceToAxis(points[1], hand)
        }
        return flipped
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if let angle {
                Text("\(angle, specifier: "%.1f")°")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            if !hasInsideInfo {
                Button(flipped ? "Nail fold bulges outward (tap to flip)" : "Nail fold dips inward (tap to flip)") {
                    flipped.toggle()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
            }
            HStack(spacing: 16) {
                Button(action: onCancel) {
                    Text("Retake")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding()
                }
                Button(action: confirm) {
                    Text("Confirm")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color(red: 0, green: 230 / 255, blue: 118 / 255))
                        .cornerRadius(24)
                }
                .disabled(angle == nil)
            }
        }
    }

    private func dot(_ i: Int, viewSize: CGSize) -> some View {
        Text(labels[i])
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.black)
            .frame(width: 28, height: 28)
            .background(Circle().fill(colors[i]))
            .frame(width: 48, height: 48)  // larger touch target
            .contentShape(Circle())
            .position(toView(points[i], viewSize))
            .gesture(DragGesture().onChanged { value in
                points[i] = toImage(value.location, viewSize)
            })
    }

    private func confirm() {
        guard let angle, points.count == 3 else { return }
        onConfirm(LovibondCandidate(side: "manual", angleDegrees: angle, inflectionPoint: points[1], inflectionIndex: 0, step: 0))
    }

    /// Start the dots spread along the finger (from hand pose) so they only
    /// need nudging onto its edge; otherwise stack them mid-image.
    private func initialPoints() -> [CGPoint] {
        if let hand = landmarks {
            let t = hand.indexTip.point, d = hand.indexDIP.point
            return [0.3, 0.6, 0.9].map { f in CGPoint(x: t.x + (d.x - t.x) * f, y: t.y + (d.y - t.y) * f) }
        }
        let s = image.size
        return [0.4, 0.5, 0.6].map { f in CGPoint(x: s.width / 2, y: s.height * f) }
    }

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

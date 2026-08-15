//
//  CaptureGuideOverlay.swift
//  NailVitals
//
//  SwiftUI overlay matching the validated design spec (see
//  guided_capture_demo.html for the working reference version):
//    - Idle/searching: cyan #00E5FF, breathing pulse
//    - Adjusting: amber #FFB300
//    - Aligned: green #00E676, scale-snap + haptic
//    - Dark backdrop: rgba(0,0,0,0.4) behind camera preview
//    - Font: SF Pro Display, Medium/Semibold, sentence case
//
//  UPDATED: the outline now MOLDS to the live detected silhouette
//  instead of always showing a fixed placeholder shape. Falls back to
//  the original hand-designed shape when nothing's detected yet, so
//  the screen isn't empty while searching.
//
//  Two things this needed that are worth understanding, not just
//  copying:
//
//  1. COORDINATE CONVERSION. silhouette.contourPoints are in the
//     camera image's pixel space, but this view draws in the SCREEN's
//     point space -- these don't match 1:1. The camera preview uses
//     .resizeAspectFill (see CameraManager's CameraPreviewView), which
//     scales the image to FILL the view and crops whatever doesn't
//     fit -- so converting coordinates requires the same aspect-fill
//     math, not a naive scale. Get this wrong and the outline will be
//     visibly offset from what the camera is actually showing.
//
//  2. POINT SIMPLIFICATION. A raw contour can have thousands of
//     points -- rebuilding a SwiftUI Path from all of them on every
//     detection update (multiple times per second) would be wasteful
//     and could visibly stutter. Simplified the same way we did once
//     before for the static demo shape (see build_demo.py in the
//     Python prototype, which used cv2.approxPolyDP) -- here
//     implemented as Douglas-Peucker directly in Swift, since there's
//     no OpenCV on this side.
//
//  STATUS: real logic, but UNTESTED until run on device -- the
//  coordinate conversion in particular is the kind of thing that's
//  easy to get subtly wrong and won't show up as a compile error,
//  only as a visibly-misaligned outline. If the live outline doesn't
//  track the real finger correctly, start debugging here.
//

import SwiftUI
import UIKit  // needed for UIImpactFeedbackGenerator -- SwiftUI alone doesn't pull this in

enum CaptureState {
    case searching
    case adjusting
    case aligned
}

struct CaptureGuideOverlay: View {
    let state: CaptureState
    let instructionText: String
    let subText: String
    // NEW: live detected silhouette, when available. nil falls back
    // to the fixed placeholder shape.
    let silhouette: DetectedSilhouette?

    private var strokeColor: Color {
        switch state {
        case .searching: return Color(hex: 0x00E5FF)
        case .adjusting: return Color(hex: 0xFFB300)
        case .aligned: return Color(hex: 0x00E676)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.4)

                outlinePath(viewSize: geometry.size)
                    .stroke(strokeColor, lineWidth: 4)
                    .shadow(color: strokeColor.opacity(0.6), radius: 10)
                    .opacity(state == .searching && silhouette == nil ? pulseOpacity : 1.0)
                    .animation(
                        state == .searching && silhouette == nil
                            ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                            : .default,
                        value: state
                    )

                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text(instructionText)
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundColor(.white)
                        Text(subText)
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .onChange(of: state) { oldValue, newValue in
            if newValue == .aligned {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
    }

    private var pulseOpacity: Double { 0.85 }

    /// Picks the live molded shape when we have real detection data,
    /// otherwise falls back to the fixed placeholder shape centered
    /// in the view.
    private func outlinePath(viewSize: CGSize) -> Path {
        if let silhouette = silhouette, !silhouette.contourPoints.isEmpty {
            return liveMoldedPath(silhouette: silhouette, viewSize: viewSize)
        }
        return fingerOutlinePath(viewSize: viewSize)
    }

    /// Builds a Path from the REAL detected contour, converted from
    /// image pixel space into view space (accounting for aspect-fill
    /// scaling/cropping), and simplified so it's cheap to redraw
    /// repeatedly.
    private func liveMoldedPath(silhouette: DetectedSilhouette, viewSize: CGSize) -> Path {
        // Tolerance increased again -- 18.0 fixed the major seam
        // artifact (see the split-point bug fix above) but left a
        // smaller spike visible right at the fingertip in device
        // screenshots. That spike is real raw-contour jitter (camera
        // noise at the rounded fingertip curve, not a bug), correctly
        // preserved by the algorithm since it exceeds tolerance -- but
        // this is a GUIDE overlay, not a measurement, so it doesn't
        // need that fidelity. Smoothing it out further is the right
        // tradeoff here.
        let simplified = simplifyPolyline(silhouette.contourPoints, tolerance: 30.0)
        let converted = simplified.map {
            convertImagePointToView($0, imageSize: silhouette.imageSize, viewSize: viewSize)
        }

        guard let first = converted.first else { return Path() }
        return Path { path in
            path.move(to: first)
            for point in converted.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
    }

    /// Aspect-fill coordinate conversion: the preview scales the
    /// camera image to FILL the view (cropping whatever overflows),
    /// so this must use the same math the preview layer uses
    /// internally, not a plain linear scale.
    private func convertImagePointToView(_ point: CGPoint, imageSize: CGSize, viewSize: CGSize) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return point }

        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledImageSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offsetX = (scaledImageSize.width - viewSize.width) / 2
        let offsetY = (scaledImageSize.height - viewSize.height) / 2

        return CGPoint(
            x: point.x * scale - offsetX,
            y: point.y * scale - offsetY
        )
    }

    /// Douglas-Peucker polyline simplification -- reduces a large
    /// point set down to the smaller set of points that still
    /// preserves the overall shape within `tolerance` pixels. Swift
    /// port of the same idea as cv2.approxPolyDP, used previously in
    /// the Python prototype to simplify a real finger contour down
    /// from ~8500 points to ~18 for the static demo shape.
    private func simplifyPolyline(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }

        func perpendicularDistance(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> Double {
            let dx = lineEnd.x - lineStart.x
            let dy = lineEnd.y - lineStart.y
            let lengthSquared = dx * dx + dy * dy
            if lengthSquared == 0 {
                return Double(hypot(point.x - lineStart.x, point.y - lineStart.y))
            }
            let t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared
            let projX = lineStart.x + t * dx
            let projY = lineStart.y + t * dy
            return Double(hypot(point.x - projX, point.y - projY))
        }

        func douglasPeucker(_ pts: [CGPoint]) -> [CGPoint] {
            guard pts.count > 2 else { return pts }

            var maxDist = 0.0
            var maxIndex = 0
            for i in 1..<(pts.count - 1) {
                let dist = perpendicularDistance(pts[i], lineStart: pts[0], lineEnd: pts[pts.count - 1])
                if dist > maxDist {
                    maxDist = dist
                    maxIndex = i
                }
            }

            if maxDist > tolerance {
                let left = douglasPeucker(Array(pts[0...maxIndex]))
                let right = douglasPeucker(Array(pts[maxIndex...]))
                return left.dropLast() + right
            } else {
                return [pts[0], pts[pts.count - 1]]
            }
        }

        // BUG FIX: previously split at points.count / 2 -- an
        // arbitrary array-index midpoint that has no relationship to
        // the contour's actual shape. On device this created a
        // visible seam/kink artifact wherever that arbitrary index
        // happened to land, including right at the fingertip in some
        // photos (visibly wrong, not just a minor imperfection).
        // Standard fix for applying Douglas-Peucker to a CLOSED curve:
        // split at the point that's farthest from the chord connecting
        // the first and last points -- this is a real geometric
        // extremum of the shape (typically the fingertip itself or
        // another genuine feature), not an arbitrary array position.
        func chordDistance(_ point: CGPoint, from: CGPoint, to: CGPoint) -> Double {
            perpendicularDistance(point, lineStart: from, lineEnd: to)
        }

        var splitIndex = 0
        var maxChordDist = 0.0
        for i in 1..<(points.count - 1) {
            let dist = chordDistance(points[i], from: points[0], to: points[points.count - 1])
            if dist > maxChordDist {
                maxChordDist = dist
                splitIndex = i
            }
        }
        guard splitIndex > 0 else { return douglasPeucker(points) }

        let firstHalf = douglasPeucker(Array(points[0...splitIndex]))
        let secondHalf = douglasPeucker(Array(points[splitIndex...]))
        return firstHalf + secondHalf.dropFirst()
    }

    /// Original hand-designed placeholder shape, shown when there's
    /// no live detection yet (see build_demo.py in the Python
    /// prototype for why this is hand-designed rather than a raw
    /// photo trace). Centered in the given view size instead of a
    /// fixed frame, so it still looks reasonable at different screen
    /// sizes.
    private func fingerOutlinePath(viewSize: CGSize) -> Path {
        let boxWidth: CGFloat = 150
        let boxHeight: CGFloat = 380
        let offsetX = (viewSize.width - boxWidth) / 2
        let offsetY = (viewSize.height - boxHeight) / 2 - 40  // nudge up, matching original layout intent

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x + offsetX, y: y + offsetY)
        }

        return Path { path in
            path.move(to: pt(75, 8))
            path.addCurve(to: pt(25, 85), control1: pt(42, 8), control2: pt(26, 38))
            path.addLine(to: pt(22, 300))
            path.addCurve(to: pt(40, 362), control1: pt(21, 330), control2: pt(28, 352))
            path.addLine(to: pt(40, 368))
            path.addCurve(to: pt(48, 376), control1: pt(40, 372), control2: pt(44, 376))
            path.addLine(to: pt(102, 376))
            path.addCurve(to: pt(110, 368), control1: pt(106, 376), control2: pt(110, 372))
            path.addLine(to: pt(110, 362))
            path.addCurve(to: pt(128, 300), control1: pt(122, 352), control2: pt(129, 330))
            path.addLine(to: pt(125, 85))
            path.addCurve(to: pt(75, 8), control1: pt(124, 38), control2: pt(108, 8))
            path.closeSubpath()
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

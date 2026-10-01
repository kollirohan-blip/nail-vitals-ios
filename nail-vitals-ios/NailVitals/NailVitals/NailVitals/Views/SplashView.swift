//
//  SplashView.swift
//  NailVitals
//
//  Opening animation: a side-view fingertip draws itself, the Lovibond angle
//  sweeps in at the cuticle, then the title fades in and the splash fades
//  away to reveal the camera (which starts underneath meanwhile).
//

import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void

    @State private var fingerProgress: CGFloat = 0
    @State private var angleProgress: CGFloat = 0
    @State private var showTitle = false
    @State private var fadingOut = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    FingerProfileShape()
                        .trim(from: 0, to: fingerProgress)
                        .stroke(Theme.searching, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .shadow(color: Theme.searching.opacity(0.6), radius: 10)
                    LovibondAngleMark()
                        .trim(from: 0, to: angleProgress)
                        .stroke(Theme.aligned, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .shadow(color: Theme.aligned.opacity(0.7), radius: 6)
                    Text("160°")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.aligned)
                        .opacity(angleProgress)
                        .offset(x: 72, y: -18)
                }
                .frame(width: 180, height: 220)

                VStack(spacing: 6) {
                    Text("Nail Vitals")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                    Text("Finger clubbing screening aid")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 14)
            }
        }
        .opacity(fadingOut ? 0 : 1)
        .task {
            withAnimation(.easeInOut(duration: 0.9)) { fingerProgress = 1 }
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.easeOut(duration: 0.5)) { angleProgress = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15)) { showTitle = true }
            try? await Task.sleep(for: .milliseconds(1300))
            withAnimation(.easeIn(duration: 0.35)) { fadingOut = true }
            try? await Task.sleep(for: .milliseconds(350))
            onFinished()
        }
    }
}

/// A finger pointing up, seen from the side: pad on the left, nail plate on
/// the right running down to the cuticle, then the skin fold stepping out.
struct FingerProfileShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.18, 1.0))
        path.addLine(to: p(0.16, 0.34))
        path.addCurve(to: p(0.36, 0.03), control1: p(0.16, 0.12), control2: p(0.24, 0.03))
        path.addCurve(to: p(0.56, 0.14), control1: p(0.48, 0.03), control2: p(0.55, 0.07))
        path.addLine(to: LovibondAngleMark.cuticle(in: rect))
        path.addLine(to: LovibondAngleMark.skinFold(in: rect))
        path.addQuadCurve(to: p(0.8, 1.0), control: p(0.79, 0.66))
        return path
    }
}

/// The angle at the cuticle, drawn on the outside of the finger: ~160°, the
/// textbook normal value.
private struct LovibondAngleMark: Shape {
    static func cuticle(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + 0.62 * rect.width, y: rect.minY + 0.42 * rect.height)
    }

    /// End of the short skin-fold step below the cuticle; with the nail line
    /// it makes a 160° outside angle.
    static func skinFold(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + 0.715 * rect.width, y: rect.minY + 0.555 * rect.height)
    }

    func path(in rect: CGRect) -> Path {
        let c = Self.cuticle(in: rect)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        let nail = p(0.56, 0.14), skin = Self.skinFold(in: rect)
        let start = atan2(nail.y - c.y, nail.x - c.x)
        let end = atan2(skin.y - c.y, skin.x - c.x)
        let radius: CGFloat = 26
        var path = Path()
        // Sweep through the outside (right-hand) side, from the nail line
        // round to the skin line.
        for i in 0...40 {
            let t = start + (end - start) * CGFloat(i) / 40
            let point = CGPoint(x: c.x + radius * cos(t), y: c.y + radius * sin(t))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

#Preview {
    SplashView(onFinished: {})
}

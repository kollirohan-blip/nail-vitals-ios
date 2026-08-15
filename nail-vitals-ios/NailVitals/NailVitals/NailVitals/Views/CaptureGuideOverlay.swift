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
//  The finger-shaped path below is the same hand-designed outline
//  used in the HTML demo -- ported from SVG path coordinates to a
//  SwiftUI Path. Coordinates are normalized to a 150x380 box, matching
//  the demo's viewBox.
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

    private var strokeColor: Color {
        switch state {
        case .searching: return Color(hex: 0x00E5FF)
        case .adjusting: return Color(hex: 0xFFB300)
        case .aligned: return Color(hex: 0x00E676)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)

            fingerOutlinePath
                .stroke(strokeColor, lineWidth: 4)
                .shadow(color: strokeColor.opacity(0.6), radius: 10)
                .frame(width: 150, height: 380)
                .scaleEffect(state == .aligned ? 1.0 : 1.0)  // TODO: snap animation on transition to .aligned
                .opacity(state == .searching ? pulseOpacity : 1.0)
                .animation(
                    state == .searching
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
        .onChange(of: state) { newValue in
            if newValue == .aligned {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
    }

    // Breathing pulse state -- TODO: wire to a proper repeating
    // animation value once this is actually running in Xcode; this
    // is a placeholder for the opacity target.
    private var pulseOpacity: Double { 0.85 }

    /// Same finger silhouette shape as the HTML demo, ported from the
    /// SVG path coordinates (hand-designed, not a raw photo trace --
    /// see build_demo.py in the Python prototype for why).
    private var fingerOutlinePath: Path {
        Path { path in
            path.move(to: CGPoint(x: 75, y: 8))
            path.addCurve(
                to: CGPoint(x: 25, y: 85),
                control1: CGPoint(x: 42, y: 8),
                control2: CGPoint(x: 26, y: 38)
            )
            path.addLine(to: CGPoint(x: 22, y: 300))
            path.addCurve(
                to: CGPoint(x: 40, y: 362),
                control1: CGPoint(x: 21, y: 330),
                control2: CGPoint(x: 28, y: 352)
            )
            path.addLine(to: CGPoint(x: 40, y: 368))
            path.addCurve(
                to: CGPoint(x: 48, y: 376),
                control1: CGPoint(x: 40, y: 372),
                control2: CGPoint(x: 44, y: 376)
            )
            path.addLine(to: CGPoint(x: 102, y: 376))
            path.addCurve(
                to: CGPoint(x: 110, y: 368),
                control1: CGPoint(x: 106, y: 376),
                control2: CGPoint(x: 110, y: 372)
            )
            path.addLine(to: CGPoint(x: 110, y: 362))
            path.addCurve(
                to: CGPoint(x: 128, y: 300),
                control1: CGPoint(x: 122, y: 352),
                control2: CGPoint(x: 129, y: 330)
            )
            path.addLine(to: CGPoint(x: 125, y: 85))
            path.addCurve(
                to: CGPoint(x: 75, y: 8),
                control1: CGPoint(x: 124, y: 38),
                control2: CGPoint(x: 108, y: 8)
            )
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

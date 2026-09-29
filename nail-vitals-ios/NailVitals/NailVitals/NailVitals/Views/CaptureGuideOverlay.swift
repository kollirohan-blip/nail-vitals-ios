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
//  SIMPLIFIED: now ALWAYS shows the fixed placeholder shape instead of
//  molding to the live detected contour. This is a deliberate UX
//  simplification, not a detection fix -- the live outline was purely
//  a VISUAL rendering of whatever SilhouetteDetector found each frame,
//  and had no effect on the actual guidance logic at all (moveBack/
//  moveCloser/etc, and the skin%/solid% debug readout, all come from
//  GuidanceEngine analyzing the SAME real detection either way). A
//  jagged or oddly-shaped real-time trace could look broken/confusing
//  even when detection underneath was working correctly, so this
//  drops that visual noise and relies on the color state (cyan/amber/
//  green) and text instructions to guide the user instead.
//
//  IMPORTANT: this simplification is ONLY for this live guidance
//  screen. InflectionPointConfirmation (the actual confirm-the-
//  cuticle step) still uses and displays the real, precisely detected
//  contour -- that's the one place accuracy actually matters, since
//  it's what AngleAnalyzer measures the angle from.
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
    // Still accepted (ContentView still passes it, and GuidanceEngine
    // still needs it to compute directions/state) but no longer used
    // to shape the drawn outline -- see the class-level comment above.
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
        }
        .onChange(of: state) { oldValue, newValue in
            if newValue == .aligned {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
    }

    private var pulseOpacity: Double { 0.85 }

    /// SIMPLIFIED: always the fixed placeholder shape now -- see the
    /// class-level comment for why. The `silhouette` parameter is kept
    /// (still needed elsewhere) but intentionally unused here.
    private func outlinePath(viewSize: CGSize) -> Path {
        fingerOutlinePath(viewSize: viewSize)
    }

    /// Hand-designed placeholder shape, centered in the given view
    /// size so it still looks reasonable at different screen sizes.
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

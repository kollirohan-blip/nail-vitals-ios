//
//  CaptureGuideOverlay.swift
//  NailVitals
//
//  Live capture overlay: the hologram "glove" (HologramGuide) where the
//  finger should go, the glowing live outline of the real finger sliding
//  into it, and one short line of instruction. Colored by capture state --
//  cyan searching, amber adjusting, green aligned.
//

import SwiftUI
import UIKit  // UIImpactFeedbackGenerator

enum CaptureState {
    case searching
    case adjusting
    case aligned
}

struct CaptureGuideOverlay: View {
    let state: CaptureState
    let instructionText: String
    let hand: HandLandmarks?
    /// Live glowing finger outline (the real finger), when found.
    var outline: FingerOutline? = nil
    /// How well the finger fills the hologram, 0...1.
    var fit: Double = 0
    /// The most useful next move, for the arrow beside the hologram.
    var direction: GuidanceDirection? = nil
    /// Which hand is being measured, for the hologram's nail side until
    /// hand pose can tell from the thumb.
    var measuredHand: MeasuredHand = .right
    /// Shown under the instruction while searching only.
    var hint: String? = nil

    private var color: Color { Theme.color(for: state) }

    var body: some View {
        ZStack {
            // Same full-screen coordinate space as the aspect-fill preview,
            // so the hologram and outline line up with the finger on screen.
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.25)
                    HologramGuide(state: state, fit: fit, nailOnRight: nailOnRight, direction: direction,
                                  frameSize: hand?.imageSize ?? outline?.imageSize ?? CGSize(width: 1080, height: 1920))
                    if let outline {
                        let mapping = PreviewMapping(imageSize: outline.imageSize, viewSize: geometry.size)
                        LiveFingerOutline(points: outline.points.map(mapping.toView),
                                          cuticle: outline.cuticle.map(mapping.toView),
                                          state: state)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: outline == nil)
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        if let symbol = direction.flatMap(DirectionCue.init)?.symbol ?? (state == .aligned ? "checkmark.circle.fill" : nil) {
                            Image(systemName: symbol)
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(instructionText)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(color == Theme.searching ? .white : color)
                    if let hint, state == .searching {
                        Text(hint)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassPanel(cornerRadius: 20)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .animation(.easeInOut(duration: 0.25), value: state)
        }
        .onChange(of: state) { _, newValue in
            if newValue == .aligned {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    /// Nail side for the hologram: away from the thumb once hand pose sees
    /// it, otherwise the usual side for the chosen hand (right index held
    /// up in front of the back camera, palm to the left: nail on the right).
    private var nailOnRight: Bool {
        if let hand, let side = hand.isOnNailSide(CGPoint(x: hand.indexTip.point.x + 100, y: hand.indexTip.point.y)) {
            return side
        }
        return measuredHand == .right
    }
}

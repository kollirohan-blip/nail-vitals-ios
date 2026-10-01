//
//  CaptureGuideOverlay.swift
//  NailVitals
//
//  Live capture overlay: a faint landing zone where the finger goes, then
//  the hologram glove (FingerGlove) molding onto the real finger once it's
//  close, with one short instruction riding above the fingertip. Colored
//  by how close it is -- amber far off or turned, cyan close, green locked.
//

import SwiftUI

enum CaptureState {
    case searching
    case adjusting
    case aligned
}

struct CaptureGuideOverlay: View {
    let state: CaptureState
    let instructionText: String
    let hand: HandLandmarks?
    /// The real finger's live outline, when found.
    var outline: FingerOutline? = nil
    /// How well the finger fills the target, 0...1.
    var fit: Double = 0
    /// The most useful next move, for the pill's arrow.
    var direction: GuidanceDirection? = nil

    /// The glove appears once the finger is this close to the target.
    static let gloveFit = 0.3

    private var locked: Bool { state == .aligned }

    /// Green locked; cyan close; amber far off or while the hand is turned.
    private var color: Color {
        if locked { return Theme.aligned }
        if direction == .turnToSide || fit < 0.5 { return Theme.adjusting }
        return Theme.searching
    }

    private var frameSize: CGSize {
        hand?.imageSize ?? outline?.imageSize ?? CGSize(width: 1080, height: 1920)
    }

    var body: some View {
        // Same full-screen coordinate space as the aspect-fill preview, so
        // the zone and glove line up with the finger on screen.
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.2)
                LandingZone(fit: fit, searching: state == .searching, frameSize: frameSize)

                if let outline, fit >= Self.gloveFit || locked {
                    let mapping = PreviewMapping(imageSize: outline.imageSize, viewSize: geometry.size)
                    FingerGlove(points: outline.points.map(mapping.toView),
                                tip: (outline.tip ?? hand.map { $0.indexTip.point }).map(mapping.toView),
                                cuticle: outline.cuticle.map(mapping.toView),
                                crease: outline.crease.map(mapping.toView),
                                color: color,
                                locked: locked,
                                instruction: state == .searching ? "" : instructionText,
                                symbol: pillSymbol)
                        .transition(.opacity)
                } else if state != .searching, let tip = fingertip(in: geometry.size) {
                    // Finger seen but not close yet: just the pill by its tip.
                    InstructionPill(text: instructionText, symbol: pillSymbol, color: color)
                        .position(x: tip.x, y: max(tip.y - 52, 40))
                        .transition(.opacity)
                        .id(instructionText)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: outline != nil && fit >= Self.gloveFit)
            .animation(.easeInOut(duration: 0.25), value: instructionText)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var pillSymbol: String? {
        if locked { return "checkmark.circle.fill" }
        return direction.flatMap(DirectionCue.init)?.symbol
    }

    private func fingertip(in viewSize: CGSize) -> CGPoint? {
        let mapping = PreviewMapping(imageSize: frameSize, viewSize: viewSize)
        if let tip = outline?.tip { return mapping.toView(tip) }
        return hand.map { mapping.toView($0.indexTip.point) }
    }
}

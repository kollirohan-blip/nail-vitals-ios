//
//  InflectionPointConfirmation.swift
//  NailVitals
//
//  Lets the user confirm or correct the automatically-suggested
//  cuticle inflection point before trusting an angle measurement --
//  see AngleAnalyzer's doc comment for why this step exists: the
//  automatic search is verified UNRELIABLE specifically in the
//  clinically-normal 160-180 degree range, so a human eye on the
//  actual photo is required, not optional polish.
//
//  Shows BOTH candidate points (left/right of the fingertip along the
//  contour) rather than picking one automatically -- from silhouette
//  shape alone we can't algorithmically tell which side is the real
//  nail/cuticle profile vs. the pad/underside of the finger, but a
//  person looking at the actual photo can. Tap a marker to select
//  that side, drag to fine-tune its exact position (snapped to the
//  nearest real contour point so recomputeAngle() has a valid index
//  to work from), then Confirm to finalize.
//
//  STATUS: first real implementation, not a port of anything --
//  UNTESTED until run on device, same caveat as the rest of the
//  Vision-based pipeline. The coordinate conversion (image pixel
//  space -> view space) is the most likely place for a subtle bug --
//  if markers don't land visually on the actual cuticle edge in the
//  photo, start debugging there first, same as CaptureGuideOverlay's
//  equivalent conversion.
//

import SwiftUI

struct InflectionPointConfirmation: View {
    let image: UIImage
    let result: LovibondResult
    let angleAnalyzer: AngleAnalyzer
    let onConfirm: (LovibondCandidate) -> Void
    let onCancel: () -> Void
    /// Passes the selected (possibly dragged) marker, if any, so manual
    /// placement can start from it.
    var onManual: ((LovibondCandidate?) -> Void)? = nil

    @State private var selectedSide: String?
    // side -> contour index, populated once the user drags that side
    @State private var adjustedIndices: [String: Int] = [:]
    // side -> recomputed angle, populated once the user drags that side
    @State private var liveAngles: [String: Double] = [:]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                imageView(in: geometry.size)

                ForEach(result.candidates, id: \.side) { candidate in
                    marker(for: candidate, viewSize: geometry.size)
                }

                VStack {
                    Spacer()
                    controls
                        .padding(.bottom, 40)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Image

    private func imageView(in viewSize: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: viewSize.width, height: viewSize.height)
    }

    // MARK: - Markers

    private func marker(for candidate: LovibondCandidate, viewSize: CGSize) -> some View {
        let imagePoint = currentImagePoint(for: candidate)
        let viewPoint = convertImagePointToView(imagePoint, viewSize: viewSize)
        let isSelected = selectedSide == candidate.side

        return Circle()
            .fill(isSelected ? Color(hex: 0x00E676) : Color(hex: 0x00E5FF))
            .frame(width: isSelected ? 28 : 20, height: isSelected ? 28 : 20)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: (isSelected ? Color(hex: 0x00E676) : Color(hex: 0x00E5FF)).opacity(0.7), radius: 8)
            .position(viewPoint)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        selectedSide = candidate.side
                        handleDrag(value.location, for: candidate, viewSize: viewSize)
                    }
            )
            .onTapGesture {
                selectedSide = candidate.side
            }
    }

    /// Returns the point to actually draw for this candidate -- the
    /// user-adjusted contour point if they've dragged this side,
    /// otherwise AngleAnalyzer's original suggestion.
    private func currentImagePoint(for candidate: LovibondCandidate) -> CGPoint {
        if let adjustedIndex = adjustedIndices[candidate.side] {
            return result.contourPoints[adjustedIndex]
        }
        return candidate.inflectionPoint
    }

    // MARK: - Dragging

    private func handleDrag(_ location: CGPoint, for candidate: LovibondCandidate, viewSize: CGSize) {
        let imagePoint = convertViewPointToImage(location, viewSize: viewSize)
        guard let nearestIndex = nearestContourIndex(to: imagePoint) else { return }

        adjustedIndices[candidate.side] = nearestIndex

        if let recomputed = angleAnalyzer.recomputeAngle(
            points: result.contourPoints,
            tipIndex: result.tipIndex,
            userConfirmedIndex: nearestIndex,
            step: candidate.step,
            segmentLengthPixels: result.segmentLengthPixels
        ) {
            liveAngles[candidate.side] = recomputed
        }
    }

    /// Nearest-neighbor search over the full contour -- fine for a
    /// one-shot interactive drag (not per-frame like the live
    /// pipeline), so no need for anything fancier than a linear scan.
    /// TODO/VERIFY: if the contour has a lot of points (thousands, per
    /// earlier device testing notes) this runs on every drag-changed
    /// event and could feel laggy -- if dragging feels choppy on
    /// device, throttling this (similar to CameraManager's frame
    /// throttling) is the fix, not rewriting the search itself.
    private func nearestContourIndex(to point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, candidatePoint) in result.contourPoints.enumerated() {
            let distance = hypot(candidatePoint.x - point.x, candidatePoint.y - point.y)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            if let side = selectedSide {
                Text("\(displayAngle(for: side), specifier: "%.1f")°")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("Drag the marker if it's not exactly on the cuticle edge")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text("Tap the marker at the cuticle edge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
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
                        .background(Color(hex: 0x00E676))
                        .cornerRadius(24)
                }
                .disabled(selectedSide == nil)
                .opacity(selectedSide == nil ? 0.4 : 1.0)
            }

            if let onManual {
                Button("Neither is right — place the points myself") { onManual(selectedCandidate()) }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    private func displayAngle(for side: String) -> Double {
        liveAngles[side] ?? result.candidates.first(where: { $0.side == side })?.angleDegrees ?? 0
    }

    private func confirm() {
        guard let confirmedCandidate = selectedCandidate() else { return }
        onConfirm(confirmedCandidate)
    }

    /// The selected marker, including any drag adjustment.
    private func selectedCandidate() -> LovibondCandidate? {
        guard let side = selectedSide,
              let original = result.candidates.first(where: { $0.side == side }) else { return nil }
        return LovibondCandidate(
            side: original.side,
            angleDegrees: liveAngles[side] ?? original.angleDegrees,
            inflectionPoint: currentImagePoint(for: original),
            inflectionIndex: adjustedIndices[side] ?? original.inflectionIndex,
            step: original.step
        )
    }

    // MARK: - Coordinate conversion
    //
    // Aspect-FIT, not aspect-FILL -- this screen shows the WHOLE
    // captured image letterboxed, unlike the live camera preview
    // which fills/crops (see CaptureGuideOverlay). Same underlying
    // idea as that view's convertImagePointToView, different scale
    // formula (min, not max) because of the different content mode.

    private func convertImagePointToView(_ point: CGPoint, viewSize: CGSize) -> CGPoint {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return point }

        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledImageSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offsetX = (viewSize.width - scaledImageSize.width) / 2
        let offsetY = (viewSize.height - scaledImageSize.height) / 2

        return CGPoint(x: point.x * scale + offsetX, y: point.y * scale + offsetY)
    }

    private func convertViewPointToImage(_ point: CGPoint, viewSize: CGSize) -> CGPoint {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return point }

        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledImageSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offsetX = (viewSize.width - scaledImageSize.width) / 2
        let offsetY = (viewSize.height - scaledImageSize.height) / 2

        return CGPoint(x: (point.x - offsetX) / scale, y: (point.y - offsetY) / scale)
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

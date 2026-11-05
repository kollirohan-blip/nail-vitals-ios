//
//  InflectionPointConfirmation.swift
//  NailVitals
//
//  The human-in-the-loop confirmation step for the cuticle inflection
//  point. See the note in AngleAnalyzer.analyze(): automatic
//  corner-detection was found to be unreliable specifically for
//  shallow bends near the clinically-normal 160-180 degree range, so
//  rather than keep tuning a hard CV problem, the app shows the
//  person their photo with the algorithm's SUGGESTED point marked,
//  and lets them tap/drag to correct it before the final angle is
//  computed. Matches the project's "screening aid, human-checked"
//  framing established from the start.
//
//  STATUS: stub -- needs the actual captured photo + AngleAnalyzer
//  wiring once SilhouetteDetector/AngleAnalyzer are verified working
//  on device.
//

import SwiftUI

struct InflectionPointConfirmation: View {
    let capturedImage: UIImage
    let candidate: LovibondCandidate
    let allPoints: [CGPoint]  // full contour, for recomputing on adjustment

    @State private var confirmedPoint: CGPoint
    @State private var currentAngle: Double

    let onConfirm: (CGPoint, Double) -> Void

    init(capturedImage: UIImage, candidate: LovibondCandidate, allPoints: [CGPoint],
         onConfirm: @escaping (CGPoint, Double) -> Void) {
        self.capturedImage = capturedImage
        self.candidate = candidate
        self.allPoints = allPoints
        self.onConfirm = onConfirm
        _confirmedPoint = State(initialValue: candidate.inflectionPoint)
        _currentAngle = State(initialValue: candidate.angleDegrees)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Confirm the cuticle point")
                .font(.system(size: 17, weight: .semibold))

            Text("Drag the marker so it sits right where your nail meets your skin.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            ZStack {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFit()

                // TODO: draggable marker at confirmedPoint, converted
                // from image coordinates to view coordinates based on
                // the displayed image's actual frame/scale. Needs the
                // real image view geometry to do this correctly --
                // placeholder position logic only.
                Circle()
                    .fill(Color(hex: 0x00E676))
                    .frame(width: 20, height: 20)
                    .shadow(color: Color(hex: 0x00E676).opacity(0.6), radius: 6)
                    // .position(confirmedPoint) -- needs coordinate conversion
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // TODO: convert value.location (view
                                // space) back to image-pixel space,
                                // find the nearest actual contour
                                // point (don't let the user pick an
                                // arbitrary point off the silhouette),
                                // then call AngleAnalyzer.recomputeAngle()
                                // with that point's index and update
                                // currentAngle live as they drag.
                            }
                    )
            }

            Text("\(currentAngle, specifier: "%.1f")°")
                .font(.system(size: 32, weight: .bold))

            Button(action: {
                onConfirm(confirmedPoint, currentAngle)
            }) {
                Text("Confirm")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: 0x00E676))
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
        }
        .padding()
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

// ContentView.swift

import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            if camera.permissionGranted {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            } else if camera.permissionDenied {
                Color.black.ignoresSafeArea()
                Text("Camera access denied -- enable it in Settings to use NailVitals")
                    .foregroundColor(.white)
                    .padding()
            } else {
                Color.black.ignoresSafeArea()
            }

            CaptureGuideOverlay(
                state: camera.captureState,
                instructionText: instructionText,
                subText: subText
            )

            VStack {
                Spacer()
                Button(action: {
                    camera.capturePhoto()
                }) {
                    Image(systemName: "circle")
                        .font(.system(size: 72))
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                        // NEW: dimmed when not aligned -- still
                        // visible (so it doesn't look broken/missing)
                        // but clearly not the "ready" state.
                        .opacity(camera.captureState == .aligned ? 1.0 : 0.35)
                }
                // NEW: only actually tappable once GuidanceEngine
                // reports .aligned. BUG THIS FIXES: nothing was
                // stopping a capture from being taken while the
                // screen still said "Move back a little" -- every
                // capture in this whole debugging session could have
                // come from a badly-framed photo, which would produce
                // a genuinely odd contour no amount of AngleAnalyzer
                // tuning could fix, since the problem would be the
                // INPUT, not the search math. This forces capture to
                // only happen on a frame GuidanceEngine has actually
                // validated as well-positioned.
                .disabled(camera.captureState != .aligned)
                .padding(.bottom, 50)

                VStack(spacing: 4) {
                    Text(debugDirectionsText)
                    Text(handReadoutText)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(6)
                // Hidden rather than removed so the capture button keeps its place.
                .opacity(showDebugReadout ? 1 : 0)
                .padding(.bottom, 100)
            }
        }
        .onAppear {
            camera.checkPermissionAndStart()
        }
        .onDisappear {
            camera.stop()
        }
        // NEW: presents once CameraManager.capturedPixelBuffer is
        // non-nil. Using isPresented (bound to a nil-check, which
        // works for any Optional regardless of its wrapped type's
        // conformances) rather than the item: variant, since
        // CVPixelBuffer doesn't conform to Identifiable/Hashable.
        .fullScreenCover(isPresented: Binding(
            get: { camera.capturedPixelBuffer != nil },
            set: { isPresented in
                if !isPresented {
                    camera.resetCapture()
                }
            }
        )) {
            if let buffer = camera.capturedPixelBuffer {
                CaptureFlowView(pixelBuffer: buffer, landmarks: camera.capturedLandmarks, onDismiss: {
                    camera.resetCapture()
                })
            }
        }
    }

    private var instructionText: String {
        guard let first = camera.currentDirections.first else {
            return "Align your finger with the outline"
        }
        switch first {
        case .noFingerDetected:
            return "Point your index finger up"
        case .moveCloser:
            return "Move closer"
        case .moveBack:
            return "Move back a little"
        case .moveLeft:
            return "Move left"
        case .moveRight:
            return "Move right"
        case .straighten:
            return "Straighten your finger and point it up"
        case .moveHandDown:
            return "Move your hand down slightly"
        case .looksGood:
            return "Perfect, hold still"
        }
    }

    private var subText: String {
        switch camera.captureState {
        case .searching: return "Turn your hand so the camera sees the side of your finger"
        case .adjusting: return "Turn until the nail looks like a thin edge, not a flat surface"
        case .aligned: return "Hold still and tap the button"
        }
    }

    private var debugDirectionsText: String {
        camera.currentDirections.map { "\($0)" }.joined(separator: ", ")
    }

    private var handReadoutText: String {
        guard let hand = camera.handLandmarks else { return "hand: none" }
        return String(format: "hand conf %.2f  length %.0f%%  tilt %.0f°",
                      hand.minIndexConfidence, hand.fingerLengthFraction * 100, hand.tiltFromVerticalDegrees)
    }
}

#Preview {
    ContentView()
}


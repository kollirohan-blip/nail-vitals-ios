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
                subText: subText,
                silhouette: camera.currentSilhouette
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
                    Text(pipelineStageText)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(6)
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
                CaptureFlowView(pixelBuffer: buffer, onDismiss: {
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
            return "Align your finger with the outline"
        case .moveCloser:
            return "Move closer"
        case .moveBack:
            return "Move back a little"
        case .moveLeft:
            return "Move left"
        case .moveRight:
            return "Move right"
        case .straighten:
            return "Straighten your finger"
        case .moveHandDown:
            return "Move your hand down slightly"
        case .looksGood:
            return "Perfect, hold still"
        }
    }

    private var subText: String {
        switch camera.captureState {
        case .searching: return "Hold your finger sideways, nail facing the camera"
        case .adjusting: return "Rotate slightly so the nail edge is visible"
        case .aligned: return "Capturing..."
        }
    }

    private var debugDirectionsText: String {
        let directions = camera.currentDirections.map { "\($0)" }.joined(separator: ", ")
        let skinPct = Int(camera.skinPassingFraction * 100)
        let solidityPct = Int(camera.solidity * 100)
        return "\(directions)  |  skin: \(skinPct)%  |  solid: \(solidityPct)%"
    }

    // Names the exact gate the latest frame was rejected at, so a
    // "detection isn't working" report comes with a specific number.
    private var pipelineStageText: String {
        guard camera.currentSilhouette != nil else {
            switch camera.silhouetteStage {
            case .noContourFound:
                return "stage: Vision found no contour"
            case .notCentered(let count):
                return "stage: \(count) contour(s), none centered"
            case .onlyFrameSized(let count):
                return "stage: rejected \(count) full-width contour(s) (background)"
            case .lowSolidity(let value):
                return "stage: rejected, low solidity \(Int(value * 100))%"
            case .failedSkinTone(let value):
                return "stage: rejected, skin check \(Int(value * 100))%"
            case .passed:
                return "stage: passed silhouette"
            }
        }
        if camera.currentDirections == [.noFingerDetected] {
            return "stage: rejected, aspect ratio \(String(format: "%.2f", camera.lastAspectRatio)) (need ≥1.40)"
        }
        return "stage: silhouette + shape OK (aspect \(String(format: "%.2f", camera.lastAspectRatio)))"
    }
}

#Preview {
    ContentView()
}


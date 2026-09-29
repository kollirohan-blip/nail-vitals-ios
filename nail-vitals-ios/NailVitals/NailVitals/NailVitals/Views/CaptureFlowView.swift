//
//  CaptureFlowView.swift
//  NailVitals
//
//  Coordinates what happens AFTER a photo is captured: run detection
//  + angle analysis on the captured frame, let the user confirm/adjust
//  the suggested inflection point (see AngleAnalyzer's doc comment on
//  why this step is required, not optional), then show the final
//  result. Presented as a full-screen cover from ContentView once
//  CameraManager.capturedPixelBuffer is set.
//
//  STATUS: first real wiring of the whole "photo -> angle -> result"
//  path -- UNTESTED until run on device, same caveat as the rest of
//  this project's Vision/AVFoundation code.
//

import SwiftUI

struct CaptureFlowView: View {
    let pixelBuffer: CVPixelBuffer
    /// Called when the user is done with this flow (confirmed a
    /// result, or backed out) -- lets ContentView dismiss and reset
    /// CameraManager.capturedPixelBuffer to nil so a new capture can
    /// be taken.
    let onDismiss: () -> Void

    @State private var stage: Stage = .analyzing
    @State private var displayImage: UIImage?
    @State private var lovibondResult: LovibondResult?

    // Fresh instances -- both are cheap, stateless-between-calls
    // classes (see their own file comments), so no need to share
    // CameraManager's live-pipeline instances.
    private let silhouetteDetector = SilhouetteDetector()
    private let angleAnalyzer = AngleAnalyzer()

    enum Stage {
        case analyzing
        case confirming
        case result(LovibondCandidate)
        case failed(String)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch stage {
            case .analyzing:
                ProgressView("Analyzing...")
                    .tint(.white)
                    .foregroundColor(.white)

            case .confirming:
                if let image = displayImage, let result = lovibondResult {
                    InflectionPointConfirmation(
                        image: image,
                        result: result,
                        angleAnalyzer: angleAnalyzer,
                        onConfirm: { confirmed in
                            stage = .result(confirmed)
                        },
                        onCancel: onDismiss
                    )
                }

            case .result(let candidate):
                VStack {
                    Spacer()
                    ResultView(candidate: candidate)
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding()
                    }
                    .padding(.bottom, 24)
                }

            case .failed(let message):
                VStack(spacing: 20) {
                    Text(message)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(action: onDismiss) {
                        Text("Try Again")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(24)
                    }
                }
            }
        }
        .onAppear {
            runAnalysis()
        }
    }

    private func runAnalysis() {
        // Off the main thread -- real Vision + geometry work, even
        // though it's a one-shot (not per-frame) operation, shouldn't
        // block the UI while it runs.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let silhouette = silhouetteDetector.detect(in: pixelBuffer, highQuality: true) else {
                DispatchQueue.main.async {
                    stage = .failed("Couldn't find a clear finger outline in that photo. Try again with better lighting or positioning.")
                }
                return
            }

            guard let result = angleAnalyzer.analyze(silhouette) else {
                DispatchQueue.main.async {
                    stage = .failed("Couldn't measure an angle from that photo. Try again, keeping the nail edge clearly visible.")
                }
                return
            }

            let image = makeDisplayImage(from: pixelBuffer)

            DispatchQueue.main.async {
                self.displayImage = image
                self.lovibondResult = result
                self.stage = .confirming
            }
        }
    }

    /// Converts the captured CVPixelBuffer into a UIImage for display
    /// during confirmation. The buffer should already be right-side-up
    /// in portrait orientation -- see CameraManager's
    /// videoRotationAngle setup, which fixed this exact orientation
    /// issue for the live overlay earlier, and applies equally here
    /// since it's the same captured buffer.
    private func makeDisplayImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

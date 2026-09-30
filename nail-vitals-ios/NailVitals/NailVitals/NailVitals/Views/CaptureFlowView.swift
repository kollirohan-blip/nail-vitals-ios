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
    /// Hand-pose joints from the same photo; the DIP joint picks the finger
    /// in the subject mask and anchors the cuticle search.
    let landmarks: HandLandmarks?
    /// Called when the user is done with this flow (confirmed a
    /// result, or backed out) -- lets ContentView dismiss and reset
    /// CameraManager.capturedPixelBuffer to nil so a new capture can
    /// be taken.
    let onDismiss: () -> Void

    @State private var stage: Stage = .analyzing
    @State private var displayImage: UIImage?
    @State private var lovibondResult: LovibondResult?
    @State private var silhouette: DetectedSilhouette?
    @State private var captureFolder: URL?

    private let segmenter = FingerMaskSegmenter()
    private let angleAnalyzer = AngleAnalyzer()

    enum Stage {
        case analyzing
        case confirming
        case manual(LovibondCandidate?)
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
                        result: nailSideOnly(result),
                        angleAnalyzer: angleAnalyzer,
                        onConfirm: { confirmed in
                            finish(with: confirmed, manualDots: nil)
                        },
                        onCancel: onDismiss,
                        onManual: { stage = .manual($0) }
                    )
                }

            case .manual(let suggestion):
                if let image = displayImage {
                    ManualAngleView(
                        image: image,
                        silhouette: silhouette,
                        landmarks: landmarks,
                        suggestion: suggestion,
                        segmentLengthPixels: lovibondResult?.segmentLengthPixels,
                        onConfirm: { finish(with: $0, manualDots: $1) },
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
                    if displayImage != nil {
                        Button("Measure manually") { stage = .manual(nil) }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .onAppear {
            runAnalysis()
        }
    }

    /// The pad-side marker isn't a Lovibond angle at all (on device it read
    /// 194-199, a false clubbing flag if tapped), so show only the nail-side
    /// one when hand pose can tell which side that is. The full result is
    /// still what gets saved.
    private func nailSideOnly(_ result: LovibondResult) -> LovibondResult {
        guard let hand = landmarks else { return result }
        let nailSide = result.candidates.filter { hand.isOnNailSide($0.inflectionPoint) == true }
        guard !nailSide.isEmpty else { return result }
        return LovibondResult(fingertip: result.fingertip, tipIndex: result.tipIndex, contourPoints: result.contourPoints,
                              segmentLengthPixels: result.segmentLengthPixels, candidates: nailSide)
    }

    private func finish(with confirmed: LovibondCandidate, manualDots: [CGPoint]?) {
        CaptureRecorder.saveConfirmation(in: captureFolder, confirmed: confirmed, manualDots: manualDots)
        stage = .result(confirmed)
    }

    private func runAnalysis() {
        // Off the main thread -- real Vision + geometry work, even
        // though it's a one-shot (not per-frame) operation, shouldn't
        // block the UI while it runs.
        let dip = landmarks?.indexDIP.point
        let hand = landmarks
        DispatchQueue.global(qos: .userInitiated).async {
            // Made first so manual measurement stays available even when
            // automatic detection fails.
            let image = makeDisplayImage(from: pixelBuffer)
            func save(_ result: LovibondResult?, failure: String?) -> URL? {
                image.flatMap { CaptureRecorder.saveAnalysis(image: $0, landmarks: hand, result: result, failure: failure) }
            }

            guard let silhouette = segmenter.segment(pixelBuffer: pixelBuffer, fingertipHint: dip) else {
                let folder = save(nil, failure: "no outline")
                DispatchQueue.main.async {
                    displayImage = image
                    captureFolder = folder
                    stage = .failed("Couldn't find a clear finger outline in that photo. Try again with better lighting or positioning, or measure it yourself.")
                }
                return
            }

            guard let result = angleAnalyzer.analyze(silhouette, dipHint: dip) else {
                let folder = save(nil, failure: "no angle")
                DispatchQueue.main.async {
                    displayImage = image
                    captureFolder = folder
                    self.silhouette = silhouette
                    stage = .failed("Couldn't measure an angle from that photo. Try again, keeping the nail edge clearly visible, or measure it yourself.")
                }
                return
            }

            let folder = save(result, failure: nil)
            DispatchQueue.main.async {
                self.displayImage = image
                self.captureFolder = folder
                self.silhouette = silhouette
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

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
    /// Which index finger this is; saved with the capture.
    var hand: MeasuredHand = .right
    /// Called when the user is done with this flow (confirmed a
    /// result, or backed out) -- lets ContentView dismiss and reset
    /// CameraManager.capturedPixelBuffer to nil so a new capture can
    /// be taken.
    let onDismiss: () -> Void
    /// Readings already confirmed this session (before this capture).
    var previousReadings: [FingerSigns] = []
    /// Reports a confirmed, plausible reading so the session can keep it.
    var onReading: (FingerSigns) -> Void = { _ in }
    /// Ends the session (clears its readings) and closes this flow.
    var onFinishSession: () -> Void = {}

    @State private var stage: Stage = .analyzing
    @State private var sessionReadings: [FingerSigns] = []
    /// What the result screen shows: the session including this reading, or
    /// only this reading when it wasn't usable.
    @State private var resultReadings: [FingerSigns] = []
    @State private var showAssistant = false
    @State private var displayImage: UIImage?
    @State private var lovibondResult: LovibondResult?
    @State private var silhouette: DetectedSilhouette?
    @State private var captureFolder: URL?
    @State private var manualNote: String?
    /// The joints actually used: hand pose's, or ones found from the
    /// outline when hand pose missed the raised finger.
    @State private var resolvedLandmarks: HandLandmarks?

    private var joints: HandLandmarks? { resolvedLandmarks ?? landmarks }

    private let segmenter = FingerMaskSegmenter()
    private let angleAnalyzer = AngleAnalyzer()

    enum Stage {
        case analyzing
        case confirming
        case manual(LovibondCandidate?)
        case result
        case failed(String)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch stage {
            case .analyzing:
                MeasuringView(image: displayImage)

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
                        landmarks: joints,
                        suggestion: suggestion,
                        segmentLengthPixels: lovibondResult?.segmentLengthPixels,
                        note: manualNote,
                        onConfirm: { finish(with: $0, manualDots: $1) },
                        onCancel: onDismiss
                    )
                }

            case .result:
                VStack {
                    ScrollView {
                        VStack {
                            ResultView(readings: resultReadings)
                                .padding(.top, 24)
                            askButton
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    HStack(spacing: 12) {
                        Button("Finish", action: onFinishSession)
                            .buttonStyle(GhostButtonStyle())
                        Button("Measure again", action: onDismiss)
                            .buttonStyle(GlowButtonStyle(color: Theme.searching))
                    }
                    .padding(.vertical, 16)
                }
                .sheet(isPresented: $showAssistant) {
                    AskAssistantView(context: AssistantContext(readings: resultReadings, hand: hand))
                }

            case .failed(let message):
                VStack(spacing: 20) {
                    Image(systemName: "hand.raised.fingers.spread")
                        .font(.system(size: 34))
                        .foregroundColor(Theme.adjusting)
                    Text(message)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Try again", action: onDismiss)
                        .buttonStyle(GlowButtonStyle(color: Theme.searching))
                    if displayImage != nil {
                        Button("Measure manually") { stage = .manual(nil) }
                            .buttonStyle(GhostButtonStyle())
                    }
                }
                .padding(24)
                .glassPanel(cornerRadius: 24)
                .padding(.horizontal, 24)
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
        guard let hand = joints else { return result }
        let nailSide = result.candidates.filter { hand.isOnNailSide($0.inflectionPoint) == true }
        guard !nailSide.isEmpty else { return result }
        return LovibondResult(fingertip: result.fingertip, tipIndex: result.tipIndex, contourPoints: result.contourPoints,
                              segmentLengthPixels: result.segmentLengthPixels, candidates: nailSide)
    }

    private var askButton: some View {
        Button {
            showAssistant = true
        } label: {
            Label("Ask about this result", systemImage: "bubble.left.and.text.bubble.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.searching)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassPanel(cornerRadius: 22)
        }
        .padding(.top, 14)
    }

    private func finish(with confirmed: LovibondCandidate, manualDots: [CGPoint]?) {
        let signs = measureSigns(at: confirmed)
        CaptureRecorder.saveConfirmation(in: captureFolder, confirmed: confirmed, manualDots: manualDots, signs: signs)
        sessionReadings = previousReadings
        if SignKind.lovibond.value(in: signs) != nil {
            sessionReadings.append(signs)
            onReading(signs)
            resultReadings = sessionReadings
        } else {
            resultReadings = [signs]
        }
        stage = .result
    }

    /// All three signs at the confirmed cuticle. The hyponychial angle and
    /// depth ratio need the finger outline and the tip and DIP joints.
    private func measureSigns(at confirmed: LovibondCandidate) -> FingerSigns {
        let lovibond = AngleAnalyzer.plausibleRange.contains(confirmed.angleDegrees) ? confirmed.angleDegrees : nil
        guard let silhouette, let hand = joints else {
            return FingerSigns(lovibond: lovibond, cuticle: confirmed.inflectionPoint)
        }
        return FingerSignsAnalyzer.measure(contour: silhouette.contourPoints, tip: hand.indexTip.point,
                                           dip: hand.indexDIP.point, cuticle: confirmed.inflectionPoint,
                                           lovibond: lovibond, isNailSide: { hand.isOnNailSide($0) })
    }

    private func runAnalysis() {
        // Off the main thread -- real Vision + geometry work, even
        // though it's a one-shot (not per-frame) operation, shouldn't
        // block the UI while it runs.
        let visionHand = landmarks
        let measuredHand = self.hand
        DispatchQueue.global(qos: .userInitiated).async {
            // Made first so manual measurement stays available even when
            // automatic detection fails.
            let image = makeDisplayImage(from: pixelBuffer)
            // Show the photo under the scanning animation while measuring.
            DispatchQueue.main.async { displayImage = image }
            var hand = visionHand
            func save(_ result: LovibondResult?, failure: String?) -> URL? {
                image.flatMap { CaptureRecorder.saveAnalysis(image: $0, landmarks: hand, measuredHand: measuredHand, result: result, failure: failure) }
            }

            guard let silhouette = segmenter.segment(pixelBuffer: pixelBuffer, fingertipHint: visionHand?.indexDIP.point) else {
                let folder = save(nil, failure: "no outline")
                DispatchQueue.main.async {
                    displayImage = image
                    captureFolder = folder
                    stage = .failed("Couldn't find a clear finger outline in that photo. Try again with better lighting or positioning, or measure it yourself.")
                }
                return
            }

            // Hand pose can miss the raised finger (rings, an OK-sign hand);
            // then the finger is found from the outline instead.
            hand = OutlineFingerFinder.resolve(visionHand, contour: silhouette.contourPoints, imageSize: silhouette.imageSize)
            let resolved = hand
            DispatchQueue.main.async { self.resolvedLandmarks = resolved }

            guard let result = angleAnalyzer.analyze(silhouette, dipHint: hand?.indexDIP.point, tipHint: hand?.indexTip.point) else {
                let folder = save(nil, failure: "no angle")
                DispatchQueue.main.async {
                    displayImage = image
                    captureFolder = folder
                    self.silhouette = silhouette
                    stage = .failed("Couldn't trace the edge of your finger. Hold it in front of a plain wall (not over a laptop or desk) with the nail edge visible, or measure it yourself.")
                }
                return
            }

            let folder = save(result, failure: nil)
            DispatchQueue.main.async {
                self.displayImage = image
                self.captureFolder = folder
                self.silhouette = silhouette
                self.lovibondResult = result
                if foundNoCuticleDip(result) {
                    self.manualNote = "No cuticle dip found. That happens when the finger is turned toward the camera, and with clubbing. If you can see the flat of the nail in this photo, tap Retake and turn the nail to face sideways. Otherwise, place the points yourself."
                    self.stage = .manual(nil)
                } else {
                    self.stage = .confirming
                }
            }
        }
    }

    /// A normal cuticle shows up as an inward dip on the nail side (reads
    /// below 180). With no dip, the automatic marker falls back to the bend
    /// of the fingertip itself: on web photos of clubbed fingers seen from
    /// the side it read above 180 with the marker near the tip, not at the
    /// cuticle. That number isn't a real measurement, so ask for the dots.
    private func foundNoCuticleDip(_ result: LovibondResult) -> Bool {
        let shown = nailSideOnly(result).candidates
        return !shown.isEmpty && shown.allSatisfy { $0.angleDegrees >= 180 }
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

/// The captured photo with a scan line sweeping over it while the
/// measurement runs.
private struct MeasuringView: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        GeometryReader { geo in
                            TimelineView(.animation) { timeline in
                                let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                                let y = geo.size.height * CGFloat(t)
                                ZStack(alignment: .top) {
                                    LinearGradient(colors: [Theme.searching.opacity(0), Theme.searching.opacity(0.25)],
                                                   startPoint: .top, endPoint: .bottom)
                                        .frame(height: 90)
                                        .offset(y: y - 90)
                                    Rectangle()
                                        .fill(Theme.searching)
                                        .frame(height: 2)
                                        .shadow(color: Theme.searching, radius: 8)
                                        .offset(y: y)
                                }
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                            }
                        }
                        .clipped()
                    }
                    .transition(.opacity)
            }
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Measuring…")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassPanel(cornerRadius: 22)
                .padding(.bottom, 60)
            }
        }
        .animation(.easeIn(duration: 0.25), value: image == nil)
    }
}

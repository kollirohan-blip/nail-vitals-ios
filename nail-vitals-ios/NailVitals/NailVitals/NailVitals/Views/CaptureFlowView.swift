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
    /// Study participant code and skin-tone group, saved with the capture.
    var participant: String?
    var skinTone: String?
    /// Called when the user is done with this flow (confirmed a
    /// result, or backed out) -- lets ContentView dismiss and reset
    /// CameraManager.capturedPixelBuffer to nil so a new capture can
    /// be taken.
    let onDismiss: () -> Void
    /// Readings already confirmed this session (before this capture).
    var previousReadings: [FingerSigns] = []
    /// Readings in a full session; the combined result shows after the last.
    var targetReadings = 3
    /// Reports a confirmed, plausible reading so the session can keep it.
    var onReading: (FingerSigns) -> Void = { _ in }
    /// Ends the session (saves its readings) and closes this flow.
    var onFinishSession: () -> Void = {}
    /// Throws the session's readings away and goes back to the camera.
    var onStartOver: () -> Void = {}

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
    /// No cuticle dip: the confirmation shows one marker at the estimated
    /// cuticle instead of the analyzer's candidates.
    @State private var noDipResult: LovibondResult?
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
        /// A reading was saved and more are needed: a short "saved" screen,
        /// then back to the camera.
        case saved(Int)
        /// The confirmed reading wasn't usable; it doesn't count.
        case unusable
        case failed(String)
    }

    var body: some View {
        ZStack {
            AppBackground()

            switch stage {
            case .analyzing:
                MeasuringView(image: displayImage)

            case .confirming:
                if let image = displayImage, let result = lovibondResult {
                    InflectionPointConfirmation(
                        image: image,
                        result: noDipResult ?? nailSideOnly(result),
                        angleAnalyzer: angleAnalyzer,
                        onConfirm: { confirmed in
                            finish(with: confirmed, manualDots: nil)
                        },
                        onCancel: onDismiss,
                        onManual: { stage = .manual($0) },
                        noDipNote: noDipResult == nil ? nil : "The nail runs straight out of the skin with no dip. Clubbing does this, and so does a finger turned toward the camera. If you can see the flat of your nail, tap Retake and turn your finger sideways. Otherwise, check the dot and tap Looks right."
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
                        Button("Scan again", action: onStartOver)
                            .buttonStyle(GhostButtonStyle())
                        Button("Done", action: onFinishSession)
                            .buttonStyle(GlowButtonStyle(color: Theme.action))
                    }
                    .padding(.vertical, 16)
                }
                .sheet(isPresented: $showAssistant) {
                    AskAssistantView(context: AssistantContext(readings: resultReadings, hand: hand))
                }

            case .saved(let count):
                ReadingSavedView(count: count, target: targetReadings,
                                 onContinue: onDismiss,
                                 onShowResult: { withAnimation(.easeInOut(duration: 0.3)) { stage = .result } })

            case .unusable:
                ReadingSavedView(count: nil, target: targetReadings,
                                 onContinue: onDismiss, onShowResult: nil)

            case .failed(let message):
                VStack(spacing: 20) {
                    Image(systemName: "hand.raised.fingers.spread")
                        .font(.system(size: 34))
                        .foregroundColor(Theme.adjusting)
                    Text(message)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    Button("Try again", action: onDismiss)
                        .buttonStyle(GlowButtonStyle(color: Theme.action))
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
                .foregroundColor(Theme.action)
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
        guard SignKind.lovibond.value(in: signs) != nil else {
            // Not a usable reading: say so and go back for another.
            withAnimation(.easeInOut(duration: 0.3)) { stage = .unusable }
            return
        }
        sessionReadings.append(signs)
        onReading(signs)
        resultReadings = sessionReadings
        withAnimation(.easeInOut(duration: 0.3)) {
            stage = sessionReadings.count >= targetReadings ? .result : .saved(sessionReadings.count)
        }
    }

    /// All three signs at the confirmed cuticle. The hyponychial angle and
    /// depth ratio need the finger outline and the tip and DIP joints.
    private func measureSigns(at confirmed: LovibondCandidate) -> FingerSigns {
        let lovibond = AngleAnalyzer.plausibleRange.contains(confirmed.angleDegrees) ? confirmed.angleDegrees : nil
        var signs: FingerSigns
        if let silhouette, let hand = joints {
            signs = FingerSignsAnalyzer.measure(contour: silhouette.contourPoints, tip: hand.indexTip.point,
                                                dip: hand.indexDIP.point, cuticle: confirmed.inflectionPoint,
                                                lovibond: lovibond, isNailSide: { hand.isOnNailSide($0) })
        } else {
            signs = FingerSigns(lovibond: lovibond, cuticle: confirmed.inflectionPoint)
        }
        // The estimated marker, confirmed as is (or dragged to a spot that
        // still shows no dip): Lovibond's angle is obliterated, 180 or more.
        if confirmed.side == Self.estimatedSide, confirmed.angleDegrees >= 180 {
            signs.noCuticleDip = true
            signs.lovibond = confirmed.angleDegrees
        }
        return signs
    }

    static let estimatedSide = "estimated"

    /// A marker at the typical cuticle position on the nail-side edge, for
    /// captures with no cuticle dip. Its angle is 180 (obliterated) until
    /// the user drags it, when the confirmation recomputes the local angle.
    private func estimatedCandidate(_ result: LovibondResult, silhouette: DetectedSilhouette) -> LovibondCandidate? {
        guard let hand = joints,
              let point = FingerSignsAnalyzer.estimatedCuticle(contour: silhouette.contourPoints, apex: result.fingertip,
                                                               tip: hand.indexTip.point, dip: hand.indexDIP.point,
                                                               isNailSide: { hand.isOnNailSide($0) }),
              let index = result.contourPoints.indices.min(by: {
                  hypot(result.contourPoints[$0].x - point.x, result.contourPoints[$0].y - point.y)
                      < hypot(result.contourPoints[$1].x - point.x, result.contourPoints[$1].y - point.y)
              })
        else { return nil }
        let step = nailSideOnly(result).candidates.first?.step ?? 1
        return LovibondCandidate(side: Self.estimatedSide, angleDegrees: 180, inflectionPoint: result.contourPoints[index],
                                 inflectionIndex: index, step: step)
    }

    private func runAnalysis() {
        // Off the main thread -- real Vision + geometry work, even
        // though it's a one-shot (not per-frame) operation, shouldn't
        // block the UI while it runs.
        let visionHand = landmarks
        let measuredHand = self.hand
        let participant = self.participant, skinTone = self.skinTone
        DispatchQueue.global(qos: .userInitiated).async {
            // Made first so manual measurement stays available even when
            // automatic detection fails.
            let image = makeDisplayImage(from: pixelBuffer)
            // Show the photo under the scanning animation while measuring.
            DispatchQueue.main.async { displayImage = image }
            var hand = visionHand
            var outlineSource: String?
            var sharpness: Double?
            func save(_ result: LovibondResult?, failure: String?) -> URL? {
                image.flatMap { CaptureRecorder.saveAnalysis(image: $0, landmarks: hand, measuredHand: measuredHand,
                                                             participant: participant, skinTone: skinTone, outline: outlineSource,
                                                             sharpness: sharpness, result: result, failure: failure) }
            }

            // A turned hand hides the cuticle dip and changes every angle;
            // the live guide blocks it, and this catches it in the photo.
            if visionHand?.isClearlyTurned == true {
                let folder = save(nil, failure: "hand turned")
                DispatchQueue.main.async {
                    displayImage = image
                    captureFolder = folder
                    stage = .failed("Your hand looks turned, with the back of the hand toward the camera. Turn it so the nail faces sideways and try again.")
                }
                return
            }

            // The outline from a crop around the finger first: its edge is
            // about twice as close to the real one, so repeat photos agree
            // better. Used only when it measures, on hand pose's own finger
            // (if the outline points to a different raised finger, the crop
            // may have missed it); otherwise the whole photo, as before.
            var outline: DetectedSilhouette?
            var lovibond: LovibondResult?
            if let visionHand, let cropped = segmenter.segmentAroundFinger(pixelBuffer: pixelBuffer, hand: visionHand) {
                let croppedHand = OutlineFingerFinder.resolve(visionHand, contour: cropped.contourPoints, imageSize: cropped.imageSize)
                if croppedHand?.fromOutline == false,
                   let measured = angleAnalyzer.analyze(cropped, dipHint: croppedHand?.indexDIP.point, tipHint: croppedHand?.indexTip.point) {
                    outline = cropped
                    outlineSource = "crop"
                    hand = croppedHand
                    lovibond = measured
                }
            }
            if outline == nil {
                guard let whole = segmenter.segment(pixelBuffer: pixelBuffer, fingertipHint: visionHand?.indexDIP.point) else {
                    let folder = save(nil, failure: "no outline")
                    DispatchQueue.main.async {
                        displayImage = image
                        captureFolder = folder
                        stage = .failed("Couldn't see your finger clearly. Try again in good light, in front of a plain wall.")
                    }
                    return
                }
                // Hand pose can miss the raised finger (rings, an OK-sign
                // hand); then the finger is found from the outline instead.
                outline = whole
                outlineSource = "whole"
                hand = OutlineFingerFinder.resolve(visionHand, contour: whole.contourPoints, imageSize: whole.imageSize)
                lovibond = angleAnalyzer.analyze(whole, dipHint: hand?.indexDIP.point, tipHint: hand?.indexTip.point)
            }
            let resolved = hand
            DispatchQueue.main.async { self.resolvedLandmarks = resolved }

            guard let silhouette = outline, let result = lovibond else {
                let folder = save(nil, failure: "no angle")
                let shown = outline
                DispatchQueue.main.async {
                    displayImage = image
                    captureFolder = folder
                    self.silhouette = shown
                    stage = .failed("Couldn't find the edge of your finger. Hold it up in front of a plain wall, side-on, so the edge of your nail shows.")
                }
                return
            }

            // A blurry photo reads the nail angle high (blur rounds off the
            // dip at the cuticle), so it's retaken rather than measured.
            if let hand {
                sharpness = EdgeSharpness.measure(contour: silhouette.contourPoints, tip: hand.indexTip.point,
                                                  dip: hand.indexDIP.point, in: pixelBuffer)
            }
            if let sharpness, sharpness < EdgeSharpness.minimum {
                let folder = save(result, failure: "blurry")
                DispatchQueue.main.async {
                    displayImage = image
                    captureFolder = folder
                    stage = .failed("That photo came out blurry. Hold the phone a little farther from your finger and keep still, then try again.")
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
                    if let estimated = estimatedCandidate(result, silhouette: silhouette) {
                        self.noDipResult = LovibondResult(fingertip: result.fingertip, tipIndex: result.tipIndex,
                                                          contourPoints: result.contourPoints,
                                                          segmentLengthPixels: result.segmentLengthPixels,
                                                          candidates: [estimated])
                        self.stage = .confirming
                    } else {
                        self.manualNote = "No dip where the nail meets the skin, and the app couldn't tell which side the nail is on. If you can see the flat of your nail, tap Retake and turn your finger sideways. Otherwise, place the points yourself."
                        self.stage = .manual(nil)
                    }
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
    @State private var flash = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    ProgressView().tint(.primary)
                    Text("Measuring…")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassPanel(cornerRadius: 22)
                .padding(.bottom, 60)
            }
            // Camera flash as the photo lands.
            Color.white
                .opacity(reduceMotion ? 0 : flash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .animation(.easeIn(duration: 0.25), value: image == nil)
        .onAppear { withAnimation(.easeOut(duration: 0.45)) { flash = 0 } }
    }
}

/// Between readings: a check mark, "Reading 1 of 3 saved", and back to the
/// camera on its own after a moment (or right away with a tap). For an
/// unusable reading (count nil): "That one didn't work" instead.
private struct ReadingSavedView: View {
    let count: Int?
    let target: Int
    let onContinue: () -> Void
    let onShowResult: (() -> Void)?

    @State private var appeared = false
    @State private var ring: CGFloat = 0

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(count == nil ? Theme.adjusting : Theme.aligned, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: (count == nil ? Theme.adjusting : Theme.aligned).opacity(0.7), radius: 10)
                Image(systemName: count == nil ? "arrow.counterclockwise" : "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(count == nil ? Theme.adjusting : Theme.aligned)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: 120, height: 120)

            VStack(spacing: 8) {
                Text(count.map { "Reading \($0) of \(target) saved" } ?? "That one didn't work")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                Text(count == nil
                     ? "The measurement wasn't reliable. Let's take it again."
                     : "Keep the same pose for the next one.")
                    .font(.system(size: 16))
                    .foregroundColor(.primary.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            HStack(spacing: 6) {
                ForEach(0..<target, id: \.self) { i in
                    Capsule()
                        .fill(i < (count ?? 0) ? Theme.aligned : Color.primary.opacity(0.25))
                        .frame(width: 26, height: 6)
                }
            }

            VStack(spacing: 10) {
                Button("Next reading", action: onContinue)
                    .buttonStyle(GlowButtonStyle(color: Theme.action))
                if let onShowResult {
                    Button("Show result now", action: onShowResult)
                        .buttonStyle(GhostButtonStyle())
                }
            }
            .padding(.top, 6)
        }
        .padding(24)
        .task {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.2)) { ring = 1 }
            // Back to the camera on its own once the ring fills.
            try? await Task.sleep(for: .milliseconds(2400))
            if !Task.isCancelled { onContinue() }
        }
    }
}

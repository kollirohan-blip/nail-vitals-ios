//
//  CameraManager.swift
//  NailVitals
//
//  First real camera code in the project. Sets up AVCaptureSession
//  and handles permission -- deliberately kept separate from
//  SilhouetteDetector for now (see architecture doc): get a live
//  preview working and verified on real hardware FIRST, before wiring
//  in detection on top of it. This mirrors how we built the Python
//  prototype in stages rather than everything at once.
//
//  STATUS: real code, not a stub -- but untested until run on device.
//

import AVFoundation
import SwiftUI
import Combine  // needed for @Published/ObservableObject -- not always auto-included

final class CameraManager: NSObject, ObservableObject {
    @Published var permissionGranted = false
    @Published var permissionDenied = false

    // First real wiring of SilhouetteDetector + GuidanceEngine to
    // live camera frames -- this is the biggest untested piece in the
    // whole project up to this point. Published so ContentView can
    // react to it directly.
    @Published var captureState: CaptureState = .searching
    @Published var currentDirections: [GuidanceDirection] = [.noFingerDetected]
    // NEW: the live detected silhouette, published so the overlay can
    // draw the REAL detected shape instead of the fixed placeholder
    // outline. nil when nothing's detected.
    @Published var currentSilhouette: DetectedSilhouette?

    // Grid-sampling debug readout -- see SilhouetteDetector's
    // looksSkinToned. Only meaningful once a contour reaches that
    // check; stays 0 otherwise (see detect()'s reset at the top).
    @Published var skinPassingFraction: Double = 0

    // NEW: solidity debug readout -- see SilhouetteDetector's
    // looksLikeCleanSingleShape. Below solidityThreshold means the
    // frame was rejected as a contaminated/non-single-blob contour
    // before even reaching the skin check.
    @Published var solidity: Double = 0

    // Which SilhouetteDetector stage the latest frame stopped at, and
    // GuidanceEngine's raw aspect ratio -- together these tell the HUD
    // exactly which gate is rejecting frames, instead of skin/solid
    // reading 0% ambiguously when a frame never reached those checks.
    @Published var silhouetteStage: SilhouetteRejectionStage = .noContourFound
    @Published var lastAspectRatio: Double = 0

    // Hand-pose landmarks for the latest processed frame (nil = no hand),
    // and how long the model took on it.
    @Published var handLandmarks: HandLandmarks?
    @Published var handPoseMs: Double = 0
    // Landmarks from the SAME frame as capturedPixelBuffer, so the mask
    // segmenter gets a fingertip hint that matches the photo.
    @Published private(set) var capturedLandmarks: HandLandmarks?

    // NEW: the frame captured when the user taps the capture button.
    // Published so ContentView can react (e.g. navigate to a result
    // flow) once it's set. This is a live preview frame reused for
    // capture, NOT a dedicated high-resolution AVCapturePhotoOutput
    // capture -- simpler to wire up first and consistent with how
    // SilhouetteDetector/AngleAnalyzer already consume CVPixelBuffer
    // directly, no format conversion needed. TODO/VERIFY: if the
    // measured angle needs more resolution than the live preview
    // provides, upgrading to a real AVCapturePhotoOutput capture is
    // the next step -- but get the full flow working end-to-end on
    // this simpler path first.
    @Published private(set) var capturedPixelBuffer: CVPixelBuffer?

    // NEW: set by capturePhoto() (called from the main actor, on a UI
    // button tap) and read+cleared inside captureOutput. Dispatched
    // onto frameProcessingQueue in capturePhoto() below specifically
    // so this flag is ONLY ever touched from that one serial queue --
    // same single-queue safety reasoning as lastProcessedTime, just
    // extended to also cover the write from the button tap.
    private nonisolated(unsafe) var captureRequested = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frameProcessingQueue = DispatchQueue(label: "camera.frame.processing")

    private let silhouetteDetector = SilhouetteDetector()
    private let guidanceEngine = GuidanceEngine()
    private let handPoseDetector = HandPoseDetector()

    // Throttling: running full detection on every frame (30-60fps)
    // would be wasteful and likely too slow for this pipeline (it
    // wasn't built with real-time performance in mind originally --
    // see architecture doc). Process at most ~4 times per second.
    // nonisolated(unsafe): mutated from captureOutput, which runs
    // nonisolated on frameProcessingQueue (see the delegate extension
    // below). Safe because this is only ever touched from that one
    // serial queue, never concurrently from elsewhere.
    private nonisolated(unsafe) var lastProcessedTime = Date.distantPast
    private let minProcessingInterval: TimeInterval = 0.25

    // NEW: debounce for the "aligned" state. A single false-positive
    // detection (something skin-colored and tall-narrow enough to
    // slip past the heuristic checks, but not actually a finger) can
    // otherwise flip the UI to green for one flickering frame. Require
    // several consecutive "looksGood" readings before actually
    // showing aligned -- doesn't fix a PERSISTENT false detection, but
    // filters out momentary ones, which is what we actually saw on
    // device testing.
    private var consecutiveAlignedCount = 0
    private let requiredConsecutiveAligned = 4  // roughly 1 second at the current processing rate

    func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    self?.permissionDenied = !granted
                    if granted {
                        self?.configureSession()
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()

            // Use the back camera -- this app photographs a finger,
            // not a selfie.
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back
            ) else {
                print("CameraManager: no back camera available")
                self.session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
            } catch {
                print("CameraManager: failed to create device input: \(error)")
                self.session.commitConfiguration()
                return
            }

            self.videoOutput.setSampleBufferDelegate(self, queue: self.frameProcessingQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            // IMPORTANT: the camera sensor's native buffer orientation
            // is landscape regardless of how the phone is held -- the
            // preview layer rotates automatically for display, but
            // raw sample buffers from AVCaptureVideoDataOutput do NOT
            // unless we explicitly set the connection's orientation.
            // Without this, contour coordinates from SilhouetteDetector
            // would be in landscape space while the screen shows
            // portrait, causing the live outline to be rotated wrong
            // relative to what's actually on screen.
            // UPDATED: switched from the older videoOrientation API
            // (deprecated in iOS 17) to the newer rotation-angle-based
            // API. 90 degrees is the portrait equivalent of the old
            // .portrait case for a back-camera connection.
            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    /// Called by the UI (capture button tap) to request that the NEXT
    /// incoming frame be saved as capturedPixelBuffer. Dispatched onto
    /// frameProcessingQueue rather than set directly, so the flag is
    /// only ever touched from that single queue -- see the property
    /// comment above for why that matters.
    func capturePhoto() {
        frameProcessingQueue.async { [weak self] in
            self?.captureRequested = true
        }
    }

    /// Clears the captured photo -- called when CaptureFlowView is
    /// dismissed (result confirmed, or user backed out), so
    /// ContentView's fullScreenCover closes and a new capture can be
    /// taken. Called directly from a SwiftUI callback, already on the
    /// main thread, so no dispatch needed here (unlike capturePhoto()
    /// above, which is called from the same context but needs to hand
    /// off to frameProcessingQueue for captureRequested specifically).
    func resetCapture() {
        capturedPixelBuffer = nil
        capturedLandmarks = nil
    }

    /// Maps a GuidanceResult's directions to the simpler CaptureState
    /// enum the overlay UI already knows how to display.
    private func mapToCaptureState(_ directions: [GuidanceDirection]) -> CaptureState {
        if directions == [.noFingerDetected] {
            return .searching
        }
        if directions == [.looksGood] {
            return .aligned
        }
        return .adjusting
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    // TODO/VERIFY: marked nonisolated because this method genuinely
    // needs to run on the background frame-processing queue, not the
    // main actor -- newer Swift/Xcode defaults were implicitly
    // treating CameraManager as main-actor isolated (a modern
    // concurrency-safety feature), which conflicted with that. This
    // is the standard pattern for AVFoundation capture delegates in
    // this situation, but I can't fully verify the compiler accepts
    // it without an actual build -- if a different isolation error
    // shows up here, that's the next thing to adjust, not a sign this
    // approach is wrong. The actual @Published property updates still
    // correctly hop back to the main actor via DispatchQueue.main.async
    // below, which is the part that actually matters for SwiftUI.
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= minProcessingInterval else { return }
        lastProcessedTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let landmarks = handPoseDetector.detect(in: pixelBuffer)
        let poseMs = handPoseDetector.lastDurationMs

        // NEW: if the user tapped capture since the last frame, save
        // THIS frame as the captured photo. Checked/cleared here on
        // frameProcessingQueue -- the only queue that ever touches
        // captureRequested, so no race with capturePhoto() setting it.
        // Holding a strong reference to the CVPixelBuffer like this is
        // enough to keep it valid past this callback (standard
        // CoreFoundation ref-counting, toll-free bridged) -- it will
        // NOT get silently recycled out from under us.
        if captureRequested {
            captureRequested = false
            DispatchQueue.main.async { [weak self] in
                self?.capturedLandmarks = landmarks
                self?.capturedPixelBuffer = pixelBuffer
            }
        }

        // SilhouetteDetector + GuidanceEngine run on this background
        // frame-processing queue, not main -- only the resulting
        // @Published updates get dispatched to main for SwiftUI.
        let silhouette = silhouetteDetector.detect(in: pixelBuffer)
        let guidance = guidanceEngine.analyze(silhouette)
        // Read off the grid-sampling debug value right after detect()
        // runs, on this same background queue, then hand it to main
        // along with everything else below.
        let skinFraction = silhouetteDetector.lastSkinPassingFraction
        let solidityValue = silhouetteDetector.lastSolidity
        let stage = silhouetteDetector.lastStage
        let aspectRatio = guidanceEngine.lastAspectRatio

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentDirections = guidance.directions
            self.currentSilhouette = silhouette
            self.skinPassingFraction = skinFraction
            self.solidity = solidityValue
            self.silhouetteStage = stage
            self.lastAspectRatio = aspectRatio
            self.handLandmarks = landmarks
            self.handPoseMs = poseMs

            let rawState = self.mapToCaptureState(guidance.directions)
            if rawState == .aligned {
                self.consecutiveAlignedCount += 1
            } else {
                self.consecutiveAlignedCount = 0
            }

            // Only actually show "aligned" once it's held steady for
            // several consecutive detections -- see the property
            // comments above for why this matters.
            if rawState == .aligned && self.consecutiveAlignedCount < self.requiredConsecutiveAligned {
                self.captureState = .adjusting
            } else {
                self.captureState = rawState
            }
        }
    }
}

/// UIKit bridge -- SwiftUI has no native camera preview view, so this
/// wraps AVCaptureVideoPreviewLayer the standard way.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // No dynamic updates needed yet -- session is set once at creation.
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

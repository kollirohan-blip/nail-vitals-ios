//
//  CameraManager.swift
//  NailVitals
//
//  Camera session, permission, live hand-pose coaching (~4 frames/sec via
//  HandPoseDetector + GuidanceEngine), and full-resolution still capture
//  for measurement.
//

import AVFoundation
import SwiftUI
import Combine  // needed for @Published/ObservableObject -- not always auto-included

final class CameraManager: NSObject, ObservableObject {
    @Published var permissionGranted = false
    @Published var permissionDenied = false

    @Published var captureState: CaptureState = .searching
    /// 0...1 toward "aligned": how much of the required steady hold is done.
    @Published var alignedProgress: Double = 0
    @Published var currentDirections: [GuidanceDirection] = [.noFingerDetected]

    // Hand-pose landmarks for the latest processed frame (nil = no hand),
    // and how long the model took on it.
    @Published var handLandmarks: HandLandmarks?
    @Published var handPoseMs: Double = 0
    // Live glowing finger outline (display only) and its time per update.
    @Published var liveOutline: FingerOutline?
    @Published var outlineMs: Double = 0
    private var lastOutlineAt = Date.distantPast
    // Landmarks from the SAME frame as capturedPixelBuffer, so the mask
    // segmenter gets a fingertip hint that matches the photo.
    @Published private(set) var capturedLandmarks: HandLandmarks?

    // The captured photo (a full-resolution still, or a video frame if the
    // photo output isn't available). Setting it presents CaptureFlowView.
    @Published private(set) var capturedPixelBuffer: CVPixelBuffer?
    /// The phone's flashlight, as soft even light on the finger.
    @Published private(set) var torchOn = false
    /// A capture has been started and not yet reset; stops the automatic
    /// capture and a button tap from both firing.
    private var captureInFlight = false
    /// Extra steady frames after "aligned" before the automatic capture
    /// (about 0.75 s at the processing rate).
    private let autoCaptureHoldFrames = 3
    private var videoDevice: AVCaptureDevice?

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
    // Full-resolution stills for the measurement. A 1080x1920 video frame
    // left the finger only ~110px wide on device -- too few pixels for the
    // cuticle search. Only touched on sessionQueue.
    private let photoOutput = AVCapturePhotoOutput()
    private nonisolated(unsafe) var photoOutputReady = false
    private let frameProcessingQueue = DispatchQueue(label: "camera.frame.processing")

    private let guidanceEngine = GuidanceEngine()
    private let handPoseDetector = HandPoseDetector()

    // The outline runs on its own queue, on every other processed frame and
    // only when the previous run has finished, so hand-pose coaching never
    // waits on it. outlineBusy/outlineFrameCount are only touched on
    // frameProcessingQueue.
    private let outlineQueue = DispatchQueue(label: "camera.outline")
    private let outlineTracker = LiveOutlineTracker()
    private nonisolated(unsafe) var outlineBusy = false
    private nonisolated(unsafe) var outlineFrameCount = 0
    /// Joints found from the outline when hand pose missed the raised
    /// finger, and when; used for coaching until hand pose finds it again.
    /// Only touched on frameProcessingQueue.
    private nonisolated(unsafe) var outlineJoints: (hand: HandLandmarks, at: Date)?

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

            DispatchQueue.main.async { self.videoDevice = device }

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
            // Without this, hand-pose coordinates would be in landscape
            // space while the screen shows portrait.
            // UPDATED: switched from the older videoOrientation API
            // (deprecated in iOS 17) to the newer rotation-angle-based
            // API. 90 degrees is the portrait equivalent of the old
            // .portrait case for a back-camera connection.
            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                if let largest = device.activeFormat.supportedMaxPhotoDimensions
                    .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
                    self.photoOutput.maxPhotoDimensions = largest
                }
                if let connection = self.photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                self.photoOutputReady = self.photoOutput.availablePhotoPixelFormatTypes
                    .contains(kCVPixelFormatType_32BGRA)
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

    /// Called by the UI (capture button tap). Takes a full-resolution
    /// still; if the photo output isn't available, falls back to saving
    /// the NEXT video frame (captureRequested is only ever touched on
    /// frameProcessingQueue -- see the property comment above).
    func capturePhoto() {
        guard !captureInFlight else { return }
        captureInFlight = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.photoOutputReady else {
                self.requestFrameCapture()
                return
            }
            let settings = AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private nonisolated func requestFrameCapture() {
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
        captureInFlight = false
        consecutiveAlignedCount = 0
    }

    /// Turns the flashlight on at low brightness, or off. Low and steady
    /// light evens out shadows on the finger without glare.
    func setTorch(_ on: Bool) {
        guard let device = videoDevice, device.hasTorch else { return }
        torchOn = on
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if on {
                    try device.setTorchModeOn(level: 0.3)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {
                print("CameraManager: torch failed: \(error)")
            }
        }
    }

    var hasTorch: Bool { videoDevice?.hasTorch ?? false }

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

        let visionLandmarks = handPoseDetector.detect(in: pixelBuffer)
        let poseMs = handPoseDetector.lastDurationMs
        updateLiveOutline(pixelBuffer: pixelBuffer, landmarks: visionLandmarks)
        let landmarks = jointsForCoaching(vision: visionLandmarks, now: now)

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

        // Live coaching comes from the hand-pose joints; only the
        // resulting @Published updates get dispatched to main for SwiftUI.
        let guidance = guidanceEngine.analyze(landmarks: landmarks)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentDirections = guidance.directions
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
            // With automatic capture the ring keeps filling through the
            // short hold after "aligned", then the photo is taken.
            let holdFrames = autoCaptureEnabled ? self.autoCaptureHoldFrames : 0
            let fullHold = self.requiredConsecutiveAligned + holdFrames
            self.alignedProgress = min(1, Double(self.consecutiveAlignedCount) / Double(fullHold))
            if autoCaptureEnabled, rawState == .aligned, self.consecutiveAlignedCount >= fullHold,
               self.capturedPixelBuffer == nil {
                self.capturePhoto()
            }
        }
    }
}

extension CameraManager {
    /// Called on frameProcessingQueue for each processed frame. Also runs
    /// when hand pose found nothing, so the outline can find the finger.
    nonisolated func updateLiveOutline(pixelBuffer: CVPixelBuffer, landmarks: HandLandmarks?) {
        outlineFrameCount += 1
        guard !outlineBusy, outlineFrameCount % 2 == 0 else { return }
        outlineBusy = true
        outlineQueue.async { [weak self] in
            guard let self else { return }
            let (outline, hand) = self.outlineTracker.outline(in: pixelBuffer, hand: landmarks)
            let ms = self.outlineTracker.lastDurationMs
            self.frameProcessingQueue.async {
                self.outlineBusy = false
                if let hand, hand.fromOutline {
                    self.outlineJoints = (hand, Date())
                } else if hand != nil {
                    self.outlineJoints = nil  // hand pose has the right finger again
                }
            }
            DispatchQueue.main.async { self.publishOutline(liveOutlineEnabled ? outline : nil, ms: ms) }
        }
    }

    /// Hand pose's joints, unless the outline recently showed that hand
    /// pose is missing the raised finger (no hand, low confidence, or its
    /// "index" is a curled finger): then the outline's joints.
    nonisolated func jointsForCoaching(vision: HandLandmarks?, now: Date) -> HandLandmarks? {
        guard let (outlineHand, at) = outlineJoints, now.timeIntervalSince(at) < 0.8 else { return vision }
        guard let vision, vision.minIndexConfidence >= 0.3 else { return outlineHand }
        let tipGap = hypot(vision.indexTip.point.x - outlineHand.indexTip.point.x, vision.indexTip.point.y - outlineHand.indexTip.point.y)
        let length = hypot(outlineHand.indexTip.point.x - outlineHand.indexMCP.point.x, outlineHand.indexTip.point.y - outlineHand.indexMCP.point.y)
        return tipGap > length * 0.3 ? outlineHand : vision
    }

    /// Keeps the last outline briefly through a missed update, so it
    /// doesn't flicker to the brackets and back.
    private func publishOutline(_ outline: FingerOutline?, ms: Double?) {
        if let ms { outlineMs = ms }
        if let outline {
            liveOutline = outline
            lastOutlineAt = Date()
        } else if Date().timeIntervalSince(lastOutlineAt) > 0.6 {
            liveOutline = nil
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let raw = photo.pixelBuffer else {
            print("CameraManager: photo capture failed (\(String(describing: error))), using a video frame instead")
            requestFrameCapture()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let buffer = Self.uprightPortrait(raw) ?? raw
            // Own detector instance: the live one belongs to frameProcessingQueue.
            let landmarks = HandPoseDetector().detect(in: buffer)
            DispatchQueue.main.async {
                self?.capturedLandmarks = landmarks
                self?.capturedPixelBuffer = buffer
            }
        }
    }

    /// Still-photo buffers may arrive in the sensor's landscape orientation
    /// even with the connection rotated; everything downstream assumes the
    /// same upright portrait frame as the live video buffers.
    private nonisolated static func uprightPortrait(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > height else { return buffer }
        let rotated = CIImage(cvPixelBuffer: buffer).oriented(.right)
        var output: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, height, width, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &output)
        guard let output else { return nil }
        CIContext().render(rotated.transformed(by: CGAffineTransform(translationX: -rotated.extent.minX, y: -rotated.extent.minY)), to: output)
        return output
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

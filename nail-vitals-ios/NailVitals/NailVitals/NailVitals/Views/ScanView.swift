//
//  ScanView.swift
//  NailVitals
//
//  The camera screen for one guided scan session: three readings of the
//  same finger, then one combined result (each sign's middle value). The
//  camera runs only while this screen is open.
//

import SwiftUI

struct ScanView: View {
    static let targetReadings = 3

    /// Leaves without saving.
    let onClose: () -> Void
    /// The session's readings, for the history; called from the result.
    let onSessionDone: ([FingerSigns], MeasuredHand) -> Void

    @StateObject private var camera = CameraManager()
    @State private var sessionReadings: [FingerSigns] = []
    @AppStorage("measuredHand") private var hand: MeasuredHand = .right
    @State private var showGuide = false
    @AppStorage("voiceGuidance") private var voiceOn = true
    @State private var voice = VoiceCoach()
    @State private var haptics = Haptics()
    // Study tagging (testing builds): the selected person and skin tone.
    @AppStorage(StudyRoster.currentKey) private var participant = "P1"
    @AppStorage(StudyRoster.listKey) private var participantsJSON = ""

    private var skinTone: String {
        StudyRoster.decode(participantsJSON).first { $0.code == participant }?.skinTone ?? ""
    }

    var body: some View {
        ZStack {
            if camera.permissionGranted {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            } else if camera.permissionDenied {
                Color.black.ignoresSafeArea()
                Text("Camera access is off. Turn it on in Settings → Nail Vitals → Camera.")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                Color.black.ignoresSafeArea()
            }

            CaptureGuideOverlay(
                state: camera.captureState,
                instructionText: instructionText,
                hand: camera.handLandmarks,
                outline: camera.liveOutline,
                fit: camera.fit,
                direction: camera.currentDirections.first
            )

            VStack {
                topBar
                Spacer()
            }
            // Exposure slider while the light is on, along the right edge
            // like the Camera app's, clear of the guide text and shutter.
            if camera.torchOn {
                HStack {
                    Spacer()
                    exposureSlider
                        .padding(.trailing, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            VStack {
                Spacer()
                Button(action: { camera.capturePhoto() }) {
                    captureButtonFace
                }
                // Only tappable once GuidanceEngine reports .aligned:
                // captures taken while the screen still said "Move back a
                // little" gave badly framed photos no angle tuning could fix.
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
            haptics.prepare()
        }
        .onDisappear {
            camera.stop()
            voice.stop()
        }
        // Spoken cues while framing (not while a photo is being measured).
        .onChange(of: camera.currentDirections) { _, directions in
            guard voiceOn, camera.capturedPixelBuffer == nil else { return }
            voice.update(directions.first)
        }
        // Light ticks as the finger fills the target. None once a photo
        // is under way: a buzz during the exposure can blur it.
        .onChange(of: camera.fit) { old, new in
            guard !camera.captureInFlight else { return }
            haptics.fitChanged(from: old, to: new)
        }
        // Locked on: a success buzz as the glove turns green. The automatic
        // photo comes about 0.75 s later, after the buzz has finished.
        .onChange(of: camera.captureState) { _, state in
            guard state == .aligned, !camera.captureInFlight else { return }
            haptics.locked()
        }
        // The photo has been delivered: a thump and "Got it".
        .onChange(of: camera.capturedPixelBuffer != nil) { _, captured in
            guard captured else { return }
            haptics.shutter()
            if voiceOn { voice.speak("Got it.") }
        }
        .onChange(of: voiceOn) { _, on in if !on { voice.stop() } }
        // Readings of the two hands differ, so switching starts a new session.
        .onChange(of: hand) { _, _ in sessionReadings = [] }
        .sheet(isPresented: $showGuide) { PoseGuideView() }
        // Presents once CameraManager.capturedPixelBuffer is set (isPresented
        // bound to a nil check, since CVPixelBuffer isn't Identifiable).
        .fullScreenCover(isPresented: Binding(
            get: { camera.capturedPixelBuffer != nil },
            set: { isPresented in
                if !isPresented { camera.resetCapture() }
            }
        )) {
            if let buffer = camera.capturedPixelBuffer {
                CaptureFlowView(
                    pixelBuffer: buffer,
                    landmarks: camera.capturedLandmarks,
                    hand: hand,
                    participant: saveCapturesForTesting ? participant : nil,
                    skinTone: saveCapturesForTesting && !skinTone.isEmpty ? skinTone : nil,
                    onDismiss: { camera.resetCapture() },
                    previousReadings: sessionReadings,
                    targetReadings: Self.targetReadings,
                    onReading: { sessionReadings.append($0) },
                    onFinishSession: {
                        let readings = sessionReadings
                        camera.resetCapture()
                        onSessionDone(readings, hand)
                    },
                    onStartOver: {
                        sessionReadings = []
                        camera.resetCapture()
                    }
                )
            }
        }
    }

    // MARK: - Top bar

    /// Close on the left, session progress in the middle, everything else
    /// in one menu on the right.
    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            progressChip
            Spacer()
            Menu {
                Picker("Finger", selection: $hand) {
                    ForEach(MeasuredHand.allCases, id: \.self) { option in
                        Text("\(option.label) index").tag(option)
                    }
                }
                if camera.hasTorch {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { camera.setTorch(!camera.torchOn) }
                    } label: {
                        Label(camera.torchOn ? "Light off" : "Light on", systemImage: camera.torchOn ? "flashlight.off.fill" : "flashlight.on.fill")
                    }
                }
                Toggle(isOn: $voiceOn) {
                    Label("Voice guidance", systemImage: voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                Button { showGuide = true } label: {
                    Label("How to hold your finger", systemImage: "questionmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Options")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// "Reading 2 of 3" with a dot per reading; shows the hand too.
    private var progressChip: some View {
        let done = sessionReadings.count
        let current = min(done + 1, Self.targetReadings)
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<Self.targetReadings, id: \.self) { i in
                    Circle()
                        .fill(i < done ? Theme.aligned : (i == done ? Theme.searching : Color.white.opacity(0.3)))
                        .frame(width: 7, height: 7)
                }
            }
            Text("Reading \(current) of \(Self.targetReadings)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            Text("· \(hand.label)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: done)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pieces

    /// Vertical exposure control: drag down to darken if the light makes
    /// the nail glare white.
    private var exposureSlider: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 13, weight: .semibold))
            Slider(value: Binding(get: { Double(camera.exposureBias) },
                                  set: { camera.setExposureBias(Float($0)) }),
                   in: Double(CameraManager.exposureRange.lowerBound)...Double(CameraManager.exposureRange.upperBound))
                .tint(Theme.adjusting)
                .frame(width: 170)
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: 170)
            Image(systemName: "sun.min")
                .font(.system(size: 13, weight: .semibold))
            Text(String(format: "%+.1f", camera.exposureBias))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundColor(.white)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Exposure")
    }

    /// Shutter with a "hold still" ring that fills as alignment steadies;
    /// dimmed (but visible) until aligned.
    private var captureButtonFace: some View {
        let aligned = camera.captureState == .aligned
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 4)
            Circle()
                .trim(from: 0, to: camera.alignedProgress)
                .stroke(Theme.aligned, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: camera.alignedProgress)
            Circle()
                .fill(Color.white)
                .padding(8)
                .scaleEffect(aligned ? 1 : 0.82)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: aligned)
        }
        .frame(width: 78, height: 78)
        .shadow(radius: 10)
        .opacity(aligned ? 1 : 0.55)
    }

    private var instructionText: String {
        guard let first = camera.currentDirections.first else {
            return "Hold your index finger up here"
        }
        switch first {
        case .noFingerDetected: return "Hold your index finger up here"
        case .moveCloser: return "Move closer"
        case .moveBack: return "Move back"
        case .moveLeft: return "Move left"
        case .moveRight: return "Move right"
        case .straighten: return "Straighten your finger"
        case .turnToSide: return "Turn your finger fully sideways"
        case .moveHandDown: return "Move your hand down"
        case .moveUp: return "Move your hand up"
        case .looksGood: return autoCaptureEnabled ? "Perfect, hold still" : "Perfect, tap the button"
        }
    }

    private var debugDirectionsText: String {
        camera.currentDirections.map { "\($0)" }.joined(separator: ", ")
    }

    private var handReadoutText: String {
        guard let hand = camera.handLandmarks else { return "hand: none" }
        return String(format: "hand conf %.2f  length %.0f%%  tilt %.0f°  outline %.0f ms",
                      hand.minIndexConfidence, hand.fingerLengthFraction * 100, hand.tiltFromVerticalDegrees, camera.outlineMs)
    }
}

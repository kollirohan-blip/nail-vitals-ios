// ContentView.swift

import SwiftUI

struct ContentView: View {
    /// False while the opening animation still covers the screen.
    var splashFinished = true

    @StateObject private var camera = CameraManager()
    /// Confirmed readings of the current session; cleared by "Finish".
    @State private var sessionReadings: [FingerSigns] = []
    @AppStorage("measuredHand") private var hand: MeasuredHand = .right
    @AppStorage("hasSeenPoseGuide") private var hasSeenPoseGuide = false
    @State private var showGuide = false

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
                hand: camera.handLandmarks,
                outline: camera.liveOutline
            )

            VStack {
                topBar
                Spacer()
                Button(action: {
                    camera.capturePhoto()
                }) {
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
            showGuideOnFirstLaunch()
        }
        .onChange(of: splashFinished) { _, _ in showGuideOnFirstLaunch() }
        // Readings of the two hands differ, so switching starts a new session.
        .onChange(of: hand) { _, _ in sessionReadings = [] }
        .sheet(isPresented: $showGuide, onDismiss: { hasSeenPoseGuide = true }) {
            PoseGuideView()
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
                CaptureFlowView(
                    pixelBuffer: buffer,
                    landmarks: camera.capturedLandmarks,
                    hand: hand,
                    onDismiss: { camera.resetCapture() },
                    previousReadings: sessionReadings,
                    onReading: { sessionReadings.append($0) },
                    onFinishSession: {
                        sessionReadings = []
                        camera.resetCapture()
                    }
                )
            }
        }
    }

    private func showGuideOnFirstLaunch() {
        if splashFinished && !hasSeenPoseGuide && !showGuide {
            showGuide = true
        }
    }

    /// Which index finger is measured, and the "how to hold it" guide.
    private var topBar: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(MeasuredHand.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { hand = option }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(hand == option ? .black : .white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(hand == option ? Theme.searching : Color.clear))
                    }
                }
            }
            .padding(3)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Measured hand")
            Text("index")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Button { showGuide = true } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("How to hold your finger")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
        return String(format: "hand conf %.2f  length %.0f%%  tilt %.0f°  outline %.0f ms",
                      hand.minIndexConfidence, hand.fingerLengthFraction * 100, hand.tiltFromVerticalDegrees, camera.outlineMs)
    }
}

#Preview {
    ContentView()
}


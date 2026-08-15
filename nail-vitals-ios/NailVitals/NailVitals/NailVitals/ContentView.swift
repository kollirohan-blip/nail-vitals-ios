//
//  ContentView.swift
//  NailVitals
//
//  First real end-to-end wiring: live camera -> SilhouetteDetector ->
//  GuidanceEngine -> CaptureGuideOverlay, all running on-device. This
//  replaces the manual "Simulate next frame" button test from the
//  previous version -- now driven entirely by CameraManager's
//  @Published captureState.
//
//  Includes a debug readout of the raw GuidanceDirection values on
//  screen, since this is the first real-world test of the whole
//  detection pipeline -- useful for seeing exactly what it's finding
//  (or not finding) rather than guessing from the overlay color alone.
//

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
                // Debug readout -- remove once the pipeline is
                // trusted; useful right now for seeing exactly what
                // GuidanceEngine is detecting in real conditions.
                Text(debugDirectionsText)
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
        camera.currentDirections.map { "\($0)" }.joined(separator: ", ")
    }
}

#Preview {
    ContentView()
}

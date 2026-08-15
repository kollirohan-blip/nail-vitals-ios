//
//  ContentView.swift
//  NailVitals
//
//  Temporary test wiring: shows CaptureGuideOverlay directly against
//  a plain background (no camera yet) just to confirm it renders
//  correctly on a real device, with a button to manually cycle
//  through the three states. Once SilhouetteDetector/GuidanceEngine
//  are wired to a real camera feed, this gets replaced with the
//  actual camera view.
//

import SwiftUI

struct ContentView: View {
    @State private var state: CaptureState = .searching
    @StateObject private var camera = CameraManager()

    private let statesInOrder: [CaptureState] = [.searching, .adjusting, .aligned]

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
                state: state,
                instructionText: instructionText,
                subText: subText
            )

            VStack {
                Spacer()
                Button(action: cycleState) {
                    Text("Simulate next frame")
                        .font(.system(size: 15, weight: .semibold))
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.bottom, 60)
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
        switch state {
        case .searching: return "Align your finger with the outline"
        case .adjusting: return "Getting closer"
        case .aligned: return "Perfect, hold still"
        }
    }

    private var subText: String {
        switch state {
        case .searching: return "Hold your finger sideways, nail facing the camera"
        case .adjusting: return "Rotate slightly so the nail edge is visible"
        case .aligned: return "Capturing..."
        }
    }

    private func cycleState() {
        let currentIndex = statesInOrder.firstIndex(of: state) ?? 0
        state = statesInOrder[(currentIndex + 1) % statesInOrder.count]
    }
}

#Preview {
    ContentView()
}

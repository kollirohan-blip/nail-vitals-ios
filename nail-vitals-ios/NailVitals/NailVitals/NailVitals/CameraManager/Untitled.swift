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

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

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

            // TODO: add AVCaptureVideoDataOutput here once we're ready
            // to feed frames into SilhouetteDetector for live guidance.
            // Kept out for now -- this step is ONLY about getting a
            // preview on screen and confirming the session itself
            // works on real hardware first.

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
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
 

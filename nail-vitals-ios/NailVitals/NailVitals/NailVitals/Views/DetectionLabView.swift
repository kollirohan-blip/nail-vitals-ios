//
//  DetectionLabView.swift
//  NailVitals
//
//  Go/no-go test screen for the pivot: shows Apple's hand-pose joints live
//  over the camera, and a "Test mask" button that freezes a frame, traces
//  the finger outline from the subject mask, and runs AngleAnalyzer on it.
//  Enabled by showDetectionLab in NailVitalsApp.swift.
//

import SwiftUI

struct DetectionLabView: View {
    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            if camera.permissionGranted {
                CameraPreviewView(session: camera.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            GeometryReader { geo in
                if let hand = camera.handLandmarks {
                    landmarkOverlay(hand, viewSize: geo.size)
                }
            }
            .ignoresSafeArea()

            VStack {
                readout
                    .padding(.top, 60)
                Spacer()
                Button(action: { camera.capturePhoto() }) {
                    Text("Test mask")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(28)
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear { camera.checkPermissionAndStart() }
        .onDisappear { camera.stop() }
        .fullScreenCover(isPresented: Binding(
            get: { camera.capturedPixelBuffer != nil },
            set: { if !$0 { camera.resetCapture() } }
        )) {
            if let buffer = camera.capturedPixelBuffer {
                MaskTestView(pixelBuffer: buffer, landmarks: camera.capturedLandmarks) {
                    camera.resetCapture()
                }
            }
        }
    }

    private var readout: some View {
        let lines: [String]
        if let h = camera.handLandmarks {
            lines = [
                "HAND FOUND   pose \(Int(camera.handPoseMs)) ms",
                String(format: "conf tip %.2f  dip %.2f  pip %.2f  mcp %.2f",
                       h.indexTip.confidence, h.indexDIP.confidence, h.indexPIP.confidence, h.indexMCP.confidence),
                String(format: "finger length %.0f%% of height   tilt %.0f°",
                       h.fingerLengthFraction * 100, h.tiltFromVerticalDegrees)
            ]
        } else {
            lines = ["no hand   pose \(Int(camera.handPoseMs)) ms"]
        }
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(lines, id: \.self) { Text($0) }
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundColor(.white)
        .padding(10)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }

    private func landmarkOverlay(_ hand: HandLandmarks, viewSize: CGSize) -> some View {
        // Preview uses aspect FILL, so map with the larger scale and a
        // centered crop offset.
        let scale = max(viewSize.width / hand.imageSize.width, viewSize.height / hand.imageSize.height)
        let offsetX = (viewSize.width - hand.imageSize.width * scale) / 2
        let offsetY = (viewSize.height - hand.imageSize.height * scale) / 2
        func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + offsetX, y: p.y * scale + offsetY) }

        let joints = [hand.indexTip, hand.indexDIP, hand.indexPIP, hand.indexMCP]
        return ZStack {
            Path { path in
                path.addLines(joints.map { toView($0.point) })
            }
            .stroke(Color.cyan, lineWidth: 3)
            ForEach(Array(joints.enumerated()), id: \.offset) { _, joint in
                Circle()
                    .fill(joint.confidence > 0.5 ? Color.green : Color.orange)
                    .frame(width: 14, height: 14)
                    .position(toView(joint.point))
            }
        }
    }
}

/// Frozen-frame result of the subject mask + AngleAnalyzer.
private struct MaskTestView: View {
    let pixelBuffer: CVPixelBuffer
    let landmarks: HandLandmarks?
    let onDone: () -> Void

    @State private var image: UIImage?
    @State private var silhouette: DetectedSilhouette?
    @State private var result: LovibondResult?
    @State private var diagnostics = FingerMaskSegmenter.Diagnostics()
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                if let image {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                        overlay(imageSize: image.size, viewSize: geo.size)
                    }
                }
            }
            VStack {
                Text(summary)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.top, 20)
                Spacer()
                Button("Back", action: onDone)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(24)
                    .padding(.bottom, 30)
            }
        }
        .onAppear(perform: run)
    }

    private var summary: String {
        guard finished else { return "Running mask..." }
        var lines = [
            "instances \(diagnostics.instanceCount)  chosen #\(diagnostics.chosenInstance)",
            "mask \(Int(diagnostics.maskMs)) ms  contour \(Int(diagnostics.contourMs)) ms  pts \(diagnostics.contourPointCount)",
            landmarks == nil ? "no hand-pose hint (used largest subject)" : "hint: index DIP from hand pose"
        ]
        if silhouette == nil {
            lines.append("NO OUTLINE FOUND")
        } else if let result {
            for c in result.candidates {
                lines.append(String(format: "%@ candidate: %.1f°", c.side, c.angleDegrees))
            }
        } else {
            lines.append("outline found, AngleAnalyzer returned nothing")
        }
        return lines.joined(separator: "\n")
    }

    private func overlay(imageSize: CGSize, viewSize: CGSize) -> some View {
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * scale) / 2
        let offsetY = (viewSize.height - imageSize.height * scale) / 2
        func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + offsetX, y: p.y * scale + offsetY) }

        return ZStack {
            if let silhouette {
                Path { path in
                    path.addLines(silhouette.contourPoints.map(toView))
                    path.closeSubpath()
                }
                .stroke(Color.green, lineWidth: 2)
            }
            if let result {
                Circle().fill(Color.white).frame(width: 10, height: 10).position(toView(result.fingertip))
                ForEach(Array(result.candidates.enumerated()), id: \.offset) { _, c in
                    Circle()
                        .stroke(c.side == "left" ? Color.yellow : Color.pink, lineWidth: 3)
                        .frame(width: 22, height: 22)
                        .position(toView(c.inflectionPoint))
                }
            }
            if let hint = landmarks?.indexDIP.point {
                Circle().fill(Color.cyan).frame(width: 10, height: 10).position(toView(hint))
            }
        }
    }

    private func run() {
        let buffer = pixelBuffer
        let hint = landmarks?.indexDIP.point
        DispatchQueue.global(qos: .userInitiated).async {
            let segmenter = FingerMaskSegmenter()
            let sil = segmenter.segment(pixelBuffer: buffer, fingertipHint: hint)
            let res = sil.flatMap { AngleAnalyzer().analyze($0) }
            let ciImage = CIImage(cvPixelBuffer: buffer)
            let cg = CIContext().createCGImage(ciImage, from: ciImage.extent)
            let diag = segmenter.lastDiagnostics
            DispatchQueue.main.async {
                image = cg.map { UIImage(cgImage: $0) }
                silhouette = sil
                result = res
                diagnostics = diag
                finished = true
            }
        }
    }
}

//
//  HandPoseDetector.swift
//  NailVitals
//
//  Live finger finding via Apple's trained hand-pose model, replacing the
//  edge-detection + color/shape-rule approach for coaching. Returns the
//  index finger's joints in image pixels (top-left origin, same convention
//  as DetectedSilhouette) so GuidanceEngine and the mask segmenter can use
//  them directly.
//

import Vision
import CoreGraphics

nonisolated struct HandLandmarks {
    nonisolated struct Joint {
        let point: CGPoint
        let confidence: Float
    }

    let indexTip: Joint
    let indexDIP: Joint
    let indexPIP: Joint
    let indexMCP: Joint
    let wrist: Joint?
    let thumbTip: Joint?
    /// Knuckles of the other fingers, for telling how far the hand is
    /// turned (see knuckleSpread).
    var middleMCP: Joint? = nil
    var littleMCP: Joint? = nil
    let imageSize: CGSize
    /// Found from the hand outline because hand pose missed the raised
    /// finger (OutlineFingerFinder); the joint positions are estimates.
    var fromOutline = false

    /// How far apart the index and little-finger knuckles look, relative to
    /// the index finger's length. Seen exactly from the side they line up
    /// behind each other (near 0); turning the back of the hand toward the
    /// camera spreads them out.
    /// The back of the hand is clearly turned toward the camera. On real
    /// captures, side views spread 0.05-0.28 and clearly turned hands
    /// 0.50-0.70; small turns overlap with side views and aren't caught.
    var isClearlyTurned: Bool {
        guard let spread = knuckleSpread, let little = littleMCP, little.confidence >= 0.3 else { return false }
        return spread > 0.42
    }

    var knuckleSpread: Double? {
        guard let little = littleMCP else { return nil }
        let length = hypot(indexTip.point.x - indexMCP.point.x, indexTip.point.y - indexMCP.point.y)
        guard length > 0 else { return nil }
        return Double(hypot(little.point.x - indexMCP.point.x, little.point.y - indexMCP.point.y) / length)
    }

    /// Whether an image point lies on the nail (back-of-hand) side of the
    /// index finger. In the side-view pose the nail faces away from the
    /// thumb, so it's the side of the finger axis opposite the thumb tip.
    /// nil when the thumb wasn't found or sits on the axis.
    func isOnNailSide(_ p: CGPoint) -> Bool? {
        guard let thumb = thumbTip?.point else { return nil }
        let a = indexMCP.point, b = indexTip.point
        func side(_ q: CGPoint) -> CGFloat { (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x) }
        let thumbSide = side(thumb)
        guard abs(thumbSide) > 1e-6 else { return nil }
        return side(p) * thumbSide < 0
    }

    var minIndexConfidence: Float {
        min(indexTip.confidence, indexDIP.confidence, indexPIP.confidence, indexMCP.confidence)
    }

    /// Tip-to-MCP distance as a fraction of image height -- the live
    /// "how close is the finger" measure.
    var fingerLengthFraction: Double {
        Double(hypot(indexTip.point.x - indexMCP.point.x, indexTip.point.y - indexMCP.point.y) / imageSize.height)
    }

    /// Degrees the MCP->tip direction leans away from straight up.
    var tiltFromVerticalDegrees: Double {
        let dx = indexTip.point.x - indexMCP.point.x
        let dy = indexMCP.point.y - indexTip.point.y
        return abs(Double(atan2(dx, dy))) * 180 / .pi
    }
}

nonisolated final class HandPoseDetector {

    private(set) nonisolated(unsafe) var lastDurationMs: Double = 0

    func detect(in pixelBuffer: CVPixelBuffer) -> HandLandmarks? {
        let start = CFAbsoluteTimeGetCurrent()
        defer { lastDurationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000 }

        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        // CameraManager rotates the connection to portrait, so buffers are
        // already upright.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("HandPoseDetector: Vision request failed: \(error)")
            return nil
        }
        guard let observation = request.results?.first,
              let finger = try? observation.recognizedPoints(.indexFinger) else { return nil }

        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))

        func joint(_ point: VNRecognizedPoint?) -> HandLandmarks.Joint? {
            guard let point, point.confidence > 0 else { return nil }
            return HandLandmarks.Joint(
                point: CGPoint(x: point.location.x * imageSize.width, y: (1 - point.location.y) * imageSize.height),
                confidence: point.confidence
            )
        }

        guard let tip = joint(finger[.indexTip]),
              let dip = joint(finger[.indexDIP]),
              let pip = joint(finger[.indexPIP]),
              let mcp = joint(finger[.indexMCP]) else { return nil }

        return HandLandmarks(
            indexTip: tip, indexDIP: dip, indexPIP: pip, indexMCP: mcp,
            wrist: joint(try? observation.recognizedPoint(.wrist)),
            thumbTip: joint(try? observation.recognizedPoint(.thumbTip)),
            middleMCP: joint(try? observation.recognizedPoint(.middleMCP)),
            littleMCP: joint(try? observation.recognizedPoint(.littleMCP)),
            imageSize: imageSize
        )
    }
}

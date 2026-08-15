//
//  SilhouetteDetector.swift
//  NailVitals
//
//  Vision-framework port of isolate_silhouette() + get_largest_contour()
//  from contour_angle.py. NOT YET COMPILED/TESTED -- there's no Swift
//  toolchain available where this was written, so treat this as a
//  strong first draft to debug on the Mac, not verified-working code.
//  Flagged uncertainties are marked TODO/VERIFY below.
//
//  Approach: the Python version combined two threshold signals
//  (grayscale Otsu + HSV-saturation Otsu, via OR) specifically because
//  a bright specular highlight on skin could fool grayscale alone into
//  misclassifying part of the fingertip as background. Vision's
//  VNDetectContoursRequest doesn't take a custom binary mask directly
//  -- it does its own contrast-based edge detection on the image you
//  give it. So instead of replicating Otsu thresholding manually, we
//  preprocess with Core Image to boost the luminance/saturation
//  separation between skin and a plain background BEFORE handing off
//  to Vision, then let VNDetectContoursRequest do the contour tracing.
//

import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

final class SilhouetteDetector {

    private let context = CIContext()

    /// Full pipeline: preprocess for skin/background separation ->
    /// Vision contour detection -> pick the largest contour ->
    /// convert normalized Vision coordinates into image-pixel
    /// coordinates (matching what AngleAnalyzer/GuidanceEngine expect,
    /// same convention as the Python contour arrays).
    func detect(in pixelBuffer: CVPixelBuffer) -> DetectedSilhouette? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        guard let preprocessed = preprocessForSeparation(ciImage) else {
            return nil
        }

        guard let cgImage = context.createCGImage(preprocessed, from: preprocessed.extent) else {
            return nil
        }

        let request = VNDetectContoursRequest()
        // TODO/VERIFY: tune these two on real device photos, same way
        // we tuned Otsu thresholds against real data in Python -- these
        // starting values are reasonable guesses, not calibrated.
        request.contrastAdjustment = 2.0
        request.detectsDarkOnLight = false  // finger is usually lighter than a plain background in our test photos; VERIFY against actual capture conditions, may need to be true depending on background choice
        request.maximumImageDimension = 512  // downscale for speed during LIVE guidance; use a higher value or omit for the final high-res capture analysis

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("SilhouetteDetector: Vision request failed: \(error)")
            return nil
        }

        guard let observation = request.results?.first as? VNContoursObservation else {
            return nil
        }

        // Pick the largest top-level contour by point count as a proxy
        // for contour complexity/size -- matches get_largest_contour()'s
        // use of cv2.contourArea, though point count isn't a perfect
        // substitute for area. TODO/VERIFY: consider computing actual
        // polygon area from normalizedPoints instead, the way Python
        // does with cv2.contourArea, if point-count picks the wrong
        // contour in practice.
        guard let largestContour = observation.topLevelContours.max(by: { $0.pointCount < $1.pointCount }) else {
            return nil
        }

        // Vision's normalizedPoints are in a 0-1 coordinate space with
        // origin at BOTTOM-left (unlike OpenCV/UIKit's top-left origin).
        // Flip the Y axis here so downstream code (AngleAnalyzer,
        // GuidanceEngine) can assume top-left origin, matching the
        // Python prototype's coordinate convention.
        let imagePoints: [CGPoint] = largestContour.normalizedPoints.map { point in
            CGPoint(
                x: CGFloat(point.x) * imageSize.width,
                y: (1 - CGFloat(point.y)) * imageSize.height
            )
        }

        guard !imagePoints.isEmpty else { return nil }

        let boundingBox = boundingRect(of: imagePoints)

        return DetectedSilhouette(
            boundingBox: boundingBox,
            contourPoints: imagePoints,
            imageSize: imageSize
        )
    }

    /// Boosts separation between skin and a plain background before
    /// Vision's contour detection runs. Combines a saturation boost
    /// (skin holds color even when brightly lit; a plain white/gray
    /// background stays desaturated) with a contrast boost -- this is
    /// the Swift-side echo of Python's grayscale+saturation combined
    /// approach, just implemented as image preprocessing instead of
    /// two separate binary masks ORed together.
    ///
    /// TODO/VERIFY: this is the piece most likely to need real tuning
    /// against actual device photos. If Vision's contour detection
    /// still clips a bright specular highlight on the fingertip (the
    /// exact bug we found and fixed in the Python version), that's the
    /// signal this preprocessing needs adjustment, not a sign the
    /// overall approach is wrong.
    private func preprocessForSeparation(_ image: CIImage) -> CIImage? {
        let saturationFilter = CIFilter.colorControls()
        saturationFilter.inputImage = image
        saturationFilter.saturation = 2.0
        saturationFilter.contrast = 1.3

        guard let output = saturationFilter.outputImage else { return nil }
        return output
    }

    private func boundingRect(of points: [CGPoint]) -> CGRect {
        guard let firstPoint = points.first else { return .zero }
        var minX = firstPoint.x, maxX = firstPoint.x
        var minY = firstPoint.y, maxY = firstPoint.y
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

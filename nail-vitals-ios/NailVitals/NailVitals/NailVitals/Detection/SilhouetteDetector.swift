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

/// The result of silhouette detection -- consumed by GuidanceEngine
/// (live, every frame) and AngleAnalyzer (once, on the final captured
/// photo). This definition was accidentally dropped when this file
/// was rewritten with the real Vision implementation -- it needs to
/// live somewhere all three files can see it.
struct DetectedSilhouette {
    let boundingBox: CGRect      // in image coordinates
    let contourPoints: [CGPoint] // ordered contour points
    let imageSize: CGSize
}

// nonisolated: fixes a cascading series of warnings where marking
// just the public detect() method nonisolated wasn't enough --
// every private helper it called (preprocessForSeparation,
// boundingRect, looksSkinToned) hit the identical warning one at a
// time, since Swift's default main-actor isolation applies per-member,
// not just to the entry point. This class has no shared mutable
// state that needs actor protection (only `let context`), so marking
// the whole type nonisolated is correct, not just a workaround.
nonisolated final class SilhouetteDetector {

    private let context = CIContext()

    /// Full pipeline: preprocess for skin/background separation ->
    /// Vision contour detection -> pick the largest contour ->
    /// convert normalized Vision coordinates into image-pixel
    /// coordinates (matching what AngleAnalyzer/GuidanceEngine expect,
    /// same convention as the Python contour arrays).
    // nonisolated: called synchronously from CameraManager's
    // nonisolated captureOutput() on a background queue -- this
    // method only touches `context` (a let constant) and has no
    // shared mutable state, so it's safe to mark nonisolated.
    nonisolated func detect(in pixelBuffer: CVPixelBuffer) -> DetectedSilhouette? {
        let fullImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        // BUG FIX: an earlier version of this function CROPPED the
        // input image to a central region before running detection,
        // intending to ignore distant unrelated edges (door frames,
        // furniture). That introduced a WORSE bug: cropping creates a
        // hard, artificial rectangular edge exactly at the crop
        // boundary, and after the contrast/saturation boost below,
        // Vision was detecting THAT edge as the largest contour --
        // this showed up on device as a huge rectangle roughly the
        // size of the crop region, not the finger at all.
        //
        // Correct approach: run detection on the FULL, unmodified
        // image (no fake edges introduced), then FILTER the results
        // to prefer contours centered in frame. This achieves the
        // same goal (ignore a door frame in the corner) without ever
        // creating an artificial boundary for Vision to misdetect.
        guard let preprocessed = preprocessForSeparation(fullImage) else {
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

        // Convert EVERY top-level contour's points to full-image
        // pixel coordinates (not just the single largest one), so we
        // can filter by position before picking a winner.
        func toImagePoints(_ contour: VNContour) -> [CGPoint] {
            contour.normalizedPoints.map { point in
                CGPoint(
                    x: CGFloat(point.x) * imageSize.width,
                    y: (1 - CGFloat(point.y)) * imageSize.height
                )
            }
        }

        // Prefer contours whose CENTER falls within a central region
        // of the frame -- this is the actual fix for the original
        // problem (a door frame or table edge far from where a
        // properly-held finger should be), applied as a filter on
        // results instead of a crop on the input.
        let roiWidthFraction: CGFloat = 0.65
        let roiHeightFraction: CGFloat = 0.85
        let roiMinX = imageSize.width * (1 - roiWidthFraction) / 2
        let roiMaxX = imageSize.width - roiMinX
        let roiMinY = imageSize.height * (1 - roiHeightFraction) / 2
        let roiMaxY = imageSize.height - roiMinY

        let centeredContours = observation.topLevelContours.filter { contour in
            let points = toImagePoints(contour)
            guard !points.isEmpty else { return false }
            let box = boundingRect(of: points)
            let centerX = box.midX
            let centerY = box.midY
            return centerX >= roiMinX && centerX <= roiMaxX
                && centerY >= roiMinY && centerY <= roiMaxY
        }

        // Among the centered candidates, pick the largest by point
        // count -- matches get_largest_contour()'s use of
        // cv2.contourArea as a size proxy. TODO/VERIFY: consider
        // computing actual polygon area from normalizedPoints instead,
        // if point-count picks the wrong contour in practice.
        guard let largestContour = centeredContours.max(by: { $0.pointCount < $1.pointCount }) else {
            return nil
        }

        let imagePoints = toImagePoints(largestContour)

        guard !imagePoints.isEmpty else { return nil }

        let boundingBox = boundingRect(of: imagePoints)

        // NEW: skin-tone plausibility check, added after real device
        // testing showed non-finger objects (a wood table + plastic
        // figures, specifically) could pass the aspect-ratio check
        // and still get treated as a valid finger. Whatever's
        // detected should at least look roughly skin-colored -- this
        // won't catch everything (another hand-shaped skin-toned
        // object would still pass), but it directly addresses the
        // false positive we actually observed.
        guard looksSkinToned(pixelBuffer: pixelBuffer, in: boundingBox, imageSize: imageSize) else {
            return nil
        }

        return DetectedSilhouette(
            boundingBox: boundingBox,
            contourPoints: imagePoints,
            imageSize: imageSize
        )
    }

    /// Samples average color within the detected region and checks it
    /// against a broad, deliberately permissive skin-tone range (needs
    /// to work across many real skin tones, not just one). This is a
    /// coarse sanity check, not a precise classifier -- the goal is
    /// filtering out obviously-wrong objects (furniture, walls, toys),
    /// not perfectly validating skin.
    private func looksSkinToned(pixelBuffer: CVPixelBuffer, in boundingBox: CGRect, imageSize: CGSize) -> Bool {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Sample a smaller center region of the bounding box, to avoid
        // averaging in background pixels right at the silhouette's edge.
        let sampleRect = boundingBox.insetBy(
            dx: boundingBox.width * 0.3,
            dy: boundingBox.height * 0.3
        )
        guard sampleRect.width > 0, sampleRect.height > 0 else { return false }

        // CIImage's coordinate origin is bottom-left; boundingBox is
        // in the top-left-origin convention used elsewhere in this
        // file (see the Y-flip above), so flip back for sampling.
        let ciSampleRect = CGRect(
            x: sampleRect.minX,
            y: imageSize.height - sampleRect.maxY,
            width: sampleRect.width,
            height: sampleRect.height
        )

        let extentVector = CIVector(
            x: ciSampleRect.origin.x, y: ciSampleRect.origin.y,
            z: ciSampleRect.width, w: ciSampleRect.height
        )
        guard let averageFilter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: extentVector
        ]) else { return false }
        guard let outputImage = averageFilter.outputImage else { return false }

        var pixelData = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage, toBitmap: &pixelData, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )

        let r = Double(pixelData[0]) / 255.0
        let g = Double(pixelData[1]) / 255.0
        let b = Double(pixelData[2]) / 255.0

        // Broad, permissive skin-tone heuristic (needs to work across
        // a wide range of real skin tones): red channel should
        // dominate or be close to green, and not be too desaturated
        // (rules out grays/whites like a wall or table) or too
        // saturated toward blue/green (rules out most fabrics,
        // plastics, wood tones outside a skin-like range).
        let maxChannel = max(r, g, b)
        let minChannel = min(r, g, b)
        let saturation = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0

        let redDominant = r >= g * 0.95 && r >= b
        let reasonableSaturation = saturation > 0.03 && saturation < 0.6
        let reasonableBrightness = maxChannel > 0.2 && maxChannel < 0.98

        return redDominant && reasonableSaturation && reasonableBrightness
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
        // TODO/VERIFY: reduced from saturation=2.0, contrast=1.3 --
        // device testing showed even a genuinely plain wall could
        // produce large spurious detected shapes, likely because that
        // aggressive a boost turns very subtle, real lighting
        // gradients (a wall is never perfectly uniformly lit) into
        // edges sharp enough for Vision to treat as object boundaries.
        // This is a first attempt at dialing it back, not a verified
        // fix -- if spurious detections persist, the contour-detection
        // approach itself may need contrastAdjustment tuned down too
        // (see the VNDetectContoursRequest setup), not just this
        // preprocessing step.
        saturationFilter.saturation = 1.3
        saturationFilter.contrast = 1.05

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

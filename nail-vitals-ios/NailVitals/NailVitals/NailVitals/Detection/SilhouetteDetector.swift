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
import UIKit
import Photos

/// TEMPORARY debug switch -- when true, detect() saves the EXACT
/// preprocessed image handed to Vision (after color boost + opening)
/// to your Photos library on every call. This is the single most
/// useful thing to turn on right now: instead of guessing at
/// contrastAdjustment/openingRadius blind and inferring what Vision
/// "must be seeing" from the final contour shape several steps later,
/// you can literally open the photo and look. Turn this back off
/// once the false-wall-detection issue is resolved -- saving a photo
/// on every live frame is wasteful and will flood your camera roll.
let silhouetteDetectorDebugSaveEnabled = false

/// DIAGNOSTIC ONLY -- temporarily loosens the two brand-new,
/// never-validated-together gates (solidity, skin-fraction) so you can
/// get one initial end-to-end "aligned" signal on device and see real
/// lowSolidity/failedSkinTone values via the HUD instead of being
/// stuck at a rejection with no number to react to. NOT a final fix --
/// once you have real on-device numbers from the HUD (and optionally
/// debug photos via silhouetteDetectorDebugSaveEnabled above), turn
/// this back to false and set solidityThreshold/skinFractionThreshold
/// below to values grounded in what you actually observed, the same
/// way solidityThreshold's own comment describes for 0.85 -> 0.7.
let silhouetteDetectorDiagnosticLooseThresholds = false

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

/// Which stage of detect()'s pipeline a given frame was rejected at
/// (or whether it passed all of them). Exists because lastSolidity/
/// lastSkinPassingFraction alone can't distinguish "this frame never
/// reached that check" from "this frame reached it and genuinely
/// failed" -- both read as 0/stale otherwise. Threaded up through
/// CameraManager to the on-screen HUD so a real rejection reason is
/// visible live on-device instead of an ambiguous "skin: 0%, solid: 0%".
enum SilhouetteRejectionStage: Equatable {
    case noContourFound
    case notCentered(candidateCount: Int)
    case onlyFrameSized(count: Int)
    case lowSolidity(value: Double)
    case failedSkinTone(value: Double)
    case passed
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

    // Grid-sampling parameters for the shadow-robustness fix below.
    // 5x5 = 25 independent patches across the sampled region.
    private let skinGridDimension = 5
    // Majority vote, not unanimous -- a shadow across part of a real
    // finger is normal and expected, not a sign it isn't a finger.
    // Computed so silhouetteDetectorDiagnosticLooseThresholds (top of
    // file) can temporarily override it; 0.6 is the real value.
    private var skinFractionThreshold: Double {
        silhouetteDetectorDiagnosticLooseThresholds ? 0.3 : 0.6
    }

    // Exposes the most recent grid-sampling result for on-screen
    // debugging while tuning skinFractionThreshold against real
    // shadow conditions. nonisolated(unsafe): same justification as
    // CameraManager's lastProcessedTime -- detect() only ever runs
    // synchronously on the single frame-processing queue, so there's
    // no concurrent access to guard against.
    private(set) nonisolated(unsafe) var lastSkinPassingFraction: Double = 0

    // NEW: solidity = contour area / convex hull area. A clean single
    // hand/finger blob is reasonably "solid" (fills most of its own
    // convex hull); a contour with a spurious spike or appendage
    // reaching out to an unrelated background artifact (a shadow edge,
    // a lighting gradient on the wall) has LOW solidity, since that
    // spike sticks out into empty space the hull covers but the real
    // shape doesn't fill. Below this threshold, detect() rejects the
    // frame entirely rather than handing AngleAnalyzer a contaminated
    // shape -- see looksLikeCleanSingleShape() below.
    // TODO/VERIFY: lowered from 0.85 back to 0.7 -- 0.85 was
    // calibrated against readings taken BEFORE the frame-border
    // artifact bug was fixed (see preprocessForSeparation's
    // clampedToExtent() fix), so it was tuned against contaminated
    // data. Real debug photos taken AFTER that fix show clean,
    // correctly-detected hand contours consistently sitting well
    // below 85% -- a fist with one finger extended has a genuine
    // anatomical notch between the extended finger and the folded
    // ones, which permanently costs some solidity no matter how
    // clean the detection is. 0.85 was likely rejecting good captures
    // the whole time, not just bad ones. 0.7 is a return to a value
    // grounded in that real notch, not a fresh guess -- if it's still
    // too strict (stuck on "searching" with a visibly clean outline
    // on screen), lower it further; if contaminated shapes start
    // passing again, raise it back up.
    // Computed so silhouetteDetectorDiagnosticLooseThresholds (top of
    // file) can temporarily override it; 0.7 is the real value.
    private var solidityThreshold: Double {
        silhouetteDetectorDiagnosticLooseThresholds ? 0.3 : 0.7
    }
    private(set) nonisolated(unsafe) var lastSolidity: Double = 0

    // Which pipeline stage the most recent detect() call stopped at --
    // see SilhouetteRejectionStage. Same single-queue safety reasoning
    // as lastSolidity above.
    private(set) nonisolated(unsafe) var lastStage: SilhouetteRejectionStage = .noContourFound

    // Throttle for the debug photo save -- same single-queue safety
    // reasoning as CameraManager's lastProcessedTime (detect() only
    // ever runs on one queue at a time).
    private nonisolated(unsafe) var lastDebugSaveTime = Date.distantPast
    private let minDebugSaveInterval: TimeInterval = 1.0

    /// Saves the preprocessed image WITH Vision's actual contours drawn
    /// on top, throttled to roughly once per second. Fire-and-forget --
    /// doesn't block detect(), and silently does nothing if photo
    /// library permission hasn't been granted. Color coding:
    ///   gray   = found by Vision, but filtered out (not centered)
    ///   yellow = centered, i.e. was a real candidate
    ///   green  = the one actually selected and used downstream
    /// This is the direct way to see WHY a given frame produced the
    /// result it did, rather than inferring it from the final contour
    /// shape or debug numbers several steps removed from the source.
    private func saveDebugImageIfDue(
        baseImage: CGImage,
        allContours: [VNContour],
        centeredContours: [VNContour],
        selectedContour: VNContour?,
        toImagePoints: (VNContour) -> [CGPoint]
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastDebugSaveTime) >= minDebugSaveInterval else { return }
        lastDebugSaveTime = now

        let baseUIImage = UIImage(cgImage: baseImage)
        let renderer = UIGraphicsImageRenderer(size: baseUIImage.size)
        let annotated = renderer.image { rendererContext in
            baseUIImage.draw(at: .zero)
            let cgContext = rendererContext.cgContext

            func drawContour(_ contour: VNContour, color: UIColor, lineWidth: CGFloat) {
                let points = toImagePoints(contour)
                guard let first = points.first else { return }
                cgContext.setStrokeColor(color.cgColor)
                cgContext.setLineWidth(lineWidth)
                cgContext.beginPath()
                cgContext.move(to: first)
                for p in points.dropFirst() {
                    cgContext.addLine(to: p)
                }
                cgContext.closePath()
                cgContext.strokePath()
            }

            for contour in allContours {
                drawContour(contour, color: UIColor.gray.withAlphaComponent(0.6), lineWidth: 2)
            }
            for contour in centeredContours {
                drawContour(contour, color: .yellow, lineWidth: 3)
            }
            if let selected = selectedContour {
                drawContour(selected, color: .green, lineWidth: 4)
            }
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: annotated)
        }, completionHandler: nil)
    }

    /// Full pipeline: preprocess for skin/background separation ->
    /// Vision contour detection -> pick the largest contour ->
    /// convert normalized Vision coordinates into image-pixel
    /// coordinates (matching what AngleAnalyzer/GuidanceEngine expect,
    /// same convention as the Python contour arrays).
    ///
    /// - Parameter highQuality: when true, skips the low-resolution
    ///   cap Vision uses during live guidance (see below) so the ONE
    ///   final captured photo gets analyzed at full resolution. This
    ///   was flagged as a TODO in an old comment on maximumImageDimension
    ///   ("use a higher value... for the final high-res capture
    ///   analysis") but never actually implemented -- every call,
    ///   live AND final, was using the same low-res 512 cap the whole
    ///   time. TODO/VERIFY: this closes that real gap, but hasn't been
    ///   confirmed on device yet -- worth checking specifically
    ///   whether the CONFIRMATION SCREEN (which now uses highQuality)
    ///   looks better than the LIVE overlay (which still uses the
    ///   fast low-res path, unchanged) -- if only one of them still
    ///   shows the frame-spanning artifact, that tells us a lot about
    ///   whether Vision's own internal downscaling was contributing to
    ///   it, separate from anything in our own CIImage preprocessing.
    // nonisolated: called synchronously from CameraManager's
    // nonisolated captureOutput() on a background queue -- this
    // method only touches `context` (a let constant) and has no
    // shared mutable state, so it's safe to mark nonisolated.
    nonisolated func detect(in pixelBuffer: CVPixelBuffer, highQuality: Bool = false) -> DetectedSilhouette? {
        // Reset so a frame that never reaches these checks (e.g. no
        // centered contour found at all) reads as 0, not a stale
        // leftover value from a previous frame's debug readout.
        lastSkinPassingFraction = 0
        lastSolidity = 0
        lastStage = .noContourFound

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
        // FLIPPED BACK TO TRUE (Sep 22), with on-device evidence this time:
        // with false, the HUD showed "silhouette + shape OK" at aspect
        // 1.78 -- exactly the 1920x1080 frame's own ratio -- plus
        // moveBack + moveHandDown and solidity 76%: the selected contour
        // was the light WALL (whole frame minus a hand-shaped notch),
        // not the hand, since the hand is darker than the wall. The
        // earlier "true traced the frame border at 100% solidity" result
        // came BEFORE the clampedToExtent() fix in preprocessForSeparation,
        // and a fake dark ring at the image edge is exactly what a
        // dark-on-light search would trace as a 100%-solid frame border.
        // If this regresses, flip back to false and note what the HUD shows.
        request.detectsDarkOnLight = true
        // PREVIOUS NOTE (kept for history): flipping to true (based on the hand-looks-darker-than-wall observation) made things categorically worse on device -- solidity read 100% and the outline traced the OUTER EDGE OF THE CAMERA FRAME instead of the hand. That's consistent with a rectangle: a full-frame border is about as "solid" (convex-hull-filling) as a shape gets, so it sailed through the solidity check even though it's not remotely a hand. Reverting to false rather than continuing to guess at this flag blind -- see the new contour-drawing debug save below, which should show directly which shape Vision is actually finding and why, instead of inferring it indirectly.
        // UPDATED: only cap resolution during live guidance
        // (highQuality == false). The final captured photo -- the one
        // that actually matters for AngleAnalyzer's measurement --
        // now gets analyzed at Vision's default (much higher)
        // resolution instead of being downsampled the same as a live
        // preview frame, closing a real gap flagged in this file long
        // ago but never implemented.
        if !highQuality {
            request.maximumImageDimension = 512  // downscale for speed during LIVE guidance only
        }

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

        // A contour spanning ~the full frame WIDTH is background (a wall
        // region, a lighting gradient, a frame-border artifact), never a
        // properly held hand -- GuidanceEngine already calls anything over
        // 0.85 width "move back". Seen on device with no hand in view: a
        // full-width wall/shadow region passed solidity (98%) and skin
        // (100%) and was only stopped by the aspect-ratio gate. Its center
        // is always "centered", so the ROI filter can't catch it; excluded
        // before selection so a real hand contour can win instead.
        var frameSizedCount = 0
        let centeredContours = observation.topLevelContours.filter { contour in
            let points = toImagePoints(contour)
            guard !points.isEmpty else { return false }
            let box = boundingRect(of: points)
            if box.width >= imageSize.width * 0.95 {
                frameSizedCount += 1
                return false
            }
            let centerX = box.midX
            let centerY = box.midY
            return centerX >= roiMinX && centerX <= roiMaxX
                && centerY >= roiMinY && centerY <= roiMaxY
        }

        if centeredContours.isEmpty && !observation.topLevelContours.isEmpty {
            lastStage = frameSizedCount > 0
                ? .onlyFrameSized(count: frameSizedCount)
                : .notCentered(candidateCount: observation.topLevelContours.count)
        }

        // Among the centered candidates, pick the largest by point
        // count -- matches get_largest_contour()'s use of
        // cv2.contourArea as a size proxy. TODO/VERIFY: consider
        // computing actual polygon area from normalizedPoints instead,
        // if point-count picks the wrong contour in practice.
        let selectedContour = centeredContours.max(by: { $0.pointCount < $1.pointCount })

        // DEBUG: save the preprocessed image with EVERY contour Vision
        // found drawn directly on top -- gray for anything found but
        // not centered, yellow for centered candidates, bright green
        // for whichever one actually got selected. This shows exactly
        // what's winning and why, instead of inferring it indirectly
        // from downstream symptoms (which is how we ended up guessing
        // wrong twice in a row on openingRadius and detectsDarkOnLight).
        // Called BEFORE the guard below so even a total detection
        // failure (no centered contour at all) still gets saved --
        // that's exactly the case most worth seeing.
        if silhouetteDetectorDebugSaveEnabled {
            saveDebugImageIfDue(
                baseImage: cgImage,
                allContours: observation.topLevelContours,
                centeredContours: centeredContours,
                selectedContour: selectedContour,
                toImagePoints: toImagePoints
            )
        }

        guard let largestContour = selectedContour else {
            return nil
        }

        let imagePoints = toImagePoints(largestContour)

        guard !imagePoints.isEmpty else { return nil }

        // NEW: reject contours that aren't a single clean blob BEFORE
        // doing anything else with them. BUG WE SAW ON DEVICE: against
        // a plain wall, a shadow or lighting gradient can get traced
        // as a thin spike/appendage still attached to the real hand
        // shape (morphological opening above helps, but doesn't
        // always fully sever it) -- this showed up as AngleAnalyzer's
        // confirmation markers landing at the literal edges/corners of
        // the photo, nowhere near the actual finger, because the
        // contour itself included points way outside the hand. A
        // solidity check catches this at the SOURCE rather than
        // chasing it downstream with search-distance tuning.
        guard looksLikeCleanSingleShape(imagePoints) else { return nil }

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

        lastStage = .passed
        return DetectedSilhouette(
            boundingBox: boundingBox,
            contourPoints: imagePoints,
            imageSize: imageSize
        )
    }

    /// Samples a GRID of small patches across the detected region and
    /// requires a MAJORITY of them to look skin-toned, rather than
    /// averaging the whole region into one color and testing that.
    ///
    /// BUG WE FOUND ON DEVICE: the original single-average version
    /// failed intermittently on a real, correctly-held finger whenever
    /// a shadow fell across part of it (extremely common -- ambient
    /// room lighting rarely lights a raised finger evenly). Averaging
    /// blends the shadowed pixels into the same value as the lit
    /// pixels, and that blended color can fall outside the skin-tone
    /// heuristic even though most of the surface is genuinely skin.
    /// Grid-sampling with a majority vote fixes this: a shadowed
    /// patch just fails ITS OWN check without dragging down every
    /// other patch's reading.
    private func looksSkinToned(pixelBuffer: CVPixelBuffer, in boundingBox: CGRect, imageSize: CGSize) -> Bool {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Same inset as before -- avoid sampling right at the
        // silhouette's edge, where background pixels can bleed in.
        let sampleRect = boundingBox.insetBy(
            dx: boundingBox.width * 0.3,
            dy: boundingBox.height * 0.3
        )
        guard sampleRect.width > 0, sampleRect.height > 0 else { return false }

        // Flip to CIImage's bottom-left origin, same as before.
        let ciSampleRect = CGRect(
            x: sampleRect.minX,
            y: imageSize.height - sampleRect.maxY,
            width: sampleRect.width,
            height: sampleRect.height
        )

        let patchWidth = ciSampleRect.width / CGFloat(skinGridDimension)
        let patchHeight = ciSampleRect.height / CGFloat(skinGridDimension)
        guard patchWidth > 0, patchHeight > 0 else { return false }

        var totalPatches = 0
        var passingPatches = 0

        for row in 0..<skinGridDimension {
            for col in 0..<skinGridDimension {
                let patchRect = CGRect(
                    x: ciSampleRect.minX + CGFloat(col) * patchWidth,
                    y: ciSampleRect.minY + CGFloat(row) * patchHeight,
                    width: patchWidth,
                    height: patchHeight
                )

                guard let (r, g, b) = averageColor(of: ciImage, in: patchRect) else { continue }

                totalPatches += 1
                if isSkinToned(r: r, g: g, b: b) {
                    passingPatches += 1
                }
            }
        }

        guard totalPatches > 0 else { return false }
        let passingFraction = Double(passingPatches) / Double(totalPatches)
        lastSkinPassingFraction = passingFraction
        let passed = passingFraction >= skinFractionThreshold
        if !passed {
            lastStage = .failedSkinTone(value: passingFraction)
        }
        return passed
    }

    /// Averages a single small region down to one RGB value. Pulled
    /// out as its own helper so looksSkinToned can call it once per
    /// grid patch instead of once for the whole region.
    private func averageColor(of image: CIImage, in rect: CGRect) -> (r: Double, g: Double, b: Double)? {
        let extentVector = CIVector(x: rect.origin.x, y: rect.origin.y, z: rect.width, w: rect.height)
        guard let averageFilter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: extentVector
        ]) else { return nil }
        guard let outputImage = averageFilter.outputImage else { return nil }

        var pixelData = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage, toBitmap: &pixelData, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )

        return (
            r: Double(pixelData[0]) / 255.0,
            g: Double(pixelData[1]) / 255.0,
            b: Double(pixelData[2]) / 255.0
        )
    }

    /// Same broad, permissive skin-tone heuristic as before -- pulled
    /// out as its own function so it can be applied per-patch instead
    /// of once for a single blended average. Needs to work across a
    /// wide range of real skin tones, not just one: red channel
    /// should dominate or be close to green, and not be too
    /// desaturated (rules out grays/whites like a wall or table) or
    /// too saturated toward blue/green (rules out most fabrics,
    /// plastics, wood tones outside a skin-like range).
    private func isSkinToned(r: Double, g: Double, b: Double) -> Bool {
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

        guard let colorBoosted = saturationFilter.outputImage else { return nil }

        // NEW: morphological opening (erode then dilate) to sever thin
        // "bridges" between separate objects before Vision traces
        // contours. BUG WE FOUND ON DEVICE: a shadow the finger casts
        // on the wall behind it can blend into the SAME connected
        // region as the finger after the contrast/saturation boost
        // above, and Vision then traces the two as one large merged
        // contour instead of two separate ones -- this showed up as a
        // huge, oddly-shaped bounding box (pulled toward the shadow,
        // extending near the top of frame) that threw off
        // widthFraction and the moveHandDown check, even though the
        // finger itself was correctly positioned. A thin neck
        // connecting two otherwise-separate blobs is exactly what
        // erosion removes; following it with an equal-radius dilation
        // restores the surviving blob(s) back to roughly their
        // original size/shape.
        //
        // TODO/VERIFY: reverted from 11 back to 5 -- 11 was pushed up
        // too far across two guesses in a row without a working
        // baseline to check against, and real device testing showed
        // it eroding the ACTUAL FINGER away, not just the artifact --
        // with the finger's own contour damaged/shrunk, a low-contrast
        // wall gradient was winning "largest centered contour" by
        // default (matches the report: detection preferring the wall
        // over the real finger, at any distance). 4 was the last
        // CONFIRMED-working value (fixed the original shadow-bridging
        // bug earlier); 5 is a small step up from that known-good
        // point, not another large blind jump. If artifacts still
        // survive at 5, the next lever to try is reducing the
        // preprocessing contrast/saturation boost below (the actual
        // root cause of a plain wall becoming "edge-worthy" in the
        // first place), not pushing this radius higher again.
        // NEW: clampedToExtent() before the morphology filters, cropped
        // back to the original extent after. BUG WE FOUND FROM REAL
        // DEBUG PHOTOS: without this, Core Image has nothing real to
        // sample beyond the image's actual edge when computing the
        // erosion/dilation neighborhood near the border, and treats
        // "outside the image" as black/transparent by default -- this
        // creates a faint but genuine dark ring right at the image
        // boundary once the kernel gets close to it. Vision then
        // traces THAT ring as a real edge, and it bridges to the
        // actual hand contour the exact same way the original
        // shadow-bridging bug worked, just against an artifact from
        // our own preprocessing instead of a real environmental
        // shadow. This one explains a lot of what looked like
        // separate bugs (false wall detection, outline on the frame
        // edge, inconsistent solidity readings) -- they were likely
        // all the same underlying border artifact, just caught or
        // missed by the solidity gate depending on the exact frame.
        // clampedToExtent() extends the edge pixels outward instead of
        // treating them as black, so there's no artificial boundary
        // for the morphology filters to create in the first place.
        let extendedForMorphology = colorBoosted.clampedToExtent()

        let openingRadius: Float = 5

        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = extendedForMorphology
        erode.radius = openingRadius
        guard let eroded = erode.outputImage else { return colorBoosted }

        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = eroded
        dilate.radius = openingRadius
        guard let opened = dilate.outputImage else { return eroded.cropped(to: image.extent) }

        // Crop back to the original frame -- clampedToExtent() made
        // the image conceptually infinite, so this undoes that before
        // handing anything off to Vision.
        return opened.cropped(to: image.extent)
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

    /// True if the contour looks like a single coherent blob rather
    /// than a real shape contaminated with a spurious spike/appendage
    /// (see the guard at its call site for the actual bug this
    /// catches). Computes solidity = contour area / convex hull area
    /// -- NOT applied to the contour itself (that would flatten real
    /// concave detail, like the cuticle notch AngleAnalyzer needs to
    /// find), only used here as a pass/fail number to decide whether
    /// to trust this frame at all.
    private func looksLikeCleanSingleShape(_ points: [CGPoint]) -> Bool {
        guard points.count > 3 else { return false }
        let hull = convexHull(points)
        guard hull.count >= 3 else { return false }

        let shapeArea = polygonArea(points)
        let hullArea = polygonArea(hull)
        guard hullArea > 0 else { return false }

        let solidity = shapeArea / hullArea
        lastSolidity = solidity
        let passed = solidity >= solidityThreshold
        if !passed {
            lastStage = .lowSolidity(value: solidity)
        }
        return passed
    }

    /// Shoelace formula -- standard polygon area from an ordered list
    /// of vertices. Used both for the raw contour and its convex hull,
    /// so their ratio (solidity) is comparable.
    private func polygonArea(_ points: [CGPoint]) -> Double {
        guard points.count > 2 else { return 0 }
        var area: Double = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            area += Double(points[i].x * points[j].y - points[j].x * points[i].y)
        }
        return abs(area) / 2.0
    }

    /// Convex hull via the monotone chain algorithm (Andrew's
    /// algorithm). Used ONLY to compute solidity above -- never to
    /// replace the actual contour, since that would erase real
    /// concave features (like the cuticle notch) that AngleAnalyzer
    /// specifically needs to find. TODO/VERIFY: untested on device,
    /// same caveat as the rest of this file -- if solidity readings
    /// look nonsensical (e.g. consistently near 0 or above 1) on
    /// screen, this is the first place to check.
    private func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 3 else { return points }
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }

        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }

        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}

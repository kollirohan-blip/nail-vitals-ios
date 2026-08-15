//
//  SilhouetteDetector.swift
//  NailVitals
//
//  Swift port of isolate_silhouette() + get_largest_contour() from
//  contour_angle.py. Uses Vision framework instead of MediaPipe --
//  MediaPipe hand landmarks failed to detect anything on close-up
//  finger crops during Python prototype testing, so this avoids that
//  dependency entirely for the live capture-guide loop.
//
//  STATUS: stub -- ported logic goes here once we're on the Mac with
//  Xcode to actually compile/test against Vision's contour APIs.
//

import Vision
import CoreImage

struct DetectedSilhouette {
    let boundingBox: CGRect      // in image coordinates
    let contourPoints: [CGPoint] // ordered contour points
    let imageSize: CGSize
}

final class SilhouetteDetector {

    /// Combines grayscale + HSV-saturation thresholding (matches the
    /// Python isolate_silhouette() approach) to separate the finger
    /// from a plain background, then finds the largest contour.
    ///
    /// TODO (on Mac): implement using VNDetectContoursRequest with a
    /// CIColorControls-preprocessed image (grayscale) OR a manual
    /// Core Image threshold filter, mirroring the Otsu-equivalent
    /// logic from the Python version. Combine with a second pass on
    /// the saturation channel the same way isolate_silhouette() does.
    func detect(in pixelBuffer: CVPixelBuffer) -> DetectedSilhouette? {
        fatalError("Not yet implemented -- port from contour_angle.py isolate_silhouette()")
    }
}

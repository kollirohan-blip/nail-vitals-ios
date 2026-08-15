//
//  AngleAnalyzer.swift
//  NailVitals
//
//  Swift port of the core geometry in contour_angle.py: fingertip
//  detection, curvature-based inflection point search, line fitting,
//  Lovibond angle calculation. Runs ONCE on the final high-res
//  captured photo -- not live, unlike SilhouetteDetector/GuidanceEngine.
//
//  IMPORTANT -- two real bugs we found and fixed in the Python
//  version, do not reintroduce them here:
//
//  1. Search range / window must scale with the contour's perimeter,
//     NOT be a fixed pixel count. A fixed count worked on one test
//     photo's resolution and completely failed to reach the real
//     cuticle on higher-resolution photos. Use something like:
//       window = max(4, Int(perimeter * 0.006))
//       searchRange = max(40, Int(perimeter * 0.12))
//       segmentLen = max(20, Int(perimeter * 0.05))
//
//  2. When fitting a line to a segment of contour points, the
//     direction vector's sign is ambiguous (can point either way
//     along the line). We found this silently flipped angle results
//     on some photos. Always explicitly orient the fitted direction
//     to match the segment's actual point-to-point traversal
//     direction (first point -> last point) before comparing two
//     segments' angles.
//
//  STATUS: stub -- port once SilhouetteDetector is working, since
//  this consumes the same contour data.
//

import CoreGraphics

struct AngleMeasurement {
    let angleDegrees: Double
    let inflectionPoint: CGPoint
    let confidence: Double  // TODO: define based on curvature sharpness,
                             // see quality_check.py's curvature-based
                             // exploration -- didn't cleanly separate
                             // good/bad on its own, but may still be
                             // useful as a secondary confidence signal
                             // alongside the guided-capture flow.
}

final class AngleAnalyzer {

    /// Full pipeline: fingertip -> inflection point search (both
    /// sides) -> line fitting -> angle calculation. Mirrors
    /// measure_lovibond_angle() in contour_angle.py.
    func analyze(_ silhouette: DetectedSilhouette) -> AngleMeasurement? {
        fatalError("Not yet implemented -- port from contour_angle.py measure_lovibond_angle()")
    }
}

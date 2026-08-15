# Nail Vitals — iOS App

Swift/SwiftUI implementation, built on top of the validated Python
prototype in `../nail-vitals-cv-prototype/`.

## Status: skeleton only

Every file in here is a **stub** with the real logic described in
comments, pointing back to the exact Python function it should be
ported from. Nothing compiles/runs yet — this needs Xcode on a Mac to
actually build and test.

## Structure

```
NailVitals/
  Detection/
    SilhouetteDetector.swift   -- Vision framework port of isolate_silhouette()
    AngleAnalyzer.swift        -- port of measure_lovibond_angle()
  Guidance/
    GuidanceEngine.swift       -- direct port of guidance_logic.py (already calibrated)
  Views/
    CaptureGuideOverlay.swift  -- SwiftUI, matches guided_capture_demo.html
    ResultView.swift           -- shows the measured angle + disclaimer
```

## Why Vision framework, not MediaPipe

We tested MediaPipe hand landmarks against real close-up finger
photos (`alignment_check.py` in the Python prototype) and it failed
to detect a hand on every single one — it needs a full hand in frame,
which conflicts with the tight crop this app needs. Vision framework
contour detection, mirroring the plain thresholding approach that
DID work in Python, avoids that problem and needs no extra SDK.

## Next steps (in order)

1. Open in Xcode on the Mac, create a real `.xcodeproj` around these
   files (or start fresh and drag them in)
2. Get `AVCaptureSession` showing a live preview with
   `CaptureGuideOverlay` rendering on top (static state first, not
   yet wired to detection)
3. Implement `SilhouetteDetector` for real using Vision framework
4. Wire `GuidanceEngine` to real detection output
5. Implement `AngleAnalyzer` for the actual capture/measurement step
   -- remember the two bugs documented in its file header, don't
   reintroduce them
6. `ResultView` + save-to-history

## Reference data from Python validation

Six repeated trials on the same healthy control finger produced
angles ranging 130.7°–161.1° (see `guidance_logic.py` and the
project's chat history for the full breakdown). That's the expected
real-world precision floor for a single photo under normal
conditions — useful context for confidence/reference-range UI later.

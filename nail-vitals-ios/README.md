# Nail Vitals: iOS app and tools

An iPhone app that screens for nail signs from phone photos, starting with finger clubbing. It is a screening aid, not a diagnosis. HOSA Medical Innovation entry by Rohan Kolli and Rohan Das.

## Where things are

| Path | What |
|---|---|
| `NailVitals/NailVitals/NailVitals.xcodeproj` | The Xcode project |
| `NailVitals/NailVitals/NailVitals/` | App source. New files in this folder join the build automatically. |
| `…/Detection/` | Hand pose, finger outline, the three clubbing signs, the verdict, photo checks |
| `…/Signs/` | The v2 sign model: one result per nail sign, four states |
| `…/Session/` | History (numbers only, never photos) and the FHIR export |
| `…/Guidance/`, `…/CameraManager/` | Live framing rules, voice, haptics, camera |
| `…/Views/` | Screens |
| `Tools/photo-lab/` | Runs the app's real measuring code on photos, on the Mac |
| `Tools/photo-study/` | Measures photos from any camera (`run.py`, `PHOTO-GUIDE.md`) |
| `Tools/validation/` | Study protocol, rater kit |
| `Tools/test.sh` | Builds and runs every test harness |
| `../docs/superpowers/` | v2 design spec and build plans |

## Build

This Mac is Intel and `xcode-select` points at the Command Line Tools, so name the working Xcode:

```bash
export DEVELOPER_DIR="/Users/sowjanyakolli/Downloads/rohan-hosa-project1/Xcode 2.app/Contents/Developer"
cd NailVitals/NailVitals
xcodebuild -project NailVitals.xcodeproj -scheme NailVitals -destination 'generic/platform=iOS Simulator' build
```

## Test

```bash
Tools/test.sh
```

Run it after any change to `AngleAnalyzer`, `FingerSigns`, `ClubbingAssessment` or `Signs/`.

## Rules

- Never commit photos. `captures/` and `testset/` are ignored.
- Photos never leave the phone or the Mac. Only numbers are stored in the app's history.
- A sign shows in the app only after it passes its written accuracy test (`Signs/SignAvailability.swift`).
- Work on the `v2` branch. Ask before merging to `main`.

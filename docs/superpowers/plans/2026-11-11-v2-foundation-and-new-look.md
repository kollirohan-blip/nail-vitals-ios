# Nail Vitals v2, Plan 1: Foundation and New Look Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give today's app (clubbing scan, history, FHIR, Ask, two beta tests) the v2 structure and look: a sign-agnostic result model, the final palette, and the Home / report card / sign detail / History screens.

**Architecture:** A new pure-logic layer (`Signs/`) turns a saved session into a list of `SignResult`s, one per nail sign, each in one of four states. Every v2 screen renders that list, so later plans add a sign by adding an analyzer and switching its flag on, with no screen changes. Clubbing is recomputed from stored readings as today; results that can't be recomputed (later signs) are stored beside them.

**Tech Stack:** Swift 5 / SwiftUI, iOS 26.5, Swift Charts. No test target: pure logic is tested with `swiftc` harness tools in `nail-vitals-ios/Tools/`, screens on the iOS simulator.

**Spec:** `docs/superpowers/specs/2026-11-11-nail-vitals-v2-design.md` (phases 0 and 2) and `…-v2-signs-and-accuracy-tests.md`. This plan covers spec phases 0 and 2. Plan 2 (next) covers phase 1 (on-phone feasibility probes) and phase 3 (check-up camera).

**Paths:** repo root `~/Documents/nail-vitals-ios`. `APP/` below means `nail-vitals-ios/NailVitals/NailVitals/NailVitals/`. `TOOLS/` means `nail-vitals-ios/Tools/`. The Xcode project uses file-system-synchronized groups: a new file under `APP/` is in the build automatically.

## Global Constraints

- Branch `v2` (off `pivot/hand-pose`). Never merge to `main` without asking.
- Never commit photos (`captures/`, `testset/` stay ignored). History stores numbers only, never photos.
- Build: `DEVELOPER_DIR="/Users/sowjanyakolli/Downloads/rohan-hosa-project1/Xcode 2.app/Contents/Developer"` on every `xcodebuild` / `xcrun`.
- App target defaults to `MainActor` isolation: pure-logic types are declared `nonisolated` so the same files compile in the harnesses.
- Palette (exact hex, spec section 6 / vault "Colour palette"):
  - typical `#087A4B` / dark `#00E676`
  - measure again `#945500` / dark `#FFB300`
  - worth discussing `#BF3030` / dark `#FF6B6B`
  - couldn't check `#636366` / dark `#AEAEB2`
  - background `#F2F2F7` / `#000000`; cards `#FFFFFF` / `#1C1C1E`
  - main button charcoal `#1C1C1E` / white in dark. No cyan outside the camera. No violet glow.
- Camera colours unchanged (`#00E5FF`, `#FFB300`, `#00E676`).
- A result state is always shown as colour + icon + word. Icons: `checkmark.circle`, `arrow.clockwise.circle`, `exclamationmark.triangle`, `minus.circle`.
- "Couldn't check" never counts as a problem in the overall banner.
- A sign that is not switched on in `SignAvailability` is not shown anywhere.
- Every result screen shows the safety line; it must contain "A screening aid, not a diagnosis."
- New screens use text styles (`.body`, `.headline`, …), not fixed sizes, so Dynamic Type works. Touch targets ≥ 44 pt.
- No invented numbers: accuracy lines come only from `validation.json`, whose values come from the vault note "Evidence so far".
- Rerun `TOOLS/test.sh` after any change to `AngleAnalyzer`, `FingerSigns`, `ClubbingAssessment` or `Signs/`.

## Review Focus

1. **A History.json saved by the old app** (no `extraSigns`, some readings without `quality`) must load with every session intact. → Task 3 test `oldHistoryLoads`.
2. **A stored sign this build doesn't know** (history written by a newer build) must not empty the history: unknown entries are dropped, the session stays. → Task 3 test `unknownSignIsDropped`.
3. **A session where nothing could be measured** shows "Couldn't check", never "Nothing stood out". → Task 2 test `nothingMeasuredIsNotTypical`.
4. **A no-dip session** (profile counted as ≥ 180°) shows "≥180°", not a number. → Task 2 test `noDipShowsAtLeast180`.
5. **The largest text size** must wrap, not clip or overlap, on Home and the report card. → Task 8 screenshot check.

---

### Task 1: Cleanup and one test command

**Files:**
- Delete: `nail-vitals-ios/NailVitals/CameraManager/`, `nail-vitals-ios/NailVitals/Detection/`, `nail-vitals-ios/NailVitals/Guidance/`, `nail-vitals-ios/NailVitals/Views/` (the August skeleton; not in the Xcode project)
- Rewrite: `nail-vitals-ios/README.md`, `README.md`
- Create: `TOOLS/test.sh`
- Modify: `.gitignore` (add `__pycache__/`, `TOOLS/signs-harness/signs-harness`), `TOOLS/angle-harness/main.swift:1-2` (build comment)

**Interfaces:**
- Produces: `TOOLS/test.sh`: builds and runs every harness; exit code 0 only if all pass. Later tasks add their harness to it.

- [ ] **Step 1:** Confirm nothing references the stale folders: `grep -c "NailVitals/Detection/AngleAnalyzer.swift" nail-vitals-ios/NailVitals/NailVitals/NailVitals.xcodeproj/project.pbxproj` prints 0. Then `git rm -r` the four folders.
- [ ] **Step 2:** Write `TOOLS/test.sh`. It compiles angle-harness with the file set that builds today: `Detection/{DetectedSilhouette,AngleAnalyzer,FingerSigns,ClubbingAssessment,HumanLabel,ReadingQuality,FingerIdentity,EdgeSharpness,BackgroundContrast,HandPoseDetector}.swift` (add or drop files until it compiles; record the working set in the script and in `main.swift`'s header comment), runs it, and fails if its output lacks the line it prints on success.
- [ ] **Step 3:** Run `TOOLS/test.sh`. Expected: angle-harness builds and its summary matches the committed binary's (same worst-error lines).
- [ ] **Step 4:** Rewrite both READMEs: what the app is, where the app source and tools are, how to build (the `DEVELOPER_DIR` line), `TOOLS/test.sh`, the privacy rules, pointer to `docs/superpowers/`.
- [ ] **Step 5:** `xcodebuild … -destination 'generic/platform=iOS Simulator' build` succeeds (baseline). Commit: "Remove the August skeleton, fix the READMEs, one test command".

### Task 2: The sign model (`Signs/`)

**Files:**
- Create: `APP/Signs/SignResult.swift`, `APP/Signs/SignAvailability.swift`, `APP/Signs/CheckupReport.swift`
- Test: `TOOLS/signs-harness/main.swift` (added to `TOOLS/test.sh`)

**Interfaces:**
- Consumes: `FingerSigns`, `ClubbingAssessment`, `SignKind` (existing, `APP/Detection/`).
- Produces:

```swift
nonisolated enum SignGroup: String, CaseIterable { case shape, colour, circulation, extra
    var title: String }                    // "Shape", "Colour", "Circulation", "Extra"

nonisolated enum NailSign: String, Codable, CaseIterable {
    case clubbing, spoonNails, pallor, cyanosis, tipBands, refill, schamroth
    var title: String      // "Clubbing", "Spoon nails", "Pallor", "Cyanosis", "Terry's / half-and-half", "Refill time", "Schamroth window"
    var group: SignGroup   // shape: clubbing, spoonNails · colour: pallor, cyanosis, tipBands · circulation: refill · extra: schamroth
}

nonisolated enum SignState: String, Codable {
    case typical, measureAgain, worthDiscussing, couldntCheck
    var severity: Int      // couldntCheck 0, typical 1, measureAgain 2, worthDiscussing 3
    var label: String      // "Typical", "Measure again", "Worth discussing", "Couldn't check"
    var symbol: String     // the four SF Symbols in Global Constraints
    init(_ verdict: ClubbingAssessment.Verdict)
    init(_ status: SignStatus)             // typical / nearThreshold→measureAgain / above→worthDiscussing
}

nonisolated struct SignResult: Codable, Equatable, Identifiable {
    var sign: NailSign
    var state: SignState
    var value: Double?         // headline number, nil when there is none
    var valueText: String?     // as shown: "166.9°", "≥180°", "1.4 s"
    var reason: String?        // why it couldn't be checked (state == .couldntCheck)
    var analyzerVersion: Int
    var id: String { sign.rawValue }
}

nonisolated enum SignAvailability {
    static let enabled: Set<NailSign> = [.clubbing]   // a sign is added here only after its accuracy test passes
}

nonisolated struct CheckupReport {
    let results: [SignResult]                 // enabled signs only, in NailSign.allCases order
    let assessment: ClubbingAssessment
    let noDip: Bool                           // most readings found no cuticle dip
    var overall: SignState                    // highest severity among results not .couldntCheck; .couldntCheck if none
    var measuredCount: Int                    // results whose state != .couldntCheck
    var headline: String                      // "Nothing stood out today" / "Measure again" / "Worth discussing with a doctor" / "Couldn't check this time"
    var nextStep: String                      // one or two plain sentences per overall state
    func results(in group: SignGroup) -> [SignResult]
    init(readings: [FingerSigns], extra: [SignResult] = [], enabled: Set<NailSign> = SignAvailability.enabled)
}
```

Rules the tests pin:
- Clubbing result: `state = SignState(assessment.verdict)`; `value` = the profile angle; `valueText` = `"≥180°"` when `noDip`, else `SignKind.lovibond.formatted(value)`.
- Clubbing with no plausible value for any of the three signs: `state = .couldntCheck`, `reason = "The app couldn't measure your finger in these photos."`.
- `extra` results for signs not in `enabled` are left out. An enabled sign with no stored result is left out too (old sessions show clubbing only).

- [ ] **Step 1: Write the failing tests** in `TOOLS/signs-harness/main.swift` as a list of named checks (`check("name") { … }`, non-zero exit if any fails):

```swift
// helper: reading(166, 179, 0.84) -> FingerSigns
check("typicalSession") {
    let r = CheckupReport(readings: [reading(166,179,0.84), reading(167,178,0.83), reading(166.5,180,0.85)])
    return r.results.count == 1 && r.results[0].sign == .clubbing && r.results[0].state == .typical
        && r.results[0].valueText == "166.5°" && r.overall == .typical && r.headline == "Nothing stood out today"
}
check("twoSignsAboveIsWorthDiscussing") {
    let r = CheckupReport(readings: [reading(185,196,0.9), reading(186,197,0.9), reading(184,195,0.9)])
    return r.results[0].state == .worthDiscussing && r.overall == .worthDiscussing
}
check("nothingMeasuredIsNotTypical") {
    let r = CheckupReport(readings: [FingerSigns()])
    return r.results[0].state == .couldntCheck && r.overall == .couldntCheck && r.measuredCount == 0
        && r.headline == "Couldn't check this time"
}
check("noDipShowsAtLeast180") {
    var a = reading(180,196,1.05); a.noCuticleDip = true
    return CheckupReport(readings: [a, a, a]).results[0].valueText == "≥180°"
}
check("couldntCheckNeverRaisesTheBanner") {
    let extra = [SignResult(sign: .refill, state: .couldntCheck, value: nil, valueText: nil, reason: "Hand moved", analyzerVersion: 1)]
    let r = CheckupReport(readings: [reading(166,179,0.84)], extra: extra, enabled: [.clubbing, .refill])
    return r.results.count == 2 && r.overall == .typical && r.measuredCount == 1
}
check("disabledSignsAreHidden") {
    let extra = [SignResult(sign: .pallor, state: .worthDiscussing, value: 1, valueText: "1", reason: nil, analyzerVersion: 1)]
    let r = CheckupReport(readings: [reading(166,179,0.84)], extra: extra)   // default: clubbing only
    return r.results.map(\.sign) == [.clubbing] && r.overall == .typical
}
check("mostSeriousMeasuredStateWins") {
    let extra = [SignResult(sign: .refill, state: .measureAgain, value: 2.4, valueText: "2.4 s", reason: nil, analyzerVersion: 1)]
    return CheckupReport(readings: [reading(166,179,0.84)], extra: extra, enabled: [.clubbing, .refill]).overall == .measureAgain
}
check("groups") { NailSign.refill.group == .circulation && NailSign.tipBands.group == .colour && NailSign.spoonNails.group == .shape }
```

- [ ] **Step 2:** Add the harness to `TOOLS/test.sh` (compile `APP/Signs/*.swift` plus the Detection files angle-harness needs). Run: fails to compile ("cannot find 'CheckupReport'").
- [ ] **Step 3:** Implement the three files to the interface above.
- [ ] **Step 4:** Run `TOOLS/test.sh`: all checks pass, angle-harness still passes.
- [ ] **Step 5:** Commit: "Sign model: one result per nail sign, four states, availability flags".

### Task 3: History keeps the extra sign results

**Files:**
- Modify: `APP/Session/ScanHistory.swift`
- Test: `TOOLS/signs-harness/main.swift`

**Interfaces:**
- Consumes: `SignResult` (Task 2).
- Produces: `ScanSession.extraSigns: [SignResult]?` (nil in sessions saved before v2); `ScanSession.report: CheckupReport`; `ScanHistory.add(readings:hand:extra:)` with `extra: [SignResult] = []`; `ScanHistory.decode(_ data: Data) -> [ScanSession]` (static, used by `init` and the tests).
- The type keeps the name `ScanSession` (the spec calls it `CheckupSession`): History.json stays compatible and the diff stays small.

- [ ] **Step 1: Failing tests** (harness now also compiles `Session/ScanHistory.swift` and `Guidance/MeasuredHand.swift`):

```swift
let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":"2026-10-02T18:00:00Z","hand":"right","readings":[{"lovibond":166.4,"hyponychial":179.1,"depthRatio":0.84,"noCuticleDip":false}]}]"#
check("oldHistoryLoads") {
    let s = ScanHistory.decode(Data(old.utf8))
    return s.count == 1 && s[0].extraSigns == nil && s[0].report.results.map(\.sign) == [.clubbing]
}
check("unknownSignIsDropped") {   // a result written by a newer build
    let newer = old.replacingOccurrences(of: #""hand":"right","#, with: #""hand":"right","extraSigns":[{"sign":"futureSign","state":"typical","analyzerVersion":1},{"sign":"refill","state":"typical","value":1.4,"valueText":"1.4 s","analyzerVersion":1}],"#)
    let s = ScanHistory.decode(Data(newer.utf8))
    return s.count == 1 && s[0].extraSigns?.map(\.sign) == [.refill]
}
check("roundTrip") { /* encode a session with one extra sign, decode, equal */ }
```

- [ ] **Step 2:** Run: fails (no `decode`, no `extraSigns`).
- [ ] **Step 3:** Implement. `extraSigns` decodes lossily: each array element is decoded on its own and dropped if it fails (a small `LossyArray` wrapper inside `ScanSession.init(from:)`). `ScanSession.report` = `CheckupReport(readings: signs, extra: extraSigns ?? [])`.
- [ ] **Step 4:** `TOOLS/test.sh` passes. App builds.
- [ ] **Step 5:** Commit: "History: keep extra sign results; old and newer files load safely".

### Task 4: Palette and state components

**Files:**
- Modify: `APP/Views/Theme.swift`, `APP/Views/Styles.swift`
- Create: `APP/Views/StatePill.swift`

**Interfaces:**
- Produces:
  - `Theme.adjusting` classic → `0x945500`; `Theme.attention` classic → `0xBF3030`; new `Theme.unmeasured` (dark `0xAEAEB2`, classic `0x636366`); `Theme.secondaryText` (same two values); `Theme.action` → dark `0xFFFFFF`, classic `0x1C1C1E`; `Theme.violet` removed.
  - `extension SignState { var color: Color }`.
  - `StatePill(state: SignState, text: String? = nil)`: icon + word in the state colour on a tint of it (12% in light, 18% in dark); one accessibility element.
  - `StateBanner(state: SignState, title: String, detail: String)`: the report card's banner, same tint rule.
  - `AppBackground`: `#F2F2F7` light, `#000000` dark, no gradients.
  - Cards (`glassCard`, `glassPanel`) in dark: solid `#1C1C1E` (no glass). Light unchanged.
  - `SafetyNote` text: "A screening aid, not a diagnosis. This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition."
  - `ResultView.color(for:)` (both overloads) now return `SignState(…).color`, so every existing screen picks up the palette.

- [ ] **Step 1:** Make the changes. `Theme.action`'s uses on the dark camera-side screens (`CaptureFlowView`, `NailCheckView`, `SchamrothView`) become white-on-dark buttons: check each still reads (GlowButtonStyle already puts black text on bright fills in dark).
- [ ] **Step 2:** Build. Commit: "Final palette: flat backgrounds, four result states with icons".

### Task 5: Accuracy lines (`validation.json`)

**Files:**
- Create: `APP/Signs/validation.json`, `APP/Signs/ValidationData.swift`
- Test: `TOOLS/signs-harness/main.swift`

**Interfaces:**
- Produces: `nonisolated struct ValidationLine: Codable { let label: String; let value: String }`; `nonisolated struct SignValidation: Codable { let sign: NailSign; let updated: String; let lines: [ValidationLine]; let note: String? }`; `enum ValidationData { static func parse(_ data: Data) -> [NailSign: SignValidation]; static let bundled: [NailSign: SignValidation] }` (reads `validation.json` from the main bundle; empty if missing).
- `validation.json` content for clubbing, exactly (from "Evidence so far"):
  - "Healthy photos measured" → "81, none flagged"
  - "Scan sessions" → "23 over 8 days"
  - "A scan vs your own average" → "usually within ±3.4°"
  - "Designed healthy and clubbed shapes" → "read Typical and Flagged"
  - note: "Computer renders of the two designs; real clubbed fingers haven't been tested yet." updated "2026-10-16".

- [ ] **Step 1:** Test `validationParses`: the harness reads `APP/Signs/validation.json` from disk, `parse` returns a clubbing entry with 4 lines; a second check feeds `{"broken"` and expects an empty dictionary.
- [ ] **Step 2:** Fails → implement → passes. Commit: "Accuracy lines from validation.json".

### Task 6: Report card and sign detail

**Files:**
- Create: `APP/Views/ReportCardView.swift`, `APP/Views/SignDetailView.swift`
- Modify: `APP/Views/ResultsListView.swift` (`SessionDetailView` body becomes the report card; `SessionRow` uses `StatePill`), `APP/Views/CaptureFlowView.swift:137-157` (the `.result` stage shows the report card), `APP/Views/ResultView.swift` (remove `struct ResultView`'s body and state; keep `ResultGauge`, `SignChip`, `CountingAngle`, and the static helpers in an `enum ResultView`)

**Interfaces:**
- Consumes: `CheckupReport`, `StatePill`, `StateBanner`, `ValidationData`, existing `NormsPanel`, `QualityPanel`, `ResultGauge`, `SignChip`, `FHIRExport`, `AskAssistantView`.
- Produces:
  - `ReportCardView(readings: [FingerSigns], extra: [SignResult] = [], hand: MeasuredHand, date: Date, animated: Bool = false, onOpen: (NailSign) -> Void)`: banner; per group a header and one row per result (title, value text, pill, chevron; under Clubbing its three `SignChip`s); "What to do next" card (`report.nextStep`); the safety line. `animated`: banner, then rows fade in 0.15 s apart (skipped with Reduce Motion). Rows are buttons calling `onOpen`.
  - `SignDetailView(sign: NailSign, readings: [FingerSigns], extra: [SignResult], recent: [ScanSession])`. For clubbing, in this order: gauge + headline value + pill; "What it means" (`ResultView.verdictDetail`); the three chips; "Why the app thinks so" (readings table, moved from `SessionDetailView`, and `QualityPanel`); "How accurate is this?" (`ValidationData.bundled[.clubbing]` lines and note); "Your recent results" (up to 5 earlier sessions' profile values with dates); "Compared with healthy fingers" (`NormsPanel`); a link to the science page (`AboutMeasurementsContent`).
  - `SessionDetailView`: report card, then "Ask about this result", "Send to doctor" (FHIR share, as today), "Delete this result". Rows push `SignDetailView`.
  - Post-scan `.result` stage: `ReportCardView(animated: true)` inside the existing scroll view with "Scan again" / "Done"; a row opens `SignDetailView` as a sheet.

- [ ] **Step 1:** Build the two views and rewire the three call sites.
- [ ] **Step 2:** Build. Run on the simulator with a seeded `Documents/History.json` (3 sessions: typical, measure again, worth discussing). Open each from the list: banner colour, pill, icon and wording match the state; clubbing detail shows every section. Commit: "Report card and sign detail".

### Task 7: Home, four tabs, History, Learn

**Files:**
- Create: `APP/Views/HomeView.swift`, `APP/Views/HistoryView.swift`
- Modify: `APP/Views/HomeTabs.swift` (tabs become Home · History · Learn · Ask; `HomeTab` removed; `BrandMark` stays), `APP/Views/LearnView.swift` (rows: How to scan · Clubbing · Nail colour bands (beta) · Schamroth window (beta)), `APP/Views/ResultsListView.swift` (`ResultsListView` removed; rows and detail stay), `APP/Views/TrendsView.swift` (`TrendsView` removed; `SignTrendCard` stays)

**Interfaces:**
- Produces:
  - `enum AppTab { case home, history, learn, ask }`.
  - `HomeView(history:transition:onStartScan:onStartModelScan:)`: header (`BrandMark`, options menu: Look, Scan a model finger, Study when `saveCapturesForTesting`); a time-of-day greeting; one line about the last check-up ("Last check-up 3 days ago · nothing stood out" / "No check-ups yet"); the main button "Start check-up" with "3 side photos of your index finger" and the finger choice as a small menu under it; "What it checks" tiles (Clubbing → the science page; Nail colour (beta) → `NailCheckView`; Schamroth window (beta) → `SchamrothView`); a small trend card (sparkline of the profile angle and "N check-ups"; tap switches to the History tab) once there are 2 or more sessions; the safety line.
  - `HistoryView(history:)`: a segmented control "Check-ups | Trends". Check-ups: `SessionRow` list, newest first, the delete-all button. Trends: the three `SignTrendCard`s (empty state under 2 sessions).
  - Relative day text helper: `HomeView.lastCheckupLine(_ session: ScanSession?, now: Date) -> String`.

- [ ] **Step 1:** Build the views; remove the old tab roots; keep navigation to `SessionDetailView` from Home and History.
- [ ] **Step 2:** Build. Commit: "Home, History, Learn and Ask: the v2 tabs".

### Task 8: Check on the simulator and the phone build

**Files:**
- Modify: whatever the checks turn up.
- Vault: `~/Downloads/Nail Vitals Vault/Project/Decision log.md`, `Code/Codebase map.md`.

- [ ] **Step 1:** `TOOLS/test.sh` passes.
- [ ] **Step 2:** Simulator, seeded history: screenshot Home, History (both segments), a report card for each state, the clubbing detail, Learn, Ask, in the white look and the dark look.
- [ ] **Step 3:** Largest text size (`xcrun simctl ui booted content_size accessibility-extra-extra-extra-large`): Home and the report card wrap with nothing clipped or overlapping. Fix what fails.
- [ ] **Step 4:** Empty history: Home and History show their empty states.
- [ ] **Step 5:** Device build (`-destination 'generic/platform=iOS'`, signing allowed) succeeds; install on the phone if it is connected and unlocked, and report that the camera flow needs a hands-on check by the user.
- [ ] **Step 6:** Update the vault notes; commit; push `v2`.

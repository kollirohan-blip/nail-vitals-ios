<!-- Copy of the Obsidian vault note 'New signs - measurement and accuracy tests'. -->
---
tags: [v2, spec, science]
status: draft for review
date: 2026-11-11
---
# New signs: how each is measured, and the accuracy test it must pass

Part of [[v2 Design spec]]. **Rule:** a sign stays switched off (`SignAvailability`) until it passes its test. Every threshold is written down **before** the test data is looked at, so we can't move the goalposts afterwards.

## Shared by the colour signs (pallor, cyanosis, tip bands)
- **Capture:**
  - Top view, with the flashlight on at a fixed level.
  - After about 0.5 s of metering, lock exposure, white balance and focus.
  - 3 photos, taken automatically when steady.
- **Finding the nail:**
  - Hand pose gives the fingertip and the DIP joint. The nail sits inside the finger outline toward the tip.
  - The code separates nail bed (pink), white tip (free edge) and skin by colour clustering.
  - If it isn't sure, one confirm screen appears (the one-confirmation rule from Oct 1).
- **Colour reference:**
  - The nail's own **white tip**: it has no blood and almost no melanin, so it works like a built-in white card.
  - Fallback: the locked flash settings only, marked lower confidence.
  - **Never the surrounding skin**, because skin tone would bias it.
- **Numbers:**
  - Nail-bed redness (a\*) and hue angle, relative to the white tip.
  - Median of 3 photos.

## Pallor (anemia sign)
- **Measure:** pallor index = nail-bed redness minus white-tip redness (Δa\*), median of 3.
- **States:**
  - **First 3 check-ups:** "Measured. Building your normal."
    - Optionally, a descriptive comparison with our study group's range, clearly labelled as such.
  - **After that,** your normal = your average ± your measured repeat range.
    - "Paler than your normal, measure again tomorrow" when below that range.
    - "Worth discussing" when still paler on 2 different days.
- **Never** a hemoglobin number. Wording: "Your nail beds look paler than your normal. Paleness can come from anemia (low red blood cells), cold hands or bright light. If it stays paler, ask a doctor about a blood count."
- **Accuracy test (gate):**
  - **P1 Repeatability:** 10 people × 3 check-ups on the same day. Gives the within-person SD and the repeat range.
  - **P2 Lighting:** 5 people under 3 room lights (lamp, daylight, overhead). The shift between lights must be smaller than the repeat range.
  - **P3a Known pale:** the pressed nail during the refill step is definitely blanched. The pallor index on a pressed frame must read far paler, 10 of 10 times.
  - **P3b Raised hand (only if Phase 1 shows it's measurable):** the hand raised above the head for 60 s against the hand lowered. The app should say "paler" in ≥ 9 of 10 people.
  - **P4 Skin tones:** report results by self-reported skin-tone group using the 10-shade Monk Skin Tone scale, with ≥ 3 people in at least 3 groups. Report honestly either way.
  - **P5 Digital:** test images with redness reduced in known steps. The index must fall in the same order.
  - **Pass if:**
    - the P1 repeat range is less than half the P3a blanch change;
    - the P2 shift is smaller than the repeat range;
    - P3a is 10 of 10;
    - P5 is in order.
- **Prior art (cite it, never say "first"):**
  - Mannino et al., Nature Communications 2018: nail-bed photos to hemoglobin, ±2.4 g/dL, 337 people.
  - Emory, PNAS 2025: 89% sensitivity, 93% specificity in real-world use.
  - The Ruby app (formerly AnemoCheck). See [[Prior art and competitors]].

## Cyanosis (low-oxygen sign)
- **Measure:** how far the nail bed's colour shifts toward blue-purple (b\* falling, hue moving toward blue) relative to the white tip, and against your normal.
- **States:**
  - **Typical:** "Not seen".
  - **Measure again:** "Slight bluish tint".
  - **Worth discussing:** "Bluish tint", together with the **urgent text** ("If this is new, or you're short of breath, confused or have chest pain, call 911 now").
  - Thresholds come from the spread of healthy results plus the digital test set, and are written down before testing.
- **Never** an "oxygen level". The Learn page says: "A phone can't replace a pulse oximeter."
- **Accuracy test:**
  - **C1 False alarms:** zero flags across every healthy check-up (target ≥ 30 people, 3 room lights).
  - **C2 Digital:** open-licence photos of blue and healthy nails (check each licence). Report the hits honestly, labelled "photos from the internet, small number".
  - **C3 Filter simulation:** a healthy nail photographed through thin blue or purple theatre gel filters of known strength. The response must rise in order, and the stronger filters must flag. It's labelled a simulation.
  - **Not doing:** making anyone actually low on oxygen (unsafe).
  - **Pass if:** C1 has zero false flags, and C3 is in order and flags the strong filters. C2 is reported either way.
- **Prior art:** a patent (US 11712165) covers phone-based cyanosis and refill measurement. Cite it.

## Capillary refill time (circulation)
- **Capture:**
  - Top view, flashlight on, settings locked.
  - About 8 s of frames at 60 fps; capillary refill needs fine timing, so 30 fps is the minimum.
  - Voice: "Press your nail firmly with your thumb… keep pressing (5-second countdown)… let go now."
  - The phone hand holds still.
- **Measure:**
  - Nail-bed redness in every frame.
  - **Release** = the moment the thumb leaves (the nail area is visible again and at its palest).
  - **Baseline** = before the press.
  - **Capillary refill time** = the time from release until redness recovers **90% of the way back** to baseline.
  - An exponential fit gives a quality check (the method in Bachour et al., arXiv 2102.13611).
- **"Couldn't check" when:**
  - the nail didn't blanch enough;
  - the hand moved (the nail area jumps);
  - the fit quality is low;
  - no release was seen.
- **States:**
  - The common rule is "≤ 2 s is normal".
  - Commonly cited limits by age and sex: 2.0 s for children and adult men, 2.9 s for adult women, 4.5 s for older adults (Schriger & Baraff, Ann Emerg Med 1988). **VERIFY this source before using it.**
  - Cold hands make refill slower, so the app reminds people to warm their hands first.
- **Accuracy test:**
  - **R1 Hand timing:**
    - 40 refill videos, each timed blind by 3 people stepping frame by frame.
    - The reference is the median of the 3, the same design as the 2026 phone refill study NCT07473869.
    - Report bias, 95% limits (Bland–Altman) and ICC.
    - **Pass if** the 95% limits are within ±0.5 s.
  - **R2 Repeatability:** 10 people × 3 tries. Gives the within-person SD.
  - **R3 Optional known change:** after holding the hand in cool (not icy) tap water, refill should be slower. Adults or with consent only.
  - **R4 Digital:** synthetic curves with known times must come out right (unit test).
- **Video wow:** the refill curve draws itself live on screen: "1.4 seconds".

## Spoon nails (koilonychia)
- **Capture:** nothing new; it uses the side photos from step 1.
- **Measure:**
  - Take the nail-plate part of the finger's outline, from the cuticle (already found) to the free edge (`FingerSigns` finds it at a 30° turn).
  - Draw a straight line between those two points.
  - The **nail curve %** is the signed largest gap between the nail and that line, divided by the line's length: + bulging out (normal), − curving in (spoon).
- **States:**
  - **Typical:** curve ≥ 0, within measurement noise.
  - **Measure again:** slightly concave.
  - **Worth discussing:** concave beyond a threshold set from healthy repeat data, written down before testing.
  - **There's no published numeric cut-off,** so this is the app's own line, and it says so.
- **Wording:** "Your nail curves inward like a spoon. Spoon nails can go with iron deficiency. They're also normal in young children."
  - The Learn page explains the water-drop test.
- **Accuracy test:**
  - **K1 Healthy:** every existing side capture (100 photos, 81 measured) plus new ones. **Zero** spoon flags.
  - **K2 Designed shapes:** a spoon-nail outline with a known curve, put through the 3D pipeline: rendered photos like the clubbing designs, and later a printed sleeve. It must measure within tolerance and flag.
  - **K3 Internet photos:** open-licence side photos of spoon nails. Report how many flag (small number).
  - **K4 Repeatability:** the spread of the curve % within one session.
  - **Pass if:** K1 has zero false flags and K2 is within tolerance and flags.

## Terry's / half-and-half nails (existing, made automatic)
- **Measure:** the same top photos. `NailColorAnalyzer` reads along the nail from the hand-pose tip and DIP points, with no tapping (one confirm screen if unsure).
- **Accuracy test:**
  - **T1:** healthy top-view nails from ≥ 30 people, **zero flags**. This has never been done.
  - **T2:** the 10 Wikimedia examples must still flag.

## Schamroth window (existing beta, optional step)
- **Accuracy test:**
  - **S1:** real fingers of healthy people. The window must be seen in ≥ 9 of 10.
  - **S2:** clubbed photos from the internet. Report the results.

## Data for the video
| Number | Comes from |
|---|---|
| People checked, check-ups, photos | Study mode plus the photo study |
| Accuracy for each sign (the tests above) | photo-lab reports |
| Refill time: app vs hand timing | R1 Bland–Altman |
| First-timers who finished with no help, and their median time | First-timer test (Phase 6) |
| Spread of skin tones | Monk scale tags in Study mode |

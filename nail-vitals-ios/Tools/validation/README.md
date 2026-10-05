# Nail Vitals validation study

How to collect the data that shows how accurate and repeatable the app is. Plan on about 15–20 people. Everything here runs on testing builds (`saveCapturesForTesting = true`).

## What we'll be able to report

| Question | Measure | Where it comes from |
|---|---|---|
| Does the app agree with careful hand measurement? | Bland–Altman bias and 95% limits, mean difference, ICC | App vs. each person's labels |
| Do two people agree with each other? (the bar the app should meet) | The same, person vs. person | Two team members' labels, and the ImageJ rater |
| Does the same finger give the same result twice? | Test-retest ICC(1,1), within-person SD | Two sessions per person |
| Does lighting change the result? | Each reading's offset from that person's own average, by lighting | The lighting tag and the flashlight record |
| Does it work equally across skin tones? | App-vs-people difference by skin-tone group | The skin-tone tag |

Report what comes out, good or bad. A number like "ICC 0.94 across 18 people" is only worth something if it was measured.

## Before you start

- **Permission:**
  - Ask every person (and a parent, for anyone under 18) if it's OK to photograph their index finger for a school project.
  - Tell them the photos stay private to the team and are deleted when the project ends, or sooner if they ask.
- **Codes, not names:** the app uses P1, P2, …. Keep any list linking codes to names on paper, not in the app.
- **App:** build from the `pivot/hand-pose` branch so everyone measures with the same version.
- **Start clean:** Study → **Delete saved photos** (after copying anything you need to the Mac).

## For each person

1. Study panel (the person icon on Home's ••• menu):
   - **Add a person**, then tap them to select.
   - Set their **skin tone** (optional).
   - Set **Lighting for the next scans**.
2. **Session A:** room light. Right index finger, one full scan (3 readings).
3. **Session B,** at least 10 minutes later, ideally another day, in different light:
   - Change the lighting tag to Daylight, Dim or Bright lamp.
   - Or turn on the app's flashlight (••• menu in the camera). That's recorded automatically.
   - One full scan.
4. **Optional:** the same for the left index finger.

If the app asks for a retake (blurry or turned), just retake. Those photos are saved too, marked as failures, and left out of the numbers.

## Labeling by the team (Label mode)

- **Who:** each team member labels every photo: Study → **Label saved photos**.
- **Order:** go in a different order from the scanning order, and don't look at the app's numbers first.
- **Taps snap:** taps snap to the same finger outline the app measures, so this checks *where* on the edge the points go.

## An independent rater in ImageJ

Someone outside the team, like a teacher or a friend who hasn't seen the app's numbers, measures the same photos in free software. This is the most independent reference we can have.

1. **Get the photos:** on the Mac, they're in `captures/<folder>/<capture>/photo.jpg` after a pull. Or use Study → Share saved photos.
2. **Install ImageJ:** **Fiji** (imagej.net/software/fiji), which is free.
3. **Set pixels as the unit:** Analyze → Set Scale → **Click to Remove Scale**, so coordinates are in pixels.
4. **For each `photo.jpg`:** open it and select the **Multi-point** tool (the point tool; double-click it for multi-point).
5. **Click the 7 points in this order,** all on the outline of the finger:
   1. **Cuticle:** where the nail meets the skin fold, on the nail's edge.
   2. **Nail:** the nail's edge about a quarter of the way from the cuticle to the nail tip.
   3. **Skin:** the skin's edge the same short distance below the cuticle.
   4. **Crease:** the nail-side edge over the last joint, at the skin crease on the back of the finger.
   5. **Nail tip:** the nail-side edge where the nail ends at the tip.
   6. **Across cuticle:** the opposite edge of the finger, straight across from the cuticle.
   7. **Across crease:** the opposite edge, straight across from the crease.
6. **Measure:** Analyze → **Measure** (Ctrl/Cmd+M). The Results table shows 7 rows with X and Y.
7. **Save:** File → Save As in the Results window, as `imagej-<initials>.csv` in **the same folder as that `photo.jpg`**. For example `captures/new/20261005-141502/imagej-JT.csv`.
8. **Clean up:** clear the results (Results → Clear Results) and the points before the next photo.

The report computes the three angles from these points with the same formulas as everything else. So only the person differs, never the math. (ImageJ's own angle tool can't tell 170° from 190°, so we use the points, not that tool.)

## Running the report

After pulling (`Tools/pull-captures.sh captures/<folder>`) or importing a teammate's zip (`Tools/import-captures.sh`):

```bash
cd nail-vitals-ios/Tools/photo-lab
./photo-lab --report ../../../captures/<folder>/2026* --out /tmp/nv-report
```

- **Output:** `report.txt`, `report.csv` and the Bland–Altman charts land in `/tmp/nv-report/report/`.
- **Blurry and turned photos** are left out automatically, the same way the app leaves them out.
- **Angle values instead of points:** if a rater gives values, put them in a CSV with columns `capture,rater,profile,hyponychial,depth_ratio` and add `--imagej that.csv`.

## Open questions the study data should settle

- **Where the knuckle crease goes:**
  - **Now:** the app takes it level with hand pose's DIP joint.
  - **Test:** `--crease-offset 0.15` takes it 15% of the way toward the tip, where one person's labels put the visible crease.
  - **First result** (4 photos, one person): the fingertip angle's gap to the labels went from 1.7° to 0.6°, and the healthy average from 179.0° to 177.1°.
  - **Next step:** compare both against every rater before changing the app.
- **The nail-angle gap:** the app reads about 3° below one person's hand labels. Check whether other raters, especially ImageJ, see the same gap.

## Keep in mind

- **Old photos:** photos from before October 2, 2026 were measured differently (whole-photo outline, closer framing). Keep them out of the study. Their `capture.json` has no `outline` field.
- **ICC depends on who's measured:** it's higher when people differ a lot from each other. With only healthy fingers, the spread between people is small, so the ICC will be lower than in a mixed group. Say which group it came from.
- **Clubbed fingers are rare** in a school setting. Accuracy on clubbed fingers needs the simulations (3D-printed fingers, wax) or clinical partners, and should be reported separately.

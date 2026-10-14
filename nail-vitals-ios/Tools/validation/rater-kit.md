# Rater kit: 15 photos, 3–4 people, about 30 minutes each

**Purpose:** check whether people placing the points by hand agree with each other, and with the app. It also settles the open question in the README: is the app's nail angle really about 3° lower than hand-placed points? That gap so far comes from 4 photos and one person.

## The photos
- **Where they are:** `captures/rater-kit/` on the Mac (gitignored; these are photos of people's hands).
- **What's in it:** 15 sharp photos with good background contrast and a straight finger, one per scanning session:
  - 8 from family scans on Sep 29–30;
  - 7 from P1, across Sep 30, Oct 2 and Oct 5.
- **Privacy:**
  - Label on the team's Mac.
  - Don't copy the folder anywhere else, post it, or send it to an AI tool.

Label them in this order, which is shuffled so it doesn't follow the scanning order:

| # | Folder | # | Folder | # | Folder |
|---|---|---|---|---|---|
| 1 | 20260930-204814 | 6 | 20260930-202616 | 11 | 20260930-234853 |
| 2 | 20260930-203214 | 7 | 20260930-014751 | 12 | 20261002-203147 |
| 3 | 20261005-144005 | 8 | 20261002-212447 | 13 | 20261002-211628 |
| 4 | 20261005-104531 | 9 | 20260930-172233 | 14 | 20261002-191659 |
| 5 | 20260929-211409 | 10 | 20260930-021619 | 15 | 20260930-000152 |

## Who labels
- **Raters:** the team, plus 1–2 people who haven't seen the app's numbers (a teacher, a friend).
- **Initials:** each rater uses their own initials (e.g. `JT`) on every file.
- **Work alone:** don't compare points with other raters until everyone is done.

## How (ImageJ / Fiji, free)
Use the 7-point steps in [README.md](README.md#an-independent-rater-in-imagej):
1. **Set up:** remove the scale, so coordinates are in pixels.
2. **Place the points:** open `photo.jpg` and use the Multi-point tool to click the 7 points in order:
   - cuticle;
   - nail;
   - skin;
   - crease;
   - nail tip;
   - across from the cuticle;
   - across from the crease.
3. **Measure:** Analyze → Measure.
4. **Save:** `imagej-<initials>.csv` **in that photo's own folder**, e.g. `captures/rater-kit/20261005-144005/imagej-JT.csv`.
5. **Next photo:** clear the results and the points.

**Tips:**
- Zoom in (Cmd +) before clicking.
- Place each point on the edge of the finger, not inside it.
- If you can't see a point clearly (e.g. the cuticle), place your best guess. Don't skip it.

## Afterwards (Claude runs this)
```bash
cd nail-vitals-ios/Tools/photo-lab
./photo-lab --report ../../../captures/rater-kit/2026* --out /tmp/nv-raters
```

**What the report shows:**
- each rater vs the app;
- each rater vs each other rater (bias, 95% limits, ICC).

**Rule for correcting the app** (plan item 10): apply an offset only if all of these hold:
- at least 3 raters labelled all 15 photos;
- the raters agree with each other better than with the app;
- the app's bias against the raters' average has a 95% interval that excludes 0.

Otherwise the slide says "offset not confirmed; no correction applied." Both are honest results.

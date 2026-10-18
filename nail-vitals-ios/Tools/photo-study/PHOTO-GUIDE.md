# Photo study: how to take the photos (1 page)

Any phone camera works. The Mac then measures each photo with the app's own code (`Tools/photo-lab`), so these count as real Nail Vitals measurements, reported separately from in-app scans.

## Before you start
- **Consent:** a signed consent sheet for each person (a parent signs for anyone under 18). Write their code on it: V01, V02, V03… If they already have a study code (P1–P4), write that too.
- **Privacy, say this to each person:** "Your photos stay on our team's Mac. We never post them, never send them to an AI, and we'll delete them if you ask."
- **Names never go in file names or folder names.** Only the code.

## The photo
1. **Hand:** right hand. Index finger pointing straight up, other fingers curled into a loose fist, thumb tucked.
2. **Side-on:** turn the hand so you see the side of the index finger, with the edge of the nail showing (not the flat of the nail, not the pad).
3. **Background:** a plain light wall or a sheet of white paper behind the finger. No wood, beige or patterned backgrounds.
4. **Light:** even room light or daylight. No flash, no strong shadow across the finger.
5. **Camera:** portrait orientation, 1× lens (not 0.5×), Photo mode (not Portrait mode). Hold it level with the fingertip, about 30 cm (1 foot) away. The finger from tip to knuckle should fill about a third of the photo's height.
6. **Focus:** tap the fingertip on screen before you shoot. Check the photo is sharp; retake if not.

## How many
- **Set 1:** 3 photos. Between photos, the person lowers their hand and raises it again (this is what makes it a fair repeat).
- **Set 2 (if you can):** 3 more photos at least 10 minutes later. This gives the day-to-day "wobble" number.
- About 1 minute per person per set.

## Getting them to the Mac
AirDrop the photos to the Mac and put them in:

```
captures/photo-study/V01/1/   ← set 1 (any file names, .jpg or .heic)
captures/photo-study/V01/2/   ← set 2
```

Then run (Claude can do this):

```bash
cd nail-vitals-ios/Tools/photo-study
python3 run.py            # measures every new photo
python3 run.py --review   # opens the review page: ✓ or ✗ each automatic dot
python3 run.py            # prints the summary using only ✓ photos
```

## Don'ts
- Don't zoom in with fingers (move the phone closer instead).
- Don't edit, crop or filter the photos.
- Don't photograph anyone without a signed consent sheet.

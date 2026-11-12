<!-- Copy of the Obsidian vault note 'v2 Design spec' (~/Downloads/Nail Vitals Vault). [[links]] point to other vault notes. -->
---
tags: [v2, spec]
status: draft for review
date: 2026-11-11
---
# Nail Vitals v2: design spec

**Status:** draft for review (Nov 11, 2026).
- **Approved in chat:** the one check-up flow (A), all 4 new signs, the rough [[Mockups]] and the [[Colour palette]].
- **Not reviewed yet:** section 5, the summary of [[New signs - measurement and accuracy tests]]. Read that one first.

A copy lives in the repo at `docs/superpowers/specs/2026-11-11-nail-vitals-v2-design.md`, so Claude Code reads the same thing when coding.

## 1. Goal and what success looks like
**Goal.** Regionals ("RSQ") pick only 5 teams, and judges see nothing but our 45-second video. So the app has to look and feel like a real medical product, every feature has to work perfectly on camera, and real data has to back it up.

**Success means:**
1. **One check-up of about 40 s measures every sign.** At least 9 of 10 first-time users finish it with no help. The first-timer test is itself data for the video.
2. **Every sign passes its written accuracy test before it shows up** in the report card or the video. A sign that hasn't passed stays switched off. We don't show it half-working.
3. **Every screen is accessible:** text contrast at least 4.5:1, Dynamic Type (big text) works, and VoiceOver reads it properly.
4. **There's enough data for the video:** accuracy numbers for each sign, number of people, spread of skin tones, and the first-timer test.

**Not doing:**
- No hemoglobin number.
- No oxygen percentage. The app is not a pulse oximeter.
- No diagnosis.
- No App Store release; the free developer account can't publish anyway.
- No photos uploaded anywhere.

## 2. What Rohan said vs. what we assumed
**Said (Nov 11):**
- This is the last big round of app changes.
- Redesign it as an easy medical app.
- Finish the leftovers and add pallor, cyanosis, refill time and spoon nails ("lets just go big").
- Nobody should have to scan separately for each sign.
- Everything must work perfectly; nothing messy.
- Don't cut anything.
- Rohan gets the real scans and data, and digital scans count too.
- Fable 5.2 writes the code.
- No white paper needed (see [[Colour palette]] and [[Mockups]]).

**Assumed:**
- It stays a free iPhone app that measures on the phone.
- It's a screening aid, not a diagnosis.
- Photos never leave the phone.
- The RSQ video is filmed after the app is done.
- **The RSQ deadline is still unknown.** See [[RSQ video]].

## 3. The check-up: one flow, three automatic steps (approach A)
The camera never closes, and the voice coach talks the user through every step.

1. **Side**: the index finger points up, nail edge-on. This is today's scan: 3 automatic photos.
   - Gives clubbing (3 signs) and spoon nails (same photos).
2. **Top**: "Now turn your nail toward me." Flashlight on, camera settings locked, 3 automatic photos.
   - Gives pallor, cyanosis, and Terry's / half-and-half nails.
3. **Press and release**: "Press your nail with your thumb… keep pressing… let go."
   - Records about 8 s of frames for capillary refill time.
4. **Optional:** "Got 10 more seconds?" adds the Schamroth window. It needs two fingers back to back, so a helper or a stand helps.

**Rules:**
- **No white paper.**
  - The side photo needs a plain background that's much lighter or darker than skin. The app already checks this: the contrast test is ΔE ≥ 24.
  - The colour steps use the flashlight with locked settings, and the nail's own white tip as the colour reference.
- **A failed step costs only that step.** "Couldn't check: [reason]" comes with a button to retry just that step. Steps that worked are never redone.
- **Fallback (decided in Phase 1):** if a step can't hit its accuracy bar when people scan themselves, that sign becomes its own short scan, opened from the report card. Rohan said: "If we can do A with accuracy it's the move, if not we can talk about multiple scans."

## 4. Screens (see [[Mockups]])
There are 4 tabs: **Home · History · Learn · Ask**. Results and Trends merge into History.

- **Home**
  - A greeting, and one line about the last check-up.
  - The big "Start check-up" button: "3 steps · about 40 seconds".
  - A "What it checks" grid. Each tile opens its Learn page.
  - A small trend chart.
- **The check-up camera**
  - A step bar (1, 2, 3), the current instruction in big text, and the camera colours you already have (cyan, amber, green).
- **Report card**
  - A banner answering "good or bad?", showing the most serious state among the signs that were measured. "Couldn't check" never counts as a problem.
  - Signs grouped as Shape, Colour, Circulation and Extra, each with a state pill.
  - Then "What to do next", then "Send to doctor" (PDF and FHIR file).
  - The safety line is always there: "A screening aid, not a diagnosis."
  - **Urgent rule:** if cyanosis is flagged, the card also says: "If this is new, or you're short of breath, confused or have chest pain, call 911 now."
- **Sign detail**
  - The value and its state.
  - What it means, in plain words.
  - "Why the app thinks so": the measured photo or the refill curve.
  - "How accurate is this?": our own test numbers, read from a bundled `validation.json` that gets updated as data comes in.
  - Your recent results, and the published range with its source.
- **History:** every check-up, with a trend chart for each sign.
- **Learn:** one page per sign: what it is, what causes it, how the app measures it, sources.
- **Ask:** the existing Gemini chat. It explains and never diagnoses. Its context becomes the whole report card.
- **Research menu (hidden):** Study mode, Label mode, model finger, capture saving. These are testing tools only and never part of the normal flow.

**Order of information** (research, see [[Research - what makes a medical app work]]): result → what it means → what to do next → more help → technical details.

## 5. The new signs (summary)
Full detail and the accuracy tests are in [[New signs - measurement and accuracy tests]].

| Sign | From which step | What the app measures | Has a published cut-off? |
|---|---|---|---|
| Clubbing (3 signs) | Side | Profile angle, hyponychial angle, depth ratio (existing) | Yes: 176° / 192° / 1.0 |
| Spoon nails (koilonychia) | Side | How much the nail plate curves inward | No; the app sets its own line from healthy data |
| Pallor | Top | Nail-bed redness against the nail's white tip, and against your normal | No; compares to your normal |
| Cyanosis | Top | How far the nail bed's colour shifts toward blue | No; set from healthy data and test images |
| Terry's / half-and-half | Top | Pale nail with a darker tip band (existing, now automatic) | The app's own line |
| Capillary refill | Press and release | Seconds until the pink returns 90% of the way | Common rule ≤ 2 s (age and sex limits **to verify**) |
| Schamroth | Optional | Diamond-shaped gap between the nails (existing beta) | Window present or absent |

## 6. Colours
Final: see [[Colour palette]]. The camera colours don't change. The app is neutral with white as the default look. Results use 4 states, each always shown as colour, icon and word.

## 7. How the code fits together
- **`SignResult`** (new model):
  - `sign` (enum), `value` (Double?), `unit`, `state`, `reason` (why it couldn't check), `evidence` (photo index, curve points, outline), `analyzerVersion`.
  - `state` is one of `typical`, `measureAgain` (close to a cut-off), `worthDiscussing` (past a cut-off) and `couldntCheck`.
  - Each sign documents how its numbers map to these 4 states.
- **`CheckupSession`**:
  - Holds the side readings, top readings, refill result and optional Schamroth, and produces `[SignResult]`.
  - Saved to history as JSON.
  - Old sessions are migrated and show as clubbing only.
- **Analyzers are pure code with no UI**, so `Tools/photo-lab` can run them on the Mac:
  - `KoilonychiaAnalyzer` works on the side outline.
  - `NailRegionFinder` finds the nail bed, the white tip and the fold in the top photo.
  - `NailBedColorAnalyzer` handles pallor and cyanosis, and wraps the existing `NailColorAnalyzer` for the tip bands.
  - `RefillAnalyzer` turns the frame series into a capillary refill time.
- **The camera** is a check-up step machine on top of `CameraManager`:
  - **Side:** as now.
  - **Top:** torch on; after about 0.5 s of metering, lock exposure, white balance and focus.
  - **Refill:** 60 fps frames reduced to stats for each frame. No video is kept unless capture saving is on.
- **Flags:** `SignAvailability` turns each sign on only after its accuracy test passes.
- **Replay:**
  - `photo-lab` gets `--top` and `--refill` modes.
  - The capture recorder saves the top photos and the refill frame stats, so every result can be replayed on the Mac.
- **Tests:**
  - Each analyzer gets a harness like `Tools/angle-harness`, fed synthetic inputs: colour patches, synthetic recovery curves, and designed nail outlines.
  - Rerun `angle-harness` after any change to `AngleAnalyzer`.

## 8. Build order
Each phase ends with a working app. If December runs out, we still have a finished app, not a half-built one.

| Phase | What | About |
|---|---|---|
| 0 | Cleanup:<br>• delete the stale top-level stub folders<br>• fix the README<br>• palette tokens<br>• `SignResult`<br>• sign flags | 1–2 days |
| 1 | **Feasibility on the phone** (throwaway tests):<br>• locked-flash colour stability under 3 room lights<br>• automatic nail-region finding<br>• refill signal while scanning yourself<br>• spoon-nail curve on existing side captures<br>Go/no-go for each sign. | week 1 |
| 2 | New look with today's features: tabs, Home, report card, sign detail, History, Learn | week 2 |
| 3 | The check-up camera flow (steps 2 and 3, voice, capture saving, photo-lab modes) | week 3 |
| 4 | One sign at a time, each with its accuracy test: spoon nails → tip bands (automatic) → pallor → refill → cyanosis | weeks 3–6 |
| 5 | Send to doctor (PDF and FHIR with every sign), "your normal", History polish | week 6 |
| 6 | Polish: accessibility check, first-timer test, voice, speed, demo build (capture saving off) | week 7 |
| — | **Data collection** (Rohan and Rohan Das), from Phase 2 onward | ongoing |

**If the RSQ video is due early December,** film after Phases 0–3 plus spoon nails and pallor, and finish the rest after.

## 9. Risks
- **Scanning yourself with the top view and a thumb press may be awkward.** Phase 1 tests it. Fallbacks: separate scans, or a helper mode.
- **Colour has only been tested on one or two phones** (the 14 Pro, plus the partner's phone if it's an iPhone). Say so in the video and the notes.
- **Skin tone.** Nail beds have little melanin but the skin around them does. That's why the reference is the nail's white tip, not the skin, and results are reported by skin-tone group.
- **Cyanosis can't be tested on people with low oxygen.** It's simulation-tested only, and the wording says so.
- **Time is tight:** 7 weeks. Keep to the order above.

## 10. Open questions
- The RSQ exact deadline and rules: length limit, required content, upload format.
- Which phones are available for testing.
- Who can do the first-timer test (people who have never seen the app).
- The who-is-who answers for the old photos (see [[Leftover to-dos]]).

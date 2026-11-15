<!-- Copy of the Obsidian vault note 'Roadmap to mid-December' (~/Downloads/Nail Vitals Vault/App v2). The vault copy is the master. -->
---
tags: [v2, plan]
status: proposed 2026-11-14, waiting for Rohan's go-ahead
---
# Roadmap to mid-December

**Source:** the 63-page PDF "Clinical UI/UX & Psychological Design Specification" (reviews from Gemini, ChatGPT, Grok, DeepSeek, Perplexity and one more), plus Rohan's request for a much more minimal Home.

**Rohan's decisions (Nov 14):**
- **Accent:** deep teal.
- **Flag colour:** "Worth discussing" becomes burnt orange. Red only on Delete.
- **Wording:** "assessment" everywhere, replacing "check-up".
- **Deadline:** everything done by mid-December. The new signs and data collection come first; the PDF's cosmetic items must not crowd them out.

**How to read this:** six stages in build order. Stages 1–2 are the PDF's must-fix items and take days. Stage 3 puts the new capture steps on the phone so data collection can start in week 2.

## Stage 1: fix what the reviewers caught (Nov 14–16)
Three reviewers independently saw the same problems in the screenshots.

1. **Tab bar bugs.**
   - The "floating clock button" is the tab bar shrinking on scroll. Turn that off.
   - Hide the tab bar on the report card and sign pages, so nothing covers the third sign or the last line.
2. **Percentile colours are wrong.**
   - "86th percentile" in green reads as a good score. It becomes neutral text.
   - Add a small bell curve with a dot for where you sit, drawn from the published mean and spread (Bentley 1976, Husarik 2002).
   - The Nail Vitals Index gets a bar from 0 and a one-tap "how it's calculated".
3. **Every limit names its source.**
   - "limit 176° · JAMA 2001" on the bar. Citations open PubMed.
   - Science page: one paragraph on why sources differ (Lovibond's bedside 160° / 180° against the measured 176°), and why the result needs 2 of 3 signs.
4. **No false precision.**
   - Headline shows "172.2° ± 3°", using our measured repeat range.
   - The dial gets tick labels, a shaded ± band, a legend for its three zones, and a dot marker in place of the sharp needle.
5. **Report card, simpler.**
   - The Clubbing row keeps the number, the state and "5 of 5 checks passed". The three sub-lines move to the sign page.
   - One main next action, chosen by the result: reminder (typical), assess again (measure again), share with your doctor (worth discussing).
   - "Send to doctor (FHIR file)" becomes "Share with your doctor" with "PDF or FHIR" underneath.
   - Delete sits apart from the safety line.
6. **Sign page.**
   - Checks badge directly under the dial. Each check opens to show its value against its threshold ("sharpness 0.31, needs 0.15").
   - Your 3 readings appear as small dots on each range bar, so the spread is visible.
   - The readings table moves under "Clinical details".
7. **Names, colours, spacing.**
   - "Assessment" everywhere.
   - "Nail colour · liver and kidney patterns" becomes "Nail appearance" with no organ claim.
   - US spelling ("color") throughout.
   - Teal accent; burnt orange flag; off-white text on dark.
   - One 8-point spacing scale.
   - Big tabular numerals for every headline number.

## Stage 2: minimal Home, settings, first run, History (Nov 17–19)
- **Home, much more minimal:**
  - One status line: "Right index · Typical · assessed 2 days ago".
  - One hero: the signature arc with your latest value, or a line drawing of the pose for a new user. Under it, the "Start assessment" button and "3 guided side photos · about a minute", with a small Right | Left finger control.
  - One "Last result" row.
  - One "More tests" row that opens Nail appearance and Schamroth window ("validation in progress" replaces the Beta badges).
  - One footer line: "Photos never leave this phone. A screening aid, not a diagnosis."
  - Removed: the greeting, the three tiles, the trend card.
- **Settings** (gear, replacing the "…" menu): look, finger, reminder, privacy and data (what's stored; delete all, with confirmation), research tools.
- **First run, 3 screens:**
  1. What it is and isn't, with a "not a diagnosis" acknowledgement.
  2. Privacy: measured on this phone; photos aren't kept; Ask sends only your numbers and question.
  3. How to hold your finger, and which finger.
- **History as a dashboard:**
  - One chart with a sign picker, for the chosen finger only.
  - Latest against previous, with "small changes are normal".
  - A designed empty state: a faded example trend.

## Stage 3: capture, and data collection starts (Nov 20–26)
This is the original Plan 2 plus the PDF's capture items. It comes early so collecting can run for three weeks.

- **Phone tests first:** top photo with locked flash, press-and-release frames, spoon-nail curve on old captures. Go or no-go per sign.
- **Live checks on the camera:** chips light up as each passes (finger found, distance, straight, side-on, steady); the photo takes itself when all pass.
- **Haptics from the PDF's table:** a crisp tap on lock, a rising buzz on completion, a double pulse when the lock is lost.
- **Help for shaky hands:** take a short burst at lock and keep the sharpest frame.
- **Measuring screen:** a soft sweep over the photo in place of a spinner.
- **Designed failure screen:** "2 of 5 checks passed · retake".
- **Save the finger's outline and measurement points** with each reading. Numbers only, so "photos aren't kept" stays true.
- **The 3-step assessment:** side, top, press-and-release.

## Stage 4: show the measurement (Nov 27–Dec 1)
- **Geometry overlay (the wow moment):** the outline of your own finger with the three measurements drawn onto it, animated. The centrepiece of the sign page and the video.
- **Baseline ring (Rohan's idea):** per finger, a ring whose halo tightens as assessments add up. After each assessment: "your range tightened from ±3.1° to ±2.6°". No streaks or points.
- **"Share with your doctor" PDF:** date, finger, the three signs and each reading, checks, earlier results, limits and method, references. FHIR stays as the data version.

## Stage 5: new signs, one at a time (Dec 2–9)
Each sign ships only after its written accuracy test ([[New signs - measurement and accuracy tests]]).
1. Spoon nails (uses the side photos)
2. Terry's / half-and-half, made automatic
3. Refill time
4. Pallor
5. Cyanosis

## Stage 6: teach and prove (Dec 8–12)
- **Learn in four sections:** understanding clubbing, understanding your measurements, other nail appearances, research and references. Each has a diagram drawn in the app's own style.
- **Interactive normal ↔ clubbed finger:** a slider morphs between our two designed shapes, with the angles updating live.
- **Research and validation page:** method, analyser version, phones tested, how many people, known limits, last update. It shows only numbers we've measured, and a Bland–Altman plot once rater data exists.
- **Ask:**
  - Opens from a result with all three readings pinned at the top.
  - Compact suggestions; a one-line disclosure.
  - Urgent words ("chest pain", "can't breathe") show an urgent-care card in place of an AI answer.
  - Answers link to Learn.

## Then: polish and the video (Dec 12–15)
- First-timer test, accessibility pass, a demo build with capture saving off, then the 45-second video ([[RSQ video]]).

## If time runs short, cut in this order
1. The stretch list below
2. Cyanosis
3. The interactive normal ↔ clubbed finger
4. Pallor

**Stretch, only if everything above is done:** a 3D finger driven by your measurements; a shareable result card image; a live angle line on the camera.

## Where the reviews disagreed, and what we do
| Topic | They said | We do |
|---|---|---|
| The dial | Gemini: dials cause panic, use tracks. Four others: it's your best element. | Keep it, calmer: dot marker, ± band, ticks, legend. Tracks for the three signs. |
| Dark background | This PDF: pure black. Last week's research: never pure black. | Keep the dark grey you approved; add off-white text, which is what prevents the glare. |
| Numbers | Gemini: hide them behind a toggle. Another review: make them the loudest thing. | Report card: one number and a word. Sign page: numbers large. Raw readings under "Clinical details". |
| Leading sign | Perplexity: lead with the fingertip angle. | Keep the nail angle on the dial, and say plainly that the verdict needs 2 of 3 signs. |
| Safety line | One review: once per flow. Project rule: on every result. | On every result screen and the PDF. Off the History and Learn lists. |
| Accent | Navy and neon; teal; or keep it calm. | Deep teal, one accent, no neon. |

## Not doing, and why
- **Web-app fixes** (safe-area CSS, PWA install): Perplexity assumed a website. It's a native app.
- **Logarithmic scales on the bars:** stretching the axis misstates how close a value is to its limit. The ± band shows uncertainty without that.
- **"Processing on Apple Neural Engine — zero cloud transmission":** we can't verify which chip runs it, and Ask does send numbers. We say "Measured on this phone. Photos never leave it."
- **HIPAA / GDPR wording:** we haven't been assessed for either, so we don't claim them.
- **"Fable 5.2 motion assets" and Lottie:** Gemini mistook the coding model's name for an animation tool. Animations are built natively, at the timings it suggests (about 600 ms, eased).
- **Voice-activated shutter:** the photo already takes itself, and a microphone permission adds friction. The sharpest-frame burst covers shaky hands.
- **"Predict when you'll cross the threshold":** nails change slowly and scans vary by a few degrees; a forecast would be invented.
- **"High confidence scan" badge:** it could be read as confidence about health. We say "5 of 5 checks passed".
- **Custom header typeface, neon accents, glow on the dial:** ChatGPT and the Gemini spec both say system font and no glow.
- **Doctor-facing dashboard, translation into other languages:** the PDF report covers the first; the second isn't needed for the competition.

## Data collection (Rohan and Rohan Das), from Nov 20
- Assessments on the phone with Study mode codes; skin tone (Monk scale), age and sex recorded.
- The rater study (15 photos) and the printed-sleeve scans. These fill the validation page.
- New-sign tests as each lands: repeat sets, three room lights, hand-timed refill videos.

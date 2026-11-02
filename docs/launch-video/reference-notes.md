# Launch video: notes from the owner's references (2026-11-02)

The owner uploaded four reference videos (they live only in that session's uploads, not in the repo). **A is the favourite, and its sound is the one to take inspiration from** ("love this the most, love the sound here"). Font: **Geist** (owner's choice). Use the references as inspiration only: never reuse their audio, footage or brand assets.

## A: "One" (agent inbox app): the main reference. 31.5 s, 1920×1080, 60 fps.
- **Cold open (0–2.5 s):** full-bleed cinematic photos (agate macro, Earth from orbit, jungle canopy, rocket launch), cut every half beat, each with a white logo and wordmark framed by four small corner ticks.
- **Match cut (2.5 s):** the corner ticks become four accent-blue dots on a light warm-grey canvas with a faint grid. The dots carry over between scenes as a motif.
- **Beat drop (3 s):** small white label chips pop onto the grid one per beat, with mono terminal lines typing in. A shuffle of blue blocks clears to the headline.
- **Headlines:** big, left-aligned, tight tracking, revealed **word by word** with a short blur-in ("Every agent. One inbox.", "Answer in a keystroke.", "Press to talk.", "See every agent.").
- **UI:** near-black rounded panels with small type, green status dots and blue accents. A dock slides in from the screen edge, and toasts emerge from it. Panels arrive with a slight 3D tilt that settles flat.
- **Interaction:** **physical keycaps** (black rounded keys, pressed on the beat) drive the UI. Dictation text appears word by word, then morphs into "Sent to …" with a check. A hand-drawn scribble marks a list row, and rows light up green one per beat.
- **Dark middle section:** a panel expands to fill the frame ("Something's still waiting."), and an iPhone slides up.
- **Ending:** back to light; a card pushes toward the camera, blurs and fades to the mascot alone, then crossfades to a cinematic photo end card (logo, tagline, URL). The last ~3 s are silent.

### A's sound, measured with numpy
- **Tempo:** 120 BPM (autocorrelation peak at 119–121); first downbeat at 0.49 s.
- **Intro (0–2.5 s):** no bass. Mids only, with energy around 1–2 kHz: airy and filtered.
- **Bass entry:** sub-bass comes in at about 3.0 s (bar 2, beat 2), right on the cut to the canvas.
- **Groove:** not four-on-the-floor. It's **syncopated, sustained sub-bass notes** with soft plucky mid stabs and sparse hats. Very little top end (8–11 kHz is about −24 dB against the mids), so it sounds warm and rounded rather than bright.
- **Breaths:** at a few moments the top end drops out for a single beat before a reveal (around 7.0, 9.0, 14.0 and 14.5 s).
- **Ending:** one big sub-heavy hit at about 26 s, a low-passed tail of about 2 s, then silence under the end card.
- **Level:** moderate loudness (RMS about −24 to −17 dB in the groove).

## B: "holo"
Loud kinetic gradient typography and photo collages. Useful idea: a **vertical word list** ("Ads / Socials / Emails / SEO"), with the active word in black and a dot beside it, while the UI on the right changes. Don't use its gradients (they clash with the clean A style).

## C: "fomo"
A dark open with a green line chart drawing itself, a blue 3D card, a phone UI and counters. Useful: numbers counting and a line drawing itself. Avoid the glows.

## D: Grok "Build Mode"
Pure white canvas. Typed text with a caret, a prompt bar that morphs, a horizontal word carousel with motion blur ("Build · Deploy · Share"), a phone UI, and very soft shadows. Useful: the caret typing, the **motion-blurred carousel** (could be Convert's WebP · AVIF · JPG · PNG · HEIC) and the restraint.

## Droptimize motion, from `Bubble/Motion.swift` (use the real values, scaled to the frame)
- **Bubble:** 44 pt, 60% opacity at idle, ×1.06 on hover, ×1.2 when a drag enters.
- **Menu:** a 160° arc facing into the screen with ring radius 80; 40 pt segments (×1.15 on hover) that fan out 25 ms apart.
- **Option bubbles:** 34 pt, 56 pt beyond the ring, 20 ms apart.
- **Progress ring:** 54 pt, 3 pt line.
- **Springs:** response 0.35 s with damping 0.75 (main), 0.2 / 0.8 (hover), 0.4 / 0.8 (snap).
- **Feedback timing:** ripple 0.4 s; shake 0.4 s with 6 pt travel.
- **Glyphs (SF Symbols):** Convert `arrow.triangle.2.circlepath`, Compress `rectangle.compress.vertical`, Half size `arrow.down.right.and.arrow.up.left`, Remove BG `scissors`, Auto `wand.and.stars`.
- **Logo:** nested circles, mint dot `#3DDC97`.

## Voice-over (ElevenLabs, connected 2026-11-02)
The owner wants an engaging female voice and to preview it before it's used.
- **First round:** Didi Sherwood (`AhjZC0ZjjAe9YVCMX0PH`), Sia (`qTRV75fy2dUja4REMifv`) and Clara V. (`0ggs85h7hrWz8ExXnsBc`). The owner preferred **Sia's energy**, but found her "too Gen Z, not so professional".
- **Second round:** Sia's energy, but more grown-up and professional:
  - **Emma, Professional Commercial** (`9HBoEQ8LqyvVZFYDodnr`), the pick: clear, confident, polished, neutral American, made for product launches.
  - **Christina, Energetic Commercial** (`BuaKXS4Sv1Mccaw3flfU`).
  - **Lola, Engaging News & Ads** (`MQCqYs9QBU817XwwHCTz`): warm and composed; works best with `eleven_v4`.
- **Sent to the owner:** the three stock samples, plus Sia reading our line ("Every photo. Every video. One drop. Droptimize makes them smaller, right where you work. Drop it. Done.", `eleven_v4`, 131 credits, 9.1 s; the second take didn't start, so it wasn't charged).
- **Chosen: Emma** (owner, 2026-11-02: "emma is the best"). Her take of our line is in `audio/emma-preview-line.mp3` (one take, 131 credits).
- **Owner's rule:** they're on the ElevenLabs Starter plan and want **no charges beyond it**. So: price first with `estimate_only`, one take per line, and synthesise UI sounds rather than buying sound effects.

## Prompt
Written: `PROMPT.md` (the owner's structure, tailored to Droptimize).

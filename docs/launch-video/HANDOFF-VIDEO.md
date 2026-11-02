# Launch film: handoff (read this first if you're picking up the video)

> The owner asked for this file so any Claude can continue the film exactly where the last one stopped. **Keep it current:** tick steps as they land, and record every decision and file path. Also read `PROMPT.md` (the brief) and `reference-notes.md` (what the references do, the measured sound, the voices).

## Where it stands (2026-11-02)

The owner approved the brief and the VO script ("let's build the vid") and left the missing inputs to us.

- [x] **Brief:** `PROMPT.md`. Owner's structure; references analysed in `reference-notes.md`.
- [x] **Voice:** Emma, `voice_id 9HBoEQ8LqyvVZFYDodnr`, model `eleven_v4`. Preview: `audio/emma-preview-line.mp3`.
- [x] **Fonts:** Geist and Geist Mono from npm `geist@1.3.1` (SIL OFL), `package/dist/fonts/geist-sans/*.woff2` and `geist-mono/*.woff2`. Fetch with `npm pack geist@1.3.1`; GitHub downloads are blocked here, npm and jsDelivr work.
- [x] **Music:** see *Music* below.
- [x] **Photos:** none, by the owner's call (see *No photos*).
- [ ] **VO lines:** generate the 9 lines, one take each. Price with `estimate_only` first; about 320 credits.
- [ ] **Animation:** `film/index.html`, with `seek(t)` as the only source of truth.
- [ ] **Stills:** one per beat, then fix anything off.
- [ ] **Audio:** `film/mix.py`. Cut and stretch the track, add the VO with ducking, synthesise the UI sounds, add the final hit and the tail.
- [ ] **Render:** `film/render.js` (Playwright, 240 fps subframes piped to ffmpeg `tmix`, output at 60 fps), then mux.
- [ ] **Deliver:** send the MP4 to the owner (`SendUserFile`). Keep big media out of git (see *Licences*).

## Owner's rules for this work
- **ElevenLabs:** they're on the **Starter plan** and want **no charges beyond it**. Always `estimate_only` first, use **one take** per line, and never retry a generation call.
  - Spent so far: 131 credits (a Sia test) and 131 (Emma's preview).
- **UI sounds:** synthesise with numpy. Never use paid sound-effect generation.
- **Delivery:** they're not technical. Send the finished film as a file; explain things in plain words.

## Music: "Hazy After Hours" by Alejandro Magaña (A. M.), Mixkit
- **Source:** Mixkit track 132, `https://assets.mixkit.co/music/132/132.mp3`, 2:07. Licence: Mixkit Stock Music Free License (commercial video use allowed; no credit required).
- **Why this one:** out of 172 Mixkit tracks, it's the closest electronic match to reference A's measured sound: about 120 BPM, warm (top end about 23 dB under the mids), deep sub, a bass-light intro, then the bass entering on a downbeat.
- **Measured tempo:** **120.90 BPM**; first beat at 0.476 s. Stretch it to exactly 120 with `atempo=0.99256` (120/120.9); that's inaudible.
- **Shape, in track bars (raw time):**
  - Bars 1–8 (0.5–16.4 s): intro, quiet sub, mids only.
  - **Bar 9 (16.4 s): the bass and groove come in.**
  - Bars 9–24: steady groove.
  - Bar 25 (48.1 s): fuller.
  - Bar 57 (111.6 s): outro.
- **The edit:** put track bar 9's downbeat (after the stretch) at **film t = 2.0 s**, so the film's audio starts 2.0 s before it.
- **Change from `PROMPT.md`:** the drop and match cut move from 2.2 to **2.1 (t = 2.0 s)**, so they land on the music's real downbeat.
- **Processing:**
  - High-pass the first 2.0 s at 250 Hz and cross-fade into the full mix at the drop.
  - "Breaths": low-pass at 800 Hz for one beat before big reveals.
  - Final deep sub hit on 14.1 (t = 26 s), synthesised (a 45→38 Hz sine with a fast attack and a 1.5 s decay), with a 2 s low-pass sweep and fade after it.
  - Silence from 28 to 31 s.

## No photos (owner, 2026-11-02)
"Don't use stock photos, man, just text and UI elements are enough." Everything on screen is type and UI drawn in HTML/SVG:
- **Cold open:** big Geist Mono file names and sizes on near-black, with corner ticks.
- **Thumbnails:** flat, abstract tiles.
- **Remove BG subject:** simple SVG headphones on solid yellow.

(An earlier pass picked Unsplash photos; they were dropped.)

## VO lines (Emma; beats from `PROMPT.md`, adjusted for the drop at 2.1)
| # | Starts at (bar.beat → t) | Line |
|---|---|---|
| 1 | 1.2 → 0.5 s | Your files are too heavy. |
| 2 | 2.3 → 3.0 s | Meet Droptimize. |
| 3 | 3.1 → 4.0 s | Drop any photo or video on the bubble. Done. |
| 4 | 5.1 → 8.0 s | Convert to WebP or AVIF in one move. |
| 5 | 7.1 → 12.0 s | Lift the background right out. |
| 6 | 9.1 → 16.0 s | Videos too, down to whatever size you need. |
| 7 | 11.1 → 20.0 s | All on your Mac. Nothing uploaded. |
| 8 | 12.2 → 22.5 s | Batches in one drop. Already on your clipboard. |
| 9 | 14.1 → 26.0 s | Droptimize. Drop it. Done. |

Bars are 2 s long and t = (bar − 1) × 2 + (beat − 1) × 0.5. Generate each line separately, trim the leading silence, and line up each line's first-syllable onset with its time.

## Licences and what goes in git
- **Commit:** the film's sources (`film/*.html`, `*.js`, `*.py`), and these notes.
- **Don't commit:** the music file (fetch it by URL; keeps the repo light and the licence clean), or renders (send them to the owner instead).
- **Fonts:** OFL, so committing them is allowed, but fetching from npm is simpler.

## Environment notes (cloud session)
- **Working folder:** the scratchpad (`…/scratchpad/film/`). It disappears with the session, so re-fetch the assets with the URLs above.
- **Tools:** Python 3 with numpy (no scipy), ffmpeg/ffprobe, and Node with the system Playwright (`require('playwright')`, `chromium.launch()`; don't reinstall).
- **Network:** jsDelivr, npm, mixkit.co and assets.mixkit.co work; Pixabay, Pexels and github.com downloads don't.

# Launch film: handoff (read this first if you're picking up the video)

> The owner asked for this file so any Claude can continue the film exactly where the last one stopped. **Keep it current:** tick steps as they land, and record every decision and file path. Also read `PROMPT.md` (the brief) and `reference-notes.md` (what the references do, the measured sound, the voices).

## Where it stands (2026-11-02)

The owner approved the brief and the VO script ("let's build the vid") and left the missing inputs to us.

- [x] **Brief:** `PROMPT.md`. Owner's structure; references analysed in `reference-notes.md`.
- [x] **Voice:** Emma, `voice_id 9HBoEQ8LqyvVZFYDodnr`, model `eleven_v4`. Preview: `audio/emma-preview-line.mp3`.
- [x] **Fonts:** Geist and Geist Mono variable fonts committed in `film/fonts/` (from npm `geist@1.3.1`, SIL OFL, licence in `film/fonts/OFL.txt`).
- [x] **Music:** see *Music* below.
- [x] **Photos:** none, by the owner's call (see *No photos*).
- [x] **VO:** generated once as a single take with long pauses, 427 credits: **`audio/emma-vo-full.mp3`** (31.4 s, committed so it never has to be paid for again). Split by silence; placements are in *VO placement* below.
- [x] **Animation:** `film/index.html`. Every style comes from `seek(t)`, using closed-form springs with the app's own values; `window.EVENTS` is the sound cue list. A first cut covers the whole timeline below.
- [x] **Stills:** checked through the film. Fixed so far: the cold open on the light canvas, elements hidden with `visibility` that a child overrode (hide with `display`), the camera push cropping the headline, tiles over the headline, the Remove BG preview over the word list, the dark scene covering its headline, the 486 KB card lingering behind the logo, and the headline running into the Mac outline.
- [x] **Audio:** `film/mix.py`: stretch and cut the track; high-pass until the drop; breaths at 11.5 and 25.5; low-pass and fade after the 26.0 hit; Emma's lines placed and the music ducked 8 dB under them; synthesised UI sounds from `events.json`; the synthesised deep hit. **Bar 9 comes from the beat grid** (0.476/stretch + 16 + 0.005 s); onset-picking caught a bass swell 83 ms late.
- [ ] **Render:** `film/render.js full video.mp4` (240 fps subframes piped to ffmpeg `tmix`, out at 60 fps; several minutes), then mux: `ffmpeg -i video.mp4 -i mix.wav -c:v copy -c:a aac -b:a 256k -movflags +faststart droptimize-launch.mp4`. **In progress.**
- [ ] **Deliver:** send the MP4 to the owner (`SendUserFile`). Keep big media out of git (see *Licences*).

## Owner's rules for this work
- **ElevenLabs:** they're on the **Starter plan** and want **no charges beyond it**. Always `estimate_only` first, use **one take** per line, and never retry a generation call.
  - Spent so far: 131 credits (a Sia test), 131 (Emma's preview) and 427 (the full VO). **Nothing else should need generating.**
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

## VO placement (from `audio/emma-vo-full.mp3`; silence threshold −45 dB)
| # | Line | In the source file (s) | Placed at (film t, s) | Ends |
|---|---|---|---|---|
| 1 | Your files are too heavy. | 0.08–1.85 | 0.25 | 2.02 (just as the bass drops at 2.0) |
| 2 | Meet Droptimize. | 3.65–4.80 | 2.50 | 3.65 |
| 3 | Drop any photo or video on the bubble. Done. | 6.21–9.43 ("Done." 9.13–9.43) | 4.00 | 7.22 ("Done." at 6.92, as the check lands) |
| 4 | Convert to WebP or AVIF in one move. | 10.63–13.78 | 8.00 | 11.15 |
| 5 | Lift the background right out. | 14.88–16.47 | 12.00 | 13.59 |
| 6 | Videos too, down to whatever size you need. | 17.62–20.45 | 16.00 | 18.83 |
| 7 | All on your Mac. Nothing uploaded. | 21.48–23.70 | 20.00 | 22.22 |
| 8 | Batches in one drop. Already on your clipboard. | 24.75–27.77 | 22.50 | 25.52 |
| 9 | Droptimize. Drop it. Done. | 28.85–31.22 | 26.00 (with the final hit) | 28.37 |

Cut each segment with a 30 ms margin either side and 10 ms fades. **The film is 31.5 s:** 28.5 s of picture plus 3 s of still, silent end card.

## Timeline (absolute seconds; beat 0.5 s, bar 2 s)
- **0–2 · Cold open** on near-black: four mono file cards cut at 0.0, 0.5, 1.0 and 1.5 (`IMG_2041.HEIC 12.4 MB`, `launch.mov 840 MB`, `hero.png 6.1 MB`, `shoot.tiff 48 MB`), each with four corner ticks.
- **2.0 · Drop.** Hard cut to the warm-grey grid; the corner ticks spring into four mint dots around the headline; the bubble fades in at the right edge. Headline "Drop" at 2.0, "it." at 2.5. The bubble pulses on "Droptimize" (~2.9). The file tile springs in at 3.0 and the cursor reaches it at 3.5.
- **4–8 · Core move.**
  - 4.0 grab; drag 4.0–4.75. At 4.5 the drag enters: bubble ×1.2, segments fan at 4.5, 4.625, 4.75 and 4.875.
  - 5.0 hover Convert, 5.25 hover Compress; option bubbles fan from 5.5 (16ths).
  - 6.0 drop on 500K: ripple, ring 6.0–6.75, check at 7.0 (with "Done."). Result card at 7.0; odometer 12.4 MB → 486 KB over 7.0–7.5; "−96%" at 7.5; headline "Done." at 7.0.
- **8–12 · Convert.** The word list replaces the headline (Convert active). `hero.png 6.1 MB` is dragged in 8.0–8.75; hover Convert at 9.0; the format carousel WebP · AVIF · JPG · PNG · HEIC settles on AVIF at 10.0 (drop); result `hero.avif 412 KB −93%` at 10.5–11.0. Breath (low-pass for one beat) at 11.5.
- **12–16 · Remove BG.** The word list steps to Remove BG. A big preview card with SVG headphones on yellow: the background dissolves to a checkerboard at 13.0; the background chips None · White · Black · … fan at 13.0–13.5; pick White, fill at 14.0; result card "Done · Background: White".
- **16–20 · Video.** Headline "Videos too." `launch.mov 840 MB` dragged in. Video arc: Convert, Compress, Resize, Mute. Hover Compress at 17.0; sizes 10 · 25 · 50 · 100 MB · … ; drop on 25 MB at 17.5. The ring fills in quarters on 18.0, 18.5, 19.0 and 19.5 while 840 → 24.1 MB; result `launch-25mb.mov −97%` at 19.5.
- **20–22 · Private.** The result card expands to fill the frame, near-black. "Never leaves your Mac." word by word on beats; a Mac outline with file tiles moving only inside it.
- **22–25 · Batch and paste.** Back to light at 22.0. Ten small tiles stream into the bubble on 16ths from 22.25, with the counter 1/10 → 10/10 inside the bubble; card "10 files · −81%" at 23.5. Keycaps ⌘ (24.0) and V (24.5) press, and the tile pastes into a plain composer.
- **25–28.5 · End.** At 25.0 the composer pushes toward the camera and blurs away; 25.5 card "IMG_2041.HEIC 486 KB"; 26.0 final hit, end card (logo, "Droptimize", "Drop it. Done.", "Free to start · Pro $9.99 once", no URL yet). Hold, then silence 28.5–31.5.

## How to rebuild (from `docs/launch-video/film/`)
```bash
curl -fsSL -o 132.mp3 https://assets.mixkit.co/music/132/132.mp3
node render.js stills stills/ 2.2 7.8 13.4          # check particular moments (or no times: one per beat)
node render.js events events.json
python3 mix.py --music 132.mp3 --vo ../audio/emma-vo-full.mp3 --events events.json --out mix.wav
node render.js full video.mp4
ffmpeg -i video.mp4 -i mix.wav -c:v copy -c:a aac -b:a 256k -movflags +faststart droptimize-launch.mp4
```

## Typography and copy (the owner asked: "no slop typography and AI writing"; checked with the better-typography and better-writing skills)
- **One type scale, seven sizes** (CSS variables in `index.html`): display-xl 220 (sizes in the cold open and the 486 KB card), display 144 (headlines and "Droptimize"), title 96 (word list, carousel, "Never leaves your Mac."), subtitle 48 (file names, result percentages, tagline, keycaps), body 28 (price line, placeholder), ui 24 (bubble labels, options, chips), ui-sm 20 (mono file details, long labels).
- **Spacing and figures:** tracking tightens as the size grows (−0.04em to −0.02em; none at UI sizes); leading 1.1 for headings. Every counter uses tabular figures. Non-breaking spaces sit between numbers and units. Geist Mono only for file names and sizes.
- **Accuracy and plain wording:**
  - Copy matches the app: compressing a HEIC keeps it HEIC (`IMG_2041-500kb.heic`), `hero.avif`, `launch-25mb.mov`, "10 files".
  - The price line is specific: "Free for 3 files a day · Pro $9.99 once".
  - Headlines are plain statements, no hype.

## Licences and what goes in git
- **Commit:** the film's sources (`film/*.html`, `*.js`, `*.py`), and these notes.
- **Don't commit:** the music file (fetch it by URL; keeps the repo light and the licence clean), or renders (send them to the owner instead).
- **Fonts:** OFL, so committing them is allowed, but fetching from npm is simpler.

## Environment notes (cloud session)
- **Working folder:** the scratchpad (`…/scratchpad/film/`). It disappears with the session, so re-fetch the assets with the URLs above.
- **Tools:** Python 3 with numpy (no scipy), ffmpeg/ffprobe, and Node with the system Playwright (`require('playwright')`, `chromium.launch()`; don't reinstall).
- **Network:** jsDelivr, npm, mixkit.co and assets.mixkit.co work; Pixabay, Pexels and github.com downloads don't.

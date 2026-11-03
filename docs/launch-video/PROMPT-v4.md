# Droptimize launch film v4: the prompt (Shotbase style)

Written 2026-11-02 from the owner's new reference, Shotbase's product film (`reference-shotbase.md`: "I want mine like this"), in the owner's prompt structure (`prompt-reference.md`). It replaces `PROMPT.md` for v4; v1–v3 followed `PROMPT.md`. Build on v3's `film/index.html` (its UI pieces, photos, cursor and keycap carry over).

---

<inputs>
Already decided. Don't ask again:
- Product: Droptimize, a Mac menu-bar app. Drag any image or video (from Finder, Photos, a web page) onto a small floating bubble at the screen edge; a radial menu fans out (Convert, Compress, Half size, Remove BG, Auto in the middle); let go on one and a smaller, web-ready file comes back, saved and copied to the clipboard. Everything happens on the Mac; it works offline. Free for 3 files a day; Pro is $9.99 once.
- Font: Geist only (SIL OFL). **No monospace anywhere** (owner).
- Palette: white panels with soft shadows; near-black `#0E0E0F` for dark scenes and text; one accent, Droptimize mint `#3DDC97`, for the highlighted caption word, the progress ring, success states and the end card's glow.
- Wallpaper: **our own** drawn gradient (soft waves in deep blue, teal and a touch of mint, blurred), never Apple's. (A landscape photo was tried on 2026-11-03; the owner preferred the gradient.)
- Voice-over: Emma, re-placed on the new grid (table below): the nine lines of `audio/emma-vo-full.mp3`, plus two lines the owner asked for ("there should be a line for no internet needed and drag from anywhere: Finder, Photos, web"), generated in one take, 80 credits, `audio/emma-vo-extra.mp3`: "Drag from anywhere. Finder, Photos, or the web." (0.03–3.83 s; "Finder" at 1.76, "Photos" at 2.45, "web" at 3.41 into the file) and "No internet needed." (5.84–7.12 s). **No more ElevenLabs generation** without asking the owner.
- Music: Mixkit 175 "Digital Clouds" (A. M.), 129.00 BPM stretched to 128; the owner's pick after hearing five options in the film (2026-11-03; before that, Mixkit 160 "Minimal Emotion"). Film t = 0 is the track's bar 15 downbeat (26.134 s into the file).
- Photos: real ones from Pexels, chosen to avoid the most common stock (owner, 2026-11-03), prepared by `film/prepare-images-v4.py`: a dog on a beach at dusk (`IMG_2041.HEIC`), a rainy street at night (`hero.png`), sea cliffs from above (`launch.mov`), a pineapple on navy (`pineapple.jpg`, the Remove BG subject).
- Format: 1920×1080, 60 fps. **24 bars at 128 BPM = 45.0 s**, then a 3 s silent hold on the end card: **48.0 s** in all. (The first cut ran 26 bars; the owner flagged a long gap after "Done.", so two held bars came out, 2026-11-03.)

Ask me only for:
1. The photos, if they're not in `film/images/`.
2. The website URL for the end card (leave room until there is one).
</inputs>

<direction>
Shotbase's film, made for Droptimize: a macro camera gliding over the real product, small captions telling the story, a bright 128 BPM track.

Look:
- **Macro camera.** The UI is huge: 3× its real size for menu shots (the arc and its options fill the frame's height), up to 6× for close-ups (the bubble's label, the ring, a keycap). The camera never stops: slow pushes, pans and rack focus. Spring 0.8 s / damping 1.0 (no overshoot).
- **Depth of field.** Anything off the focal plane is blurred (the wallpaper always; panels behind the subject 6–12 px). Focus racks from the source window to the bubble during each drag.
- **The cursor** is the macOS arrow at camera scale (about 150 px tall in close-ups), with motion blur from the render.
- **Captions, not headlines.** Geist 600, 64 px, sentence case, tracking −1%, centred on the UI they describe, never over it. Words arrive one at a time with a 10 px blur and 8 px rise, timed to Emma's words. One word per caption is mint (or sits in a mint highlight box with near-black text). Old captions leave with a blur before new ones arrive.
- **Transitions:** a pixel dissolve (squares in the next scene's colour, random order, 0.4 s) at the drop and into and out of the dark scene; blur dissolves elsewhere; one 3D tilt (rotateY −12° → 0 with a soft mint edge glow) on the first result card; zoom-throughs between scenes.
- **The real Droptimize UI** at full fidelity (as in v3): frosted bubble with the nested-circles logo, ×1.06 on hover, ×1.2 on drag-in; the 160° arc, ring radius 80 pt, 40 pt segments fanning 25 ms apart, the hovered label inside the bubble; 34 pt option bubbles 56 pt beyond the ring, 20 ms apart; the 54 pt progress ring with a 3 pt line; the 0.4 s drop ripple; the result card. App springs: response 0.35 s, damping 0.75 (hover 0.2 / 0.8).
- **Tactile close-ups** (Shotbase's keycaps and pills): giant "Photos" and "Videos" pills clicked by the giant cursor; ⌘ and V keycaps, black, rounded, 3 px press depth.
- **Glow, only twice:** the tilted result card's edge and the end-card logo.

Sound:
- **Music:** "Minimal Emotion" from its bar 15. Bar 2 of the film is the track's break (bass out): high-pass it for extra lift; **the drop lands on 3.1 with the reveal of the bubble**. Bars 16–18 are the track's lighter stretch: use it for the dark "Never leaves your Mac" scene. Final sub hit on 23.1, a 2 s low-pass sweep, fade out by 25.1, silence to 48.0. A low-pass breath on 19.4, before the batch.
- **Emma** on top, warm and close; music ducked 8 dB under her (80 ms attack, 250 ms release).
- **UI sounds, denser than v3** (Shotbase has one on every action): a soft tick per segment fan and hover, a felt click for the cursor, a low "thup" on drop, an airy swish on the ripple and the pixel dissolves, ticks as numbers count, a felt click per keycap. Synthesised with numpy, about 18 dB under the music.
- **Master:** −14 LUFS integrated, peaks under −1.5 dBFS (`mix.py`'s mastering step).

Banned: bouncy easing, particle bursts, lens flares, glows beyond the two above, gradients on UI chrome, mismatched icon strokes, dead time, stock-template transitions, fake brand logos, any real company's UI, logo or wallpaper, monospace, rolling digits that smear.
</direction>

<structure>
128 BPM, 24 bars (bar.beat; one beat 0.469 s, one bar 1.875 s). Emma's lines start on the beat shown; captions follow her words, and **no caption appears without her saying it**. Scenes 1–4 are as below; from scene 5 the bars are the retimed ones (2026-11-03).

1. **1.1–2.4 · Cold open** (0–3.75 s), dark blurred wallpaper.
   - Macro drift across four file tiles at different depths: the owner's photos as thumbnails, names and sizes in Geist (`IMG_2041.HEIC 12.4 MB`, `launch.mov 840 MB`, `hero.png 6.1 MB`, `shoot.tiff 48 MB`). Sizes arrive **already settled**, with a blur-in: no rolling digits.
   - Emma at 1.2: "Your files are too heavy." Caption, mint on "heavy".
   - Bar 2 is the track's break: the tiles drift apart in near-silence.
2. **3.1 · Drop** (3.75 s). Pixel dissolve to the bright blurred wallpaper; the Droptimize bubble, macro at 6×, rests at the right edge and pulses on the beat.
   - Emma at 3.2: "Meet Droptimize." Caption, mint on "Droptimize".
3. **4.1–5.4 · Drag from anywhere** (5.6–9.4 s). The owner's point: files come from anywhere.
   - 4.1: the camera pulls back from the bubble; three generic windows float in at different depths around it: a Finder-style file list, a Photos-style grid, a web page.
   - Emma at 4.1: "Drag from anywhere. Finder, Photos, or the web." Caption "Drag from anywhere." (mint "anywhere"), then "Finder, Photos, or the web." with each source word turning mint as she says it.
   - On each word, focus racks to that window and a file lifts a few pixels out of it: Finder at 7.39 s, Photos at 8.08 s, the web at 9.04 s.
4. **6.1–9.4 · The core move** (9.4–16.9 s).
   - 6.1: focus back on the Photos window; the cursor grabs `IMG_2041.HEIC`; it lifts out and the other windows blur away.
   - Emma at 6.3: "Drop any photo or video on the bubble. Done." The drag enters on 6.3: the bubble ×1.2, the arc fans on 16ths. Hover ticks over Convert (6.4), then Compress (7.1); the label inside the bubble swaps; the size options fan (7.2): 100K · 250K · 500K · 1M · 2M · …
   - 7.3: drop on 500K: ripple, ring, **the check lands with "Done."** (13.23 s).
   - 8.2: the result card slides out and tilts flat from −12° with the mint edge glow; `12.4 MB → 486 KB` (settled values, cross-fading, not rolling); "−96%" on 8.4.
5. **8.4–11.4 · Convert** (14.4–20.6 s).
   - 8.4: the camera leaves the −96% card for the web page from bar 4. 9.1: `hero.png` is dragged off it; the page fades as it lifts.
   - Emma at 9.2: "Convert to WebP or AVIF in one move." Caption, mint on "AVIF".
   - 9.3: the drag enters; hover Convert; the format options fan; the cursor passes WebP and settles on AVIF as she says them; drop on 11.1. Result `hero.avif 412 KB −93%` on 11.3.
6. **12.1–13.4 · Remove BG** (20.6–24.4 s).
   - `pineapple.jpg` mid-drag, its photo on a panel beside the bubble. Emma at 12.2: "Lift the background right out." Caption, mint on "out".
   - The background discs fan (none, white, black, eyedropper); on "right out" the navy backdrop dissolves to a checkerboard under the cut-out. 13.1: hover white; drop on 13.2; white fills behind it, a slow push in.
7. **14.1–16.4 · Video** (24.4–30.0 s).
   - 14.1: two giant pills, "Photos" and "Videos"; the cursor clicks "Videos" on 14.2.
   - Emma at 14.2: "Videos too, down to whatever size you need." Captions, mint on "Videos", then on "size".
   - 14.3: `launch.mov 840 MB` mid-drag; hover Compress; sizes fan (10M · 25M · 50M · 100M · …); drop on 25M on 15.3. The ring fills a quarter per beat (15.4–16.3) while the size steps down to `24.1 MB`; "−97%" just after.
8. **17.1–19.4 · Private and offline** (30.0–35.6 s).
   - Pixel dissolve to near-black. The camera pulls back: the canvas shrinks into a flat silver laptop (v3's), files changing size only inside it.
   - Emma at 17.2: "All on your Mac. Nothing uploaded." Caption, mint on "Mac".
   - Emma at 18.4: "No internet needed." Caption, mint on "internet"; a small Wi-Fi glyph in the laptop's menu bar switches off as she says it, and the files keep shrinking.
   - Low-pass breath on 19.4.
9. **20.1–22.4 · Batches and paste** (35.6–41.25 s).
   - Pixel dissolve back to light. A stack of ten on the cursor drops on Auto (20.2); they fan out beside the bubble and fly in on 16ths; the bubble counts 1/10 → 10/10; card "10 files · −81%" on 21.1.
   - Emma at 20.2: "Batches in one drop. Already on your clipboard." Captions, mint on "drop", then "clipboard".
   - 21.3–21.4: macro on the ⌘ and V keycaps pressing. 22.1: the image pastes into a plain, unbranded chat composer and sends on 22.3.
10. **23.1–25.1 · End** (41.25–45.0 s), then a silent hold to 48.0.
   - Zoom through the sent image to near-black; the nested-circles logo blurs into focus with a soft mint glow over a faint pixel grid.
   - Emma at 23.1, with the final sub hit: "Droptimize. Drop it. Done."
   - End card: logo, "Droptimize", "Drop it. Done.", "Free for 3 files a day · Pro $9.99 once", room for the URL. Still and silent from 45.0 to 48.0.
</structure>

<build>
1. Keep v3's method: one HTML file, every style computed from `seek(t)`, closed-form springs (a sum of one spring per target change), drags as direct manipulation, `window.EVENTS` as the sound cue list, local fonts awaited before the first frame.
2. **Camera:** one world transform (scale, x, y) driven by springs toward per-beat targets; depth of field as CSS blur by distance from a focal plane that is itself a spring. Never `will-change` on scaled text; keep text on whole pixels at rest.
3. **Captions:** take Emma's word onsets from `audio/emma-vo-full.mp3` (energy envelope, checked by ear against the line table) and drive each caption word from them.
4. **Pixel dissolve:** a 24 × 14 grid of squares in the next scene's colour, each with its own random onset inside 0.2 s, then the same in reverse to reveal; seeded, so it's a pure function of time.
5. **Music and voice:** `mix.py` with the new track (no time-stretch, 128.00 BPM), the new start point, the break high-pass, the ending, the new VO placements and ducking, the denser UI sounds, then mastering.
6. **Render:** `render.js` with 12 subframes per frame (as v3), out at 60 fps; mux with AAC 256 kbps.
7. Render one frame per beat before the full render. Fix anything off the grid, cramped, hard to read or overlapping.
</build>

<gotchas>
- **Settled numbers:** sizes never roll; they cross-fade or step once per beat. v3's rolling digits smeared under motion blur.
- **One photo per file:** `IMG_2041.HEIC`, `hero.png`, the Remove BG subject and `launch.mov` each use a different photo.
- **Captions vs speech:** a caption shows exactly the words Emma says (or, where she's silent, a short phrase of its own). Never different words at the same time as her line.
- **UI accuracy:** the arc faces into the screen (the bubble is on the right edge, the arc opens left); option bubbles never cross the frame edge; labels show inside the bubble.
- **Numbers agree:** 12.4 MB → 486 KB is −96%; 6.1 MB → 412 KB is −93%; 840 MB → 24.1 MB is −97%.
- **Voice timing:** no line runs into the next line's beat.
- **Clean ending:** the last 3 s are a still end card in silence.
</gotchas>

<start>
Show the owner this beat grid (done in chat, 2026-11-02). When they approve and v3 plus the photos are here, build, check stills, render and send.
</start>

## VO placement on the new grid
Lines 1–9 from `audio/emma-vo-full.mp3` (source times in `HANDOFF-VIDEO.md`); A and B from `audio/emma-vo-extra.mp3`.

| # | Line | Starts (bar.beat) | Film time (s) | Ends |
|---|---|---|---|---|
| 1 | Your files are too heavy. | 1.2 | 0.469 | 2.24 |
| 2 | Meet Droptimize. | 3.2 | 4.219 | 5.37 |
| A | Drag from anywhere. Finder, Photos, or the web. | 4.1 | 5.625 | 9.43 ("Finder" 7.39, "Photos" 8.08, "web" 9.04) |
| 3 | Drop any photo or video on the bubble. Done. | 6.3 | 10.313 | 13.53 ("Done." at 13.23, with the check) |
| 4 | Convert to WebP or AVIF in one move. | 9.2 | 15.469 | 18.62 |
| 5 | Lift the background right out. | 12.2 | 21.094 | 22.69 |
| 6 | Videos too, down to whatever size you need. | 14.2 | 24.844 | 27.67 |
| 7 | All on your Mac. Nothing uploaded. | 17.2 | 30.469 | 32.69 |
| B | No internet needed. | 18.4 | 33.281 | 34.56 |
| 8 | Batches in one drop. Already on your clipboard. | 20.2 | 36.094 | 39.11 |
| 9 | Droptimize. Drop it. Done. | 23.1 | 41.250 | 43.62 |

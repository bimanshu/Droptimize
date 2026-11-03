# Launch film v4 (Shotbase style): handoff

> Read this to continue **v4**. It sits beside `HANDOFF-VIDEO.md` (v1–v3, kept on the owner's office Mac) so the two copies can't clash in git. The plan is `PROMPT-v4.md`; the reference is `reference-shotbase.md`. **Keep this file current** after every change you push.

## Where it stands (2026-11-03)
- [x] **Reference studied:** Shotbase's product film (`reference-shotbase.md`). Owner: "I want mine like this."
- [x] **Owner's decisions:** captions plus Emma; about 45 s (now 48.75 s + 3 s still end card, because of the two new lines); music Mixkit 160 "Minimal Emotion" (owner: "go with minimal emotion"); built in the cloud session.
- [x] **Two new lines** (owner asked for "no internet needed" and "drag from anywhere: Finder, Photos, web"): one take, 80 credits, `audio/emma-vo-extra.mp3`. **Don't generate any more voice without asking.** Credits so far: 131 + 131 + 427 + 80 = 769, all within the Starter plan.
- [x] **Plan:** `PROMPT-v4.md` (26 bars at 128 BPM, scene by scene, Emma's placements).
- [x] **Built:** `film/v4.html` (picture), `film/render-v4.js` (stills, cue list, parallel subframes, encode), `film/mix-v4.py` (soundtrack; imports `mix.py`'s tools). All new files, so nothing of v1–v3 changed.
- [x] **Checked:** one still per beat (111) plus every transition; fixes so far: caption placement clear of cards and panels, windows side by side, the camera keeping the bubble in frame on the pull-back, the dissolve layers, the holds after "Done." and after Remove BG now move, the batch fanning out, a bigger composer, bigger pills and keycaps.
- [x] **Soundtrack:** music from the track's bar 15 (26.681 s), so its break is film bar 2 and its drop lands on the reveal (3.75 s); the grid lines up exactly (onset fold: 0 ms). Mastered −14.2 LUFS, −1.2 dBTP.
- [ ] **First render with stand-in photos** (in progress): sent to the owner to judge motion, timing and sound.
- [ ] **The owner's photos.** The film uses **stand-ins** (soft placeholder images made with PIL) until the owner uploads theirs. Needed in `film/images/` (git-ignored), any 16:9 size:
  - `photo.webp`: `IMG_2041.HEIC` (v3: a daisy).
  - `hero.webp`: `hero.png`, the image on the web page (v3: a cat under the moon).
  - `product.webp` and `product-cutout.png`: `statue.jpg`, the Remove BG subject, and its cut-out on transparency (v3: a blue statue; the cut-out comes from `cutout.swift` on a Mac with Apple Vision). Both must be the same size.
  - `video.webp`: **new**, the still for `launch.mov`, so no photo is used for two files.
  - Then re-render (below) and resend.
- [ ] **Owner's feedback** on the v4 cut.

## Still waiting on the owner
1. **Push v3 from the office Mac** (it isn't on GitHub: `encode.swift`, `cutout.swift`, the v3 `index.html` and `HANDOFF-VIDEO.md`). v4 doesn't need it to render, but the repo should hold it.
2. **The four photos** (above). Photos they may use commercially; the imageory.in samples have no licence.
3. **The website URL** for the end card, once there is one.

## How v4 is built (from `docs/launch-video/film/`)
```bash
curl -fsSL -o 160.mp3 https://assets.mixkit.co/music/160/160.mp3
node render-v4.js stills stills/ 3.8 13.3 24.6              # check moments (no times: one per beat)
node render-v4.js events events-v4.json
python3 mix-v4.py --music 160.mp3 --events events-v4.json --out mix-v4.wav   # ~15 s; prints loudness
node render-v4.js frames sub/ 4 8                           # 24,840 subframes (8 per frame), 4 pages, resumable
node render-v4.js encode sub/ video-v4.mp4 8                # blends each frame's 8 subframes → 60 fps H.264
ffmpeg -i video-v4.mp4 -i mix-v4.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -movflags +faststart droptimize-launch-v4.mp4
```

## Design notes (v4)
- **Desk:** a Mac desktop in points (1440 × 900); the camera maps points to pixels (`CAMK`: time, scale, centre, springs; scale and pan can have different springs so the bubble stays in frame). The bubble is docked at (1404, 450); menu geometry and option labels are the app's own (`ActionOptions.swift`: 100K…2M, WebP/AVIF/JPG/PNG/HEIC, checkerboard/white/black/eyedropper, 10M…100M; video segments Convert/Compress/Resize/Mute).
- **Screen scenes:** cold open, Photos/Videos pills, the laptop, the keycaps, the composer and the end card are drawn in pixels; pixel dissolves at 3.75, 33.75 and 39.375 s; blur dissolves and zoom-throughs elsewhere.
- **Captions:** Geist 600, 64 px, word by word from Emma's measured word onsets (`words(...)` in `v4.html`), one word in a mint box; menu scenes put them high on the left, clear of the card.
- **Wallpaper:** our own (canvas waves in blue, teal and a touch of mint, blurred), never Apple's.
- **Glow:** only the first result card's edge and the end-card logo.

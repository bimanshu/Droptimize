# Launch film v4 (Shotbase style): handoff

> Read this to continue **v4**. It sits beside `HANDOFF-VIDEO.md` (v1–v3, kept on the owner's office Mac) so the two copies can't clash in git. The plan is `PROMPT-v4.md`; the reference is `reference-shotbase.md`. **Keep this file current** after every change you push.

## Where it stands (2026-11-03)
- [x] **Reference studied:** Shotbase's product film (`reference-shotbase.md`). Owner: "I want mine like this."
- [x] **Owner's decisions:** captions plus Emma; about 45 s (now exactly 45 s + 3 s still end card); music first Mixkit 160 "Minimal Emotion", now **Mixkit 175 "Digital Clouds"** (owner, 2026-11-03); built in the cloud session.
- [x] **Two new lines** (owner asked for "no internet needed" and "drag from anywhere: Finder, Photos, web"): one take, 80 credits, `audio/emma-vo-extra.mp3`. **Don't generate any more voice without asking.** Credits so far: 131 + 131 + 427 + 80 = 769, all within the Starter plan.
- [x] **Plan:** `PROMPT-v4.md` (26 bars at 128 BPM, scene by scene, Emma's placements).
- [x] **Built:** `film/v4.html` (picture), `film/render-v4.js` (stills, cue list, parallel subframes, encode), `film/mix-v4.py` (soundtrack; imports `mix.py`'s tools). All new files, so nothing of v1–v3 changed.
- [x] **Checked:** one still per beat (111) plus every transition; fixes so far: caption placement clear of cards and panels, windows side by side, the camera keeping the bubble in frame on the pull-back, the dissolve layers, the holds after "Done." and after Remove BG now move, the batch fanning out, a bigger composer, bigger pills and keycaps.
- [x] **Soundtrack:** Digital Clouds from its bar 15 (26.134 s), stretched from 129 to 128 BPM, so its bass lift lands on the reveal (3.75 s) and its quieter bars fall in the dark scene; on the grid within 5 ms. Mastered −14.2 LUFS, −1.3 dBTP.
- [x] **First render with stand-in photos** (2026-11-03): `droptimize-launch-v4.mp4`, 51.75 s, 1920×1080 at 60 fps, 3,105 frames, 18.3 MB, −14.3 LUFS, −1.2 dBTP; 8 subframes per frame (24,840 renders, ~23 min with 4 pages, then ~5.5 min to encode). Checked on 22 frames of the final file; sent to the owner. Not in git.
- [x] **Owner's feedback on the first cut (2026-11-03):** "this is cool".
  1. **"At 0:14 after Done there's a big gap to the next voice, and a mismatch between video and voice":** 4.3 s with no voice, and a caption ("Straight off the web.") that Emma never says. Fixed: Convert moved up a bar and a beat (her line now 1.9 s after "Done."), the held bar after Remove BG came out (the film is 24 bars, 45 s), and **no caption appears without her voice** any more. The longest gap between lines is now 2.8 s.
  2. **"Add real images; I don't like the background illustration":** the owner said to use any Unsplash or Pexels photos, "but not the most common, pick a non-common image". Unsplash's search sits behind a bot check (not bypassed); Pexels pages were found by web search and the files fetched from `images.pexels.com`. Picked: misty blue-hour ridges (the desktop background, replacing the drawn waves), a dog on a beach at dusk, a rainy street at night, sea cliffs from above, and a pineapple on navy (the Remove BG subject, renamed `pineapple.jpg`; the statue is gone). **`film/prepare-images-v4.py`** downloads and prepares them (crops, the background's grade, and the pineapple's cut-out keyed by hue, since there's no Apple Vision here). Pexels licence: free commercial use, no credit needed; page links are in the script.
- [x] **Second render** (2026-11-03): `droptimize-launch-v4b.mp4`, 48.0 s (45 s + 3 s still), 1920×1080 at 60 fps, 2,880 frames, 23.3 MB, −14.2 LUFS, −1.3 dBTP; checked on 20 frames of the final file and the soundtrack rebuilt byte-identical from the final cue list. Sent to the owner. Not in git.
- [x] **Music exploration (owner: "can we explore some other music tracks", 2026-11-03).** **The owner picked #2, Digital Clouds** ("I like the second one"); it's now `mix-v4.py`'s default, and the final film with it, `droptimize-launch-v4c.mp4` (1080p60, 48 s, 23.3 MB, −14.2 LUFS), was sent. Five Mixkit tracks (same free licence) previewed **in the film** as 720p cuts (only the soundtrack changes, so no re-render: `mix-v4.py --bpm <tempo> --start <source s>` then mux with the rendered video). Each is stretched to 128 BPM and started so a lift lands on the reveal (3.75 s); all sit within 15 ms of the grid:
  | # | Track (Mixkit id) | Measured BPM | `--start` (s) | Character |
  |---|---|---|---|---|
  | 1 | Slow Trance Morning, A. M. (123) | 123.98 | 42.531 | melodic, dreamy; steady bass, no big drop |
  | 2 | Digital Clouds, A. M. (175) | 129.00 | 26.134 | airy chillout; bass lifts on the reveal; a dip in the dark scene |
  | 3 | Cat Walk, Arulo (371) | 130.02 | 9.860 | groovy house; the bass enters right on the reveal |
  | 4 | Rising Forest, Diego Nava (471) | 123.94 | 41.304 | uplifting house; a breakdown, then the drop on the reveal |
  | 5 | Minimal Techno 01, A. M. (162) | 127.98 | 41.460 | driving tech house; steady |
  The earlier track was Minimal Emotion (160), 128.00, 26.681. Downloads: `https://assets.mixkit.co/music/<id>/<id>.mp3`.
- [ ] **Gradient back (owner, 2026-11-03):** "I liked the previous gradient bg, can we move back to that bg, nothing else should change". Done in `v4.html` (only the background lines changed; the files' photos, timing, Digital Clouds and the voice are the same); render `droptimize-launch-v4d.mp4` in progress.
- [ ] **Owner's feedback** on the gradient version.

## Still waiting on the owner
1. **Push v3 from the office Mac** (it isn't on GitHub: `encode.swift`, `cutout.swift`, the v3 `index.html` and `HANDOFF-VIDEO.md`). v4 doesn't need it.
2. **The website URL** for the end card, once there is one.

## How v4 is built (from `docs/launch-video/film/`)
```bash
python3 prepare-images-v4.py                               # the four photos into images/ (git-ignored)
curl -fsSL -o 175.mp3 https://assets.mixkit.co/music/175/175.mp3
node render-v4.js stills stills/ 3.8 13.3 24.6              # check moments (no times: one per beat)
node render-v4.js events events-v4.json
python3 mix-v4.py --music 175.mp3 --events events-v4.json --out mix-v4.wav   # ~15 s; prints loudness
node render-v4.js frames sub/ 4 8                           # 23,040 subframes (8 per frame), 4 pages, resumable, ~22 min
node render-v4.js encode sub/ video-v4.mp4 8                # blends each frame's 8 subframes → 60 fps H.264
ffmpeg -i video-v4.mp4 -i mix-v4.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -movflags +faststart droptimize-launch-v4.mp4
```

## Design notes (v4)
- **Desk:** a Mac desktop in points (1440 × 900); the camera maps points to pixels (`CAMK`: time, scale, centre, springs; scale and pan can have different springs so the bubble stays in frame). The bubble is docked at (1404, 450); menu geometry and option labels are the app's own (`ActionOptions.swift`: 100K…2M, WebP/AVIF/JPG/PNG/HEIC, checkerboard/white/black/eyedropper, 10M…100M; video segments Convert/Compress/Resize/Mute).
- **Screen scenes:** cold open, Photos/Videos pills, the laptop, the keycaps, the composer and the end card are drawn in pixels; pixel dissolves at 3.75, 30.0 and 35.625 s (the squares take the gradient's colours); blur dissolves and zoom-throughs elsewhere.
- **Captions:** Geist 600, 64 px, word by word from Emma's measured word onsets (`words(...)` in `v4.html`), one word in a mint box; menu scenes put them high on the left, clear of the card.
- **Wallpaper:** the drawn gradient (canvas waves in blue, teal and a touch of mint, blurred), a dark version for the opening and the keycaps; never Apple's. The owner tried a landscape photo in the second cut and asked for the gradient back (2026-11-03: "I liked the previous gradient bg… nothing else should change").
- **Glow:** only the first result card's edge and the end-card logo.

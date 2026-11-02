# Reference: the Shotbase product film (owner, 2026-11-02: "I want mine like this")

The owner sent Shotbase's launch film ("The capture tool your Mac should have had", 58.2 s, 1280×720 at 60 fps; the file was a download, not committed) and asked for the Droptimize film to be like it. This is what it does, measured from the file, frame by frame (one frame a second, and full-size frames at key moments).

## Story and pacing
- **58 s, about 7 s per idea**, with long continuous camera moves; only 7 hard cuts (6.2, 15.6, 16.9, 48.6, 49.3, 52.1 s). Ours is 28.5 s for eight ideas, which is why it feels rushed next to it.
- **No voice-over.** On-screen captions tell the story as one running sentence across scenes: "You … screenshot … your screen" → "or you just paste" (a URL) → "no digging through folders" → "Static / Motion" → "When you're done … Share you're done" → "Every screenshot … it all lives together … in one place" → "Shotbase" → "Capture beautifully. Share instantly."
- Order: shortcut keys (⇧⌘5) → toolbar → capture → annotate ("blur this", red arrow) → background picker → 3D-tilted result → static/motion → video editor timeline → webcam recording → share into a chat → library → logo.

## Look
- **Macro camera.** The camera sits right on the UI: the toolbar fills ~70% of the frame width, the cursor is huge (~150 px tall at 1080p) and in motion blur, and the edges fall out of focus (shallow depth of field, rack focus between elements).
- **Backgrounds:** a blurred macOS wallpaper (blue and teal waves) for the opening; clean white with soft shadows for most scenes; real dark content (websites, a photo, a forest wallpaper) inside the UI; a near-black end card with a soft blue glow and a faint pixel grid.
- **Captions, not headlines.** Sentence case, a semibold SF-style sans at roughly 60–70 px on 1080p (much smaller than our 144 px headlines), centred on the UI they talk about, arriving word by word with a blur. One word per caption is in the brand blue ("through", "done"), or sits in a blue highlight box ("screenshot").
- **Real product UI at full fidelity**, with real content in it (real web pages, a real person on webcam, real wallpapers), never placeholder boxes.
- **Transitions:** blur dissolves, a pixel/mosaic dissolve (32 s, 50 s), a 3D perspective tilt with a glowing edge (20 s), zooms through the UI, the logo blurring into focus (52 s).
- **Big, tactile objects:** close-up keycaps with a soft glow (0–1 s), giant pill buttons clicked by the giant cursor (22–23 s).

## Sound
- **About 129 BPM** (beat 0.464 s), electronic and bright: a sustained synth note around 700–800 Hz runs through, with a short gap every 16 beats (~7.4 s: at 1.3, 10.3, 17.9, 25.2, 32.5, 39.9, 45.5 s) that marks each section.
- **Dense UI sound effects** (clicks, ticks) on every action; sub-heavy (20–60 Hz sits +3 dB over the mids), top end rolled off (5–10 kHz −13.5 dB).
- **Mastered loud:** about −9 to −10 dBFS RMS through the body (far louder than our −14 LUFS); fades out over the last 3 s.

## What it means for Droptimize (the mapping)
| Shotbase | Droptimize |
|---|---|
| ⇧⌘5 keycaps open the film | A file being dragged; or the ⌘V keycaps saved for the end |
| The toolbar, macro, on a blurred wallpaper | The bubble and radial menu, macro, on a blurred macOS wallpaper |
| "You screenshot your screen" | "You drop a photo … on the bubble" |
| "or you just paste" a URL | Drag from anywhere: Photos, a web page, Mail |
| Annotate, background picker | Compress to a size, convert to WebP/AVIF, Remove BG |
| Static / Motion pills | Photos / Videos |
| Video timeline | Video compress to "Under 25 MB", the ring filling |
| Share into a chat | Already on the clipboard: ⌘V into a chat |
| "it all lives together in one place" | "Never leaves your Mac. No internet needed." |
| Glowing logo on near-black | The Shrink logo on near-black, mint glow |

## The owner's decisions for the new film (2026-11-02)
- **Voice:** captions **and** Emma. The captions carry the key words of each line, timed to her delivery; Emma's existing take is re-placed for the new edit (no new ElevenLabs credits unless the words change, and then ask first).
- **Length:** about **45 s** (24 bars at 128 BPM is exactly 45.0 s), plus the silent end-card hold.
- **Music:** a new, brighter track: **Mixkit 160 "Minimal Emotion"** (the owner chose it from three previews: "go with minimal emotion") by Alejandro Magaña (A. M.), techno, `https://assets.mixkit.co/music/160/160.mp3`, 2:00, Mixkit Stock Music Free License. Chosen by comparing the band-by-band average spectrum and punch of all 172 Mixkit candidates with Shotbase's soundtrack: it's the closest match. Measured: **exactly 128.00 BPM** (no stretch), first beat 0.431 s, bar 1.875 s. Shape: bars 1–15 groove with bass; **bar 16 a break (bass drops out); bar 17 the drop** (louder, fuller); bars 17–56 groove; outro from bar 57. Runners-up previewed to the owner: 334 "Night Terrors" (EDM, 130.04 BPM) and 175 "Digital Clouds" (chillout, 129.02 BPM).
- **Plan:** `PROMPT-v4.md` (the beat grid, waiting for the owner's OK).
- **Where:** built in the cloud session, **starting from the third cut (v3)**, once the office Mac has pushed v3 and the owner has uploaded the photos (v3's stand-ins plus any new ones). The new film should still fix v3's two issues: the smeared rolling digits in the cold open, and the same daisy photo used for two files.

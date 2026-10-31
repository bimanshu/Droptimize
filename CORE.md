---
name: droptimize
description: The living source of truth for Droptimize, a native macOS utility where you drag an image or video onto a small floating bubble, let go on a radial menu (convert, compress, resize, remove background), and get a smaller, web-ready file back instantly. Use this skill for ANY work on Droptimize, including Swift/SwiftUI/AppKit code, the floating panel, the radial menu and its motion, drag and drop, the image and video pipelines, encoders (jpegli, MozJPEG, libwebp, libavif, pngquant, oxipng, AVFoundation, FFmpeg), perceptual auto-tuning (SSIMULACRA 2, VMAF), background removal with Vision, licensing, packaging, notarization, benchmarks, naming and launch copy, even when the request doesn't say "Droptimize" but clearly continues this project (the bubble, the drop tool, Blip, the image optimizer). Read it before writing code so every part follows the same rules, and update the Status and Changelog sections whenever something ships or a decision changes.
---

# Droptimize

> **Drop it. Done.** Drag any image or video onto a small bubble on your screen, let go on what you want (WebP, compress, half size, remove background), and the optimized file is on your clipboard before you've moved your hand.

Working name: **Droptimize** (also considered: Blip, Ripple, Halo, PixDrop). If it changes, it's one find-and-replace.

## How to use and update this file

- **Start with `HANDOFF.md`**: it says where the work stands right now and what's next. This file is the spec and the rules.
- Read the relevant section before building. **Rules** (§3) are decisions, not suggestions; change them only on purpose and record why in the Changelog.
- After each work session, update **Status** (§1) and add one line per change to **Changelog** (§14), newest first.
- Keep this file under ~500 lines. When a section grows past ~60 lines, move detail to `references/<topic>.md` and leave a pointer here.
- Values marked *(tune)* are starting points. Expose them as named constants and adjust by feel and by benchmark, not by guess.

---

## 1. Status

| Area | State | Notes |
|---|---|---|
| Phase 0: app shell, bubble, radial menu (dummy actions) | Code complete; needs hands-on tuning on a Mac | Builds and passes tests in CI; DMG on the `preview` release. Feel not yet tuned by a person; see HANDOFF.md |
| Phase 1: image pipeline | Steps 1 and 4 done, step 2 half done (WebP, AVIF, Compress incl. target sizes, Half size, Remove BG with backgrounds, naming, size guard, clipboard) | libwebp; libaom + libavif; own lossless PNG optimizer; ImageIO for JPEG/HEIC until jpegli; Vision for Remove BG. Next: Auto classification and the full PNG pipeline (step 2), auto-tune (step 3) |
| Phase 1.5: benchmark, polish, launch clip | Not started | |
| Phase 2: video pipeline | Steps 1–4 done with AVFoundation only (remux, H.264/HEVC, compress to a size, resize, mute, GIF) | No new dependencies. Next: WebM and FFmpeg "max quality" + VMAF, which need the owner's OK on FFmpeg or libvpx (§13) |
| Phase 3: signing, notarization, distribution | Not started | |

---

## 2. The problem and the idea

Optimizing an image for the web is a detour: open TinyPNG or Squoosh, upload, pick a format, fiddle with a slider, download, find the file in Downloads, drag it to where you actually needed it. Video is worse (HandBrake presets, giant `.mov` screen recordings).

The tools that inspired this all kill a detour. CleanShot X keeps the screenshot floating where you're already looking. Unhook removes what pulls you off-task. A radial "convert" menu turns five steps into one drag. Droptimize does that for media optimization.

**Who it's for:** web designers and developers, people who post design work (X, Dribbble, Slack, GitHub READMEs), anyone who uploads images to the web.

**The edge is the feel, not the feature list.** Optimizers already exist (ImageOptim, Squoosh, TinyPNG). The ones people love feel instant and obvious. Interaction polish is product work here, not decoration.

---

## 3. Rules

1. **Never leave the user's context.** No windows to manage in the core flow. Drop → result. Images go to the clipboard; videos appear as a draggable thumbnail on the bubble. Both are also saved next to the original.
2. **Never touch the original.** Always write a new file. Never overwrite; on a name clash append `-2`, `-3`.
3. **Never hand back a bigger file.** If the output is larger than the input (or saves less than ~1%, *tune*), keep the original and say "Already as small as it gets." Exceptions, agreed with the owner: **Convert** into another format, and **Remove BG**. They do what was asked even when the result is bigger. The video equivalents (Convert to MP4, HEVC or GIF, and **Mute**) follow the same reasoning.
4. **Everything on-device.** No network calls, no accounts, no analytics in v1. Works offline, costs nothing per use. Privacy is a selling point.
5. **The bubble never stutters.** Decoding, encoding and analysis all run off the main thread. The UI reacts to a drag within one frame.
6. **Quality is measured, not guessed.** "Looks the same" means a perceptual metric score (§6.4, §7.3), not a fixed quality number.
7. **License-check every dependency before adding it** (§8). Ask the user before adding anything GPL or AGPL.
8. **Respect the system.** Light and dark mode, Reduce Motion, VoiceOver labels on the bubble and every segment.

---

## 4. Interaction spec

### 4.1 The bubble (idle)

- A small circle (~44pt, *tune*) docked near a screen edge. Default: right edge, vertically centered.
- Lives in an `NSPanel`: borderless, `.nonactivatingPanel` (never steals focus from the app you're in), floating level, `collectionBehavior` with `.canJoinAllSpaces` and `.fullScreenAuxiliary` so it's on every desktop and over full-screen apps. `hidesOnDeactivate = false`, clear background.
- Quiet when idle: reduced opacity (~0.6, *tune*), soft shadow. Full opacity on hover.
- Drag the bubble itself to move it; it springs to the nearest **left or right** edge (top has the menu bar, bottom usually the Dock) and remembers its position per display.
- Nice-to-have: when a file drag starts *anywhere* on screen, the bubble wakes up (grows slightly, glows) so it's easy to find. This needs a global mouse monitor plus a look at the drag pasteboard; check what permission macOS asks for before relying on it (§13).

### 4.2 The radial menu (while dragging over)

- When a drag carrying image or video files enters the bubble, the panel **expands** (keeping the bubble's center fixed) and segments fan out with a short stagger (~20–30ms each, *tune*). Expanding the panel matters: segments must be real drop targets inside the window.
- Segments sit on an **arc facing into the screen** (160°, *tune*), not a full ring, because the bubble is always docked to an edge. They're ordered top to bottom. The ring grows if there are 6 segments so neighbours never touch.
- Hovering a segment highlights it, shows its one-word label **inside the bubble** (the drag image under the pointer would cover a label on the segment), and gives a light trackpad haptic (`NSHapticFeedbackManager`, `.alignment`). Beyond the center, segments are picked by angle (pie-menu style), which is forgiving at drag speed.
- **Drop on the center = Auto.** Drop on a segment = that action. Drag back out without dropping = collapse.
- Maximum 6 segments; more becomes unreadable at drag speed. Icons are SF Symbols.
- **Option bubbles:** some segments have a second ring of smaller bubbles (max 6) that fan out beyond them while hovered. Dropping on the segment itself does its default; dropping on an option picks it. Options are centered on their segment but kept within 85° of straight into the screen. **Compress:** 100 KB · 250 KB · 500 KB · 1 MB · 2 MB · Custom. **Remove BG:** None (transparent) · White · Black · last custom color · Custom. You can't type mid-drag, so **Custom** opens a small panel beside the bubble after the drop (a size in KB/MB, or a hex color with swatches and an eyedropper). It takes the keyboard without activating the app.

Image segments, top to bottom: **Convert · Compress · Half size · Remove BG** (center: **Auto**), leaving one slot free. Convert's option bubbles: **WebP · AVIF · JPG · PNG · HEIC** (only formats that web pages and uploads take; no general-purpose conversion).
Video segments, top to bottom: **Convert · Compress · Resize · Mute** (center: **Auto**, a smaller H.264 MP4), mirroring the image menu. Convert's option bubbles: **MP4 · HEVC · GIF** (WebM waits on §13). Compress: **10 MB · 25 MB · 50 MB · 100 MB · Custom** (common upload limits). Resize: **1080p · 720p · 480p** (the short side).

- Mixed drops (images and videos): show only actions that apply to both (Auto, Compress, without option bubbles).
- Several files: one batch, same action for all.

### 4.3 Working → done

- **Working:** a progress ring around the bubble; batches show a count ("3/12"). Click to cancel.
- **Done:** a checkmark on the bubble, and a small card beside it (on the side facing into the screen) with a thumbnail of the result and the saving ("−68%"). It rests there for a few seconds (~4s, *tune*), longer while hovered. Drag the card into any app (Finder, Figma, Slack, a browser upload). Click it to reveal in Finder.
- **Errors:** a gentle shake and one short line in a pill beside the bubble, for example:
  - "Already as small as it gets." (size guard)
  - "Couldn't find a clear subject." (background removal)
  - "Can't open this file type yet."
- Jobs longer than ~10s (mostly video) also post a system notification when done.

### 4.4 Menu bar

An icon with: Show/Hide bubble (plus a global shortcut), **History…** (a window listing every file made: thumbnail, action, before → after size, date; reveal, drag out, copy, remove, clear; kept on this Mac only, max 500), Recent (last 10 outputs, click to reveal), Settings, Quit.

### 4.5 Motion

- Springs everywhere, no linear tweens. Starting point: response 0.35, damping 0.75 (*tune*).
- Every motion and sizing constant (sizes, springs, stagger, durations, opacities) lives in `Motion.swift`, so the feel can be tuned in one place.
- On drop, a quick ring ripples out from the drop point as work begins.
- With Reduce Motion on: fades instead of scale and fan-out, no stagger, no ripple.

---

## 5. Tech stack and architecture

- **Swift + SwiftUI** for views; **AppKit** where SwiftUI falls short (the `NSPanel`, drag-destination details, pasteboard, haptics). Latest stable Xcode.
- **Minimum macOS 14 (Sonoma)**, required for Vision's foreground mask (§6.5). Build universal (Apple Silicon + Intel).
- **XcodeGen** (`project.yml`) generates the Xcode project so everything builds from the command line with `xcodebuild`. Commit `project.yml`, not the generated `.xcodeproj`.
- **Concurrency:** Swift concurrency. A `JobQueue` actor runs jobs with a limit (images: number of performance cores; video: one at a time). Every job is cancellable.
- **Distribution:** direct download with Developer ID and notarization, **not** the Mac App Store, for v1. The App Store sandbox makes "save next to the original" and bundled encoders much harder. Revisit later.

Structure (current; `HANDOFF.md` has a one-line description of every file):

```
Droptimize/
├── project.yml     XcodeGen spec (the .xcodeproj is generated, not committed)
├── CORE.md         this spec · HANDOFF.md where work stands · CLAUDE.md agent instructions
├── App/            DroptimizeApp.swift, AppDelegate.swift, MenuBar.swift, HotKey.swift (Settings.swift in Phase 1)
├── Bubble/         BubblePanel, BubbleHostView (all events), BubbleController (state machine),
│                   BubbleModel, BubbleView, RadialMenu, BubbleLayout, DockPosition, Spring,
│                   PanelMover, Thumbnails, Motion.swift
├── Pipeline/       Action.swift, MediaKind+Files.swift, Job.swift, FakeJobRunner.swift (Phase 0 only)
│                   Phase 1 adds JobQueue.swift, Output.swift (naming, clipboard, saving)
├── Image/          (Phase 1) Decode.swift, Normalize.swift, Classify.swift, AutoTune.swift, BackgroundRemoval.swift
│   └── Encoders/   JPEG.swift, WebP.swift, AVIF.swift, PNG.swift
├── Video/          (Phase 2) Probe.swift, Remux.swift, AppleEncoder.swift, FFmpegEncoder.swift, GIF.swift
├── Metrics/        SSIMULACRA2.swift, VMAF.swift
├── Vendor/         prebuilt static libraries and headers (§8)
├── bench/          benchmark corpus (§9)
├── scripts/        check-linux.sh; later build-deps.sh, benchmark.sh
├── .github/        workflows/build.yml (macOS CI: build, test, universal Release, zipped app)
└── Tests/
```

---

## 6. Image pipeline (Phase 1)

### 6.1 Input

Decode with ImageIO: JPEG, PNG, HEIC, WebP, AVIF, TIFF, GIF (first frame only in v1), BMP. SVG and PDF are out of scope for v1.

### 6.2 Normalize (before any encode)

- Apply EXIF orientation to the pixels, then drop the orientation tag.
- Convert to **sRGB**. Display P3 and other profiles can look washed out or oversaturated in browsers. Output is tagged sRGB or untagged, never the original exotic profile.
- **Strip metadata** by default (camera info, GPS, embedded thumbnails). A setting keeps it.
- Preserve alpha exactly. Flatten onto white only when the target can't hold alpha (JPEG), and tell the user.

### 6.3 Encoders

Use the same open-source engines the best tools use. Quality comes from them plus the tuning in §6.4.

| Format | Engine | Notes |
|---|---|---|
| JPEG | **jpegli** (from libjxl), fallback MozJPEG | Progressive; 4:2:0 chroma for photos, 4:4:4 for graphics and text. **Now:** ImageIO (progressive, quality 0.8) as a stand-in |
| WebP | **libwebp** | Lossy for photos; for graphics try lossless and lossy, keep the smaller |
| AVIF | **libavif + libaom** | 8-bit for compatibility; encoder speed ~6 for interactive use (*tune*); 4:4:4 for graphics. **In use** (quality 60, speed 6; alpha lossless) |
| PNG | **pngquant** (lossy palette) → **oxipng** (lossless) | Skip pngquant when it can't hit the quality target; license note in §8. **Now:** our own lossless optimizer (`Image/Encoders/PNG.swift`: palette/gray/RGB reduction, adaptive filters, zlib 9) until free vs paid is decided |

### 6.4 Auto-tune (how we beat fixed presets)

Most tools apply one quality number to every image. Instead, per image:

1. Encode at a candidate quality.
2. Score it against the normalized original with **SSIMULACRA 2** (higher is closer to the original; roughly 50 = medium, 70 = high, 90 = indistinguishable side by side).
3. Binary-search the quality setting for the **smallest file whose score meets the target**. Cap at ~6 encodes and a time budget (~2s for JPEG/WebP, longer for AVIF, *tune*).
4. Run candidate encodes in parallel across cores where possible.
5. Apply Rule 3 (never bigger than the input).

Quality presets (in Settings; calibrate with the §9 benchmark and by eye):

| Preset | SSIMULACRA 2 target |
|---|---|
| Smaller | 75 |
| **Balanced (default)** | 80 |
| High | 85 |
| Near-lossless | 90 |

### 6.5 Actions

- **Auto (center):** classify the image as photo or graphic/screenshot (unique-colour count, alpha, edge statistics). Photo → lossy WebP, auto-tuned. Graphic → try lossless WebP and PNG (pngquant/oxipng), keep the smaller. WebP is the default because every current browser supports it; a setting lets users prefer AVIF.
- **Convert → WebP · AVIF · JPG · PNG · HEIC:** convert, auto-tuned (each output is the best of its format, not a bloated one). JPG flattens transparency onto white and says so. Converting to the source's own format is a recompress.
- **Compress:** keep the same format, auto-tuned (JPEG → jpegli, PNG → pngquant + oxipng, WebP/AVIF → re-encode). **To a target size** (option bubbles): the best quality that fits, found by bisection; only if the lowest quality is still too big, shrink the image step by step and say so. Named `photo-500kb.jpg`.
- **Half size:** scale to 50% (2x retina export → 1x) with high-quality resampling (vImage), then compress in the same format. A setting allows a custom max width instead.
- **Remove BG:** Vision's `VNGenerateForegroundInstanceMaskRequest` → `VNInstanceMaskObservation.generateMaskedImage(ofInstances: allInstances, from: handler, croppedToInstancesExtent: false)` → save as PNG (through oxipng) or lossless WebP with alpha. **Background choice** (option bubbles): keep it transparent, or lay the subject over white, black or any hex color (then opaque). Named `-nobg` / `-bg`. Remove BG is exempt from Rule 3: it changes content rather than optimizing, so the PNG may be bigger than the original. On-device, free, offline. Works best on people, products, pets and objects with clear edges; weaker on UI screenshots, low-contrast images and busy scenes. No subject found → "Couldn't find a clear subject." Possible later upgrade: an open-source matting model (such as RMBG) converted to Core ML, only if Vision proves not good enough, and only after checking its license.

### 6.6 Output

- **Location:** next to the original (default) or a chosen folder.
- **Naming:** new format → `photo.webp`; same format → `photo-min.png` (suffix configurable); clash → `photo-min-2.png`.
- **Clipboard:** write the output **file URL** *and* a PNG/TIFF image representation, so it pastes as a file in Finder, Slack and browser upload fields, and as an image in Figma and Notes. Test pasting into: Finder, Slack, Figma, a Chrome upload field, Notes, Messages.

---

## 7. Video pipeline (Phase 2)

### 7.1 Input and probe

AVFoundation for MOV, MP4 and M4V; FFmpeg for WebM, MKV and anything AVFoundation can't open. Probe codec, dimensions, frame rate, bitrate, audio and HDR before choosing a path.

### 7.2 Engines

| Mode | Engine | Use |
|---|---|---|
| **Instant re-wrap** | Remux, no re-encode | MOV → MP4 when the stream is already H.264/HEVC: seconds, zero quality loss. Always try first |
| **Fast (default)** | Apple hardware encoders (H.264/HEVC via AVFoundation/VideoToolbox) | Very fast, free, no licensing issues |
| **Max quality** | FFmpeg with libx264 / libx265 (MP4), libvpx-vp9 or SVT-AV1 (WebM) | Smallest files, much slower; check licenses (§8) |

MP4s are always written web-ready (index at the front: `shouldOptimizeForNetworkUse` in AVFoundation, `-movflags +faststart` in FFmpeg) so they play in browsers before fully downloading.

### 7.3 Auto-tune with VMAF

The same idea as §6.4, using Netflix's **VMAF** metric: encode a few short sample clips spread across the video at several quality settings (CRF), score them, pick the setting that meets the target (default VMAF ~95, "Smaller" ~93, *tune*), then encode the full video once. The open-source tool `ab-av1` uses this sample-encode-and-search approach; borrow the idea, and only borrow code if its license fits.

### 7.4 Actions

- **Auto:** MP4 (H.264 for maximum compatibility; HEVC as a setting). Remux if possible, otherwise encode, auto-tuned.
- **MP4 / WebM:** convert.
- **GIF:** two-pass palette (one palette for the clip, then dithered frames that only redraw what changed), up to 30 fps in even steps of the source and ~800px (*tune*). Many platforms convert uploaded GIFs to video anyway, so the done state can suggest MP4 as the smaller option. gifski makes better GIFs but is AGPL (§8).
- **1080p / 720p:** scale down preserving aspect ratio, even dimensions, never upscale.
- **Mute:** drop the audio track (for website hero videos).
- Audio when kept: AAC ~128–160 kbps in MP4, Opus in WebM.
- HDR sources: keep HDR in HEVC; tone-map to SDR for H.264, WebM and GIF.

**Built so far (AVFoundation only, `Video/`):** Auto = H.264 MP4 at ~0.08 bits per pixel per frame, never above 70% of the source's bitrate, size guard on. Convert → MP4 remuxes when the streams are already H.264/HEVC + AAC, else encodes H.264; HEVC encodes at ~0.05 bpp. Compress to a size takes the bitrate from size ÷ duration (8% headroom, AAC 128 kbps), drops to the largest standard size (1080p, 720p, 480p, 360p) that bitrate suits when it is too low for the frame, and retries when the encoder overshoots (lower bitrate, then fewer pixels); the card says "Scaled to 480p to fit". Resize never upscales and keeps even sizes. Mute is a passthrough copy without the audio track. GIF is our own encoder (`Video/GIFEncoder.swift`: one palette per clip by median cut + k-means, Floyd–Steinberg dithering, only changed pixels redrawn, real frame timing), from every frame up to 30 fps, Lanczos-scaled to ≤ 800 px and color-managed to sRGB, the first 30 seconds. Settings in `VideoTuning` (*tune*) until VMAF.

### 7.5 UX differences from images

Video takes time (a 2-minute 4K clip can take a minute or more). Show real progress, keep working in the background, allow cancel, notify when done, and present the result as a draggable thumbnail, since videos don't paste usefully from the clipboard.

---

## 8. Dependencies and licensing

Decide **free/open-source vs paid closed-source** early: it decides which libraries are allowed. This table is a starting point, not legal advice. Verify each license (and patent terms for video codecs) before shipping a paid build.

| Library | Purpose | License (verify) | Fine in a closed-source paid app? |
|---|---|---|---|
| jpegli / libjxl | JPEG encode, SSIMULACRA 2 | BSD-3 | Yes |
| MozJPEG | JPEG fallback | BSD-style (IJG) | Yes |
| libwebp | WebP | BSD-3 | Yes. **In use** (1.6.0, approved 2026-10-30) |
| libavif + libaom | AVIF | BSD-2 (+ AOM patent license) | Yes. **In use** (libavif 1.4.2, libaom 3.15.2, approved 2026-10-30) |
| oxipng | Lossless PNG | MIT | Yes |
| pngquant / libimagequant | Lossy PNG | GPLv3 or commercial | **Only with a commercial license** |
| FFmpeg | Video plumbing | LGPL (GPL if built with x264/x265) | Yes as an LGPL build |
| x264 / x265 | H.264 / HEVC software encoders | GPLv2 or commercial | **Only with a commercial license** |
| libvpx | VP9 | BSD-3 | Yes |
| SVT-AV1 | AV1 | BSD-style (+ AOM patent license) | Yes |
| VMAF | Video quality metric | BSD-2-Clause-Patent | Yes |
| gifski | High-quality GIF | AGPL or commercial | **Only with a commercial license** |
| Sparkle | Auto-updates (Phase 3) | MIT | Yes |
| Apple frameworks (ImageIO, Vision, AVFoundation, VideoToolbox, vImage) | Built in | Apple | Yes |
| zlib (system) | PNG compression | zlib license | Yes (ships with macOS) |

**Paid-app-safe default:** Apple encoders for video, oxipng-only PNG (or a permissively licensed quantizer), FFmpeg built as LGPL.

### Building native dependencies

- `scripts/build-deps.sh` builds pinned versions (checked by SHA-256) as static libraries for arm64 and x86_64, merges them with `lipo`, and puts them in `Vendor/`. It must work from a clean machine. `Vendor/` is generated, not committed: `xcodegen generate` runs the script first, and CI caches it. On Linux it does a host build so the encoders can be tested there. Swift reaches the C libraries through `Modules/module.modulemap`.
- Images: link the C libraries directly. Auto-tune encodes several times per image, so launching a process per encode is too slow.
- Video: FFmpeg can be a bundled binary called via `Process` (common practice), signed with the app.
- Homebrew is fine for experiments, but the shipped app never depends on the user having Homebrew.
- Every bundled binary and library is code-signed for the hardened runtime, or notarization fails.

---

## 9. Benchmark (prove it before claiming it)

- Corpus in `bench/`: ~25 images (photos, screenshots, UI, illustrations, transparent PNGs, gradients, text-heavy). Later ~10 videos (screen recordings, camera footage, motion graphics).
- Compare against Squoosh, TinyPNG and ImageOptim for images; HandBrake presets for video.
- Record output size, SSIMULACRA 2 (or VMAF) and encode time per file.
- `scripts/benchmark.sh` writes a CSV and a Markdown summary table.
- Only claim wins the data supports. An honest table ("same visual quality, X% smaller than Y") is the launch post.

---

## 10. Settings

Auto format (WebP / AVIF) · quality preset · output location · filename suffix · copy to clipboard (on) · keep metadata (off) · video engine (Fast / Max quality) · bubble size and side · launch at login · show/hide shortcut.

---

## 11. Phases and acceptance

**Phase 0: the feel (interaction first, fake actions).**
Menu bar app; floating bubble on all spaces; drag to reposition with edge snap; a file drag enters → panel expands → radial menu fans out; hover highlight + haptic; drop → fake 1s progress → done state with a draggable thumbnail.
*Done when:* it feels right with dummy actions and never steals focus from the frontmost app.

**Phase 1: images**, in this order:
1. Normalize, WebP, Compress (JPEG/PNG), Half size, clipboard, size guard, naming.
2. AVIF, the full PNG pipeline, Auto classification.
3. SSIMULACRA 2 auto-tune and presets.
4. Remove BG.
*Done when:* every action works across the bench corpus, no output is bigger than its input, nothing blocks the UI, and pasting works in every app listed in §6.6.

**Phase 1.5: benchmark, polish, launch.** Run §9, tune targets and motion, record a 10–15s demo clip.

**Phase 2: video**, in this order: remux fast path → Apple encoders (MP4) → resize and mute → GIF → WebM → FFmpeg max quality + VMAF auto-tune.

**Phase 3: ship.** Developer ID signing, notarization, DMG, auto-updates (Sparkle), a simple landing page.

---

## 12. Working rules for Claude Code

- Read this file at the start of a session and build what the current phase says, in order.
- Build after every meaningful change (`xcodegen generate && xcodebuild …`) and fix warnings, not just errors.
- No Mac (for example, a Linux container)? Run `scripts/check-linux.sh` (parse plus portable tests), then push and let CI (`.github/workflows/build.yml`) compile and test on macOS. Never call AppKit/SwiftUI code "working" until CI is green, and never call the feel "done" until a person has tried it.
- Keep pure logic (geometry, naming, size maths) Foundation-only and in the portable lists of `scripts/check-linux.sh`, so it's tested everywhere.
- Keep the main thread free (Rule 5). If something might be slow, it's a job.
- Before adding a dependency, state its license and why it's needed (Rule 7).
- Keep motion and sizing constants in `Motion.swift`; no magic numbers scattered through views.
- Unit-test the pipeline basics: naming and clashes, size guard, orientation, sRGB conversion, alpha preservation.
- When a choice affects licensing, distribution or the interaction feel, ask instead of guessing.
- End of session: update `HANDOFF.md`, update **Status**, add **Changelog** lines, and list anything needing a decision under **Open decisions**.

---

## 13. Open decisions

- Final name (working: Droptimize).
- Free/open-source vs paid (decides pngquant, x264/x265, gifski).
- Auto's default format: WebP (current) or AVIF.
- Whether "wake on any drag" (§4.1) is worth a permission prompt.
- Direct download only, or the Mac App Store later.
- Hovered label inside the bubble (current) or next to the segment?
- Show/hide shortcut: ⌃⌥⌘D for now (⌥⌘D is macOS's Dock toggle). Make it configurable in Settings?
- How to ship oxipng (Rust, no C API): a bundled binary via `Process`, or a different lossless PNG optimizer with a C library?
- WebM and video "max quality": FFmpeg (LGPL build, dynamic linking) or libvpx + libwebm (BSD-3)? Needs the owner's OK (Rule 7). Ties into free vs paid for x264/x265.

---

## 14. Changelog

- 2026-10-31: GIF rebuilt after the owner found ImageIO's output "very bad" (bands, colors breaking, lag): our own GIF encoder (no dependencies) with one palette per clip, dithering, redraw-only-what-changed frames and true timing, fed every frame up to 30 fps (evenly), upright and color-managed by Core Image.
- 2026-10-31: New logo (owner's pick of four concepts): "Shrink", nested circles getting smaller with a solid dot, in place of the drop. Used for the bubble glyph, the menu bar icon and a new app icon (dark tile, mint dot). Geometry in `Bubble/Logo.swift`; icon source `scripts/app-icon.svg`.
- 2026-10-30: Video (Phase 2 steps 1–4) with AVFoundation only, no new dependencies (owner said "do the recommended stuff, don't ask"). The video menu mirrors images: Convert (MP4 · HEVC · GIF), Compress (10/25/50/100 MB · Custom), Resize (1080p · 720p · 480p), Mute; Auto = smaller H.264 MP4. Remux when possible, real per-frame progress, cancel, one video at a time. Video conversions and Mute are exempt from Rule 3 like image conversions. WebM, FFmpeg max quality and VMAF deferred until the owner approves FFmpeg or libvpx.
- 2026-10-30: History window (owner asked for it in the app): menu bar → History… lists every file made with sizes and the saving, with reveal, drag out, copy and clear. Stored in Application Support, local only. The publish step now swaps release files in place; the owner had hit a 404 during the old delete-and-recreate gap.
- 2026-10-30: Menu restructured (owner approved): Convert (→ WebP · AVIF · JPG · PNG · HEIC) replaces the separate WebP and AVIF buttons, freeing a slot. Conversions to another format are exempt from Rule 3. Owner asked "conversions or only optimizations?": decided on conversions only into web/upload formats, always optimized.
- 2026-10-30: AVIF works: libaom 3.15.2 + libavif 1.4.2 (owner approved), built by `scripts/build-deps.sh` with CMake (libavif pinned by commit). The AVIF button converts; Compress, Half size and compress-to-size handle AVIF sources. Video is the only "coming soon" left.
- 2026-10-30: Option bubbles (owner's design): hovering Compress fans out target sizes (100 KB–2 MB, Custom); hovering Remove BG fans out backgrounds (None, White, Black, last color, Custom hex). Built Remove BG with Vision (Phase 1 step 4 brought forward) and compress-to-size (quality bisection, resize only as a last resort). Custom values are asked for in a non-activating panel after the drop. Remove BG is exempt from Rule 3. The bubble now keeps ~180 pt from the screen's top and bottom so the outer ring fits.
- 2026-10-30: One-command install/update for the owner: `curl -fsSL https://github.com/bimanshu/Droptimize/releases/download/preview/install.sh | bash` (`scripts/install.sh`, published with each preview and tested in CI). The app itself still makes no network calls; in-app updates wait for Sparkle (Phase 3).
- 2026-10-30: Phase 1 step 1: real WebP (libwebp 1.6.0; lossy, plus lossless for graphics), Compress (own lossless PNG optimizer; ImageIO JPEG/HEIC), Half size (vImage), normalize (orientation, sRGB, metadata dropped), naming (`-min`, `-half`, `-2`…), size guard, clipboard (file + picture), parallel batches. Replaced the fake runner and the Option-drop test failure. Auto = WebP until classification; AVIF, Remove BG and video say "coming soon". Owner approved libwebp; free vs paid still open.
- 2026-10-30: CI now builds a DMG and publishes it to a `preview` pre-release on every green push, so the owner can try builds without Xcode: https://github.com/bimanshu/Droptimize/releases/download/preview/Droptimize.dmg (owner approved making it public). Not notarized until Phase 3, so the first launch needs `xattr -cr` or Open Anyway.
- 2026-10-30: Phase 0 code complete on branch `claude/fervent-thompson-2620yn`: menu bar app, non-activating floating bubble, edge snapping with a display-synced spring and per-display memory, radial menu with stagger, haptics and Reduce Motion, fake 1s job, done card (drag out or click to reveal), error pill with shake, ⌃⌥⌘D show/hide, unit tests, Linux check script, macOS CI. Builds and passes tests in CI; not yet tried by a person.
- 2026-10-30: Interaction decisions while building Phase 0 (§4): dock to left/right edges only; segments on a 160° arc facing into the screen instead of a full ring (a docked bubble would put half a ring off-screen); hovered label shown inside the bubble; segments picked by angle; results and messages shown beside the bubble. Swift 5 language mode for now, ad-hoc signing until Phase 3.
- 2026-10-30: Added `HANDOFF.md` (where work stands, next steps) and `CLAUDE.md` (agent start/end routine).
- 2026-10-30: Spec created from the planning chat: idea, rules, interaction, image and video pipelines, auto-tune, licensing, benchmark, phases.

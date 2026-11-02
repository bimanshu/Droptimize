# Handoff

> **Read this first, then `CORE.md`.** This file says where the work stands right now and exactly what to do next. `CORE.md` says what we're building and the rules.
> Whoever ends a session updates the ✱ sections before pushing. Keep it current, not historical: history goes in `CORE.md` §14 and the git log.

## ✱ Snapshot

| | |
|---|---|
| Last updated | 2026-11-01 |
| Branch | `claude/fervent-thompson-2620yn` (the only branch so far; no `main` yet, nothing merged, no PR) |
| Phase | **1: WebP, AVIF, Compress (incl. target sizes), Half size and Remove BG (with background choices) work. 2: video works with AVFoundation only** (Convert MP4 · HEVC · GIF, Compress to 10–100 MB, Resize, Mute, Auto). **Freemium built** (free 3 files a day; Pro $5/month or $50 lifetime via Lemon Squeezy), switched off until the store exists. The feel and real-world video haven't been tried by a person yet. |
| CI | [Build workflow](https://github.com/bimanshu/Droptimize/actions/workflows/build.yml): green at `16caa8c` (Xcode 16.4, macOS 15 runner): **178/178 tests** (130 of them also on Linux; including GIF timing, colors and rotation, the free plan, Lemon Squeezy answers, and drags carrying picture data or Finder files), 0 warnings (warnings fail the build), universal libwebp/libaom/libavif and app, install script tested, preview published with freemium (off until `StoreConfig` is set) and drag from any app. The DMG is ~8.8 MB, mostly libaom (video adds nothing: AVFoundation is part of macOS). The first deps build after a `build-deps.sh` change takes ~3 minutes in CI; otherwise it's cached |
| Install / update | One Terminal command: **`curl -fsSL https://github.com/bimanshu/Droptimize/releases/download/preview/install.sh \| bash`** (or the [DMG](https://github.com/bimanshu/Droptimize/releases/download/preview/Droptimize.dmg)). Both come from the [preview release](https://github.com/bimanshu/Droptimize/releases/tag/preview), which CI replaces on every green push. |
| Owner | Doesn't build with Xcode. Updates with the one-line command above (asked for this instead of re-downloading DMGs). Not technical about Terminal: give exact click-by-click steps. |
| Next | Owner sets up Lemon Squeezy and sends the store ID, product IDs and checkout links (Next steps 1), which switch Pro and the free limit on. Owner tries images, video and the new GIFs on real files (Next steps 2). |

## ✱ Where things stand

**Phase 0 (interaction), built:** menu bar app with Show/Hide (⌃⌥⌘D), Recent and Quit; a non-activating floating bubble on every Space; drag to move, springs to the nearest left/right edge and remembers it per display; a file drag fans out the radial menu (inward arc, stagger, haptics, label in the bubble); the done card can be dragged into any app or clicked to reveal in Finder; errors shake and show one line; Reduce Motion fades only; VoiceOver labels everywhere.

**Phase 1 step 1 (`CORE.md` §11), built:**

- **WebP** (Convert → WebP, and the center, **Auto**, until classification): libwebp lossy at quality 80 with sharp YUV. For graphics (transparency, or ≤ 4096 colors in a sample) it also tries lossless and keeps the smaller.
- **Compress** keeps the format. JPEG and HEIC go through ImageIO (JPEG is progressive; jpegli later). PNG goes through our own lossless optimizer, `Image/Encoders/PNG.swift`: palette at 1/2/4/8 bits, grayscale, or RGB when opaque, with adaptive filters and zlib level 9. WebP is re-encoded. TIFF and BMP become PNG. GIF and AVIF say "can't yet".
- **Half size**: vImage Lanczos on premultiplied pixels, then the same format as Compress.
- **Normalize** (`Image/Decode.swift`): first frame, EXIF orientation applied, converted to sRGB, metadata dropped, alpha kept.
- **Output**: a new file next to the original: `photo.webp`, `photo-min.png`, `photo-half.png`, then `-2`, `-3`… Never overwrites (`.withoutOverwriting`). Falls back to Downloads if the folder is read-only. **Never bigger than the input** (≥ 1% saving or "Already as small as it gets.").
- **Clipboard**: every output as a file URL, plus the first as PNG picture data when there's a single file under 30 MP.
- **Batches** run in parallel (performance cores, at most 4). Progress counts files; a single file shows a spinner.
- **AVIF** (Convert → AVIF; added 2026-10-30, owner approved libaom + libavif): libaom 3.15.2 + libavif 1.4.2, 8-bit, tagged sRGB (CICP 1/13/6, full range), 4:4:4 for graphics and 4:2:0 for photos, alpha lossless, no alpha plane when opaque, quality 60 at speed 6 (`EncoderTuning`). The AVIF button converts; Compress and Half size keep AVIF sources as AVIF. Compress-to-size searches at speed 8, then re-encodes the winner at speed 6 and keeps whichever fits. macOS decodes AVIF natively (ImageIO), so libaom's decoder is only used by tests.

**Video (Phase 2, built 2026-10-30 while the owner was away, AVFoundation only, no new dependencies):** MOV, MP4 and M4V get their own menu, mirroring the image one: **Convert** → MP4 · HEVC · GIF · **Compress** → 10 MB · 25 MB · 50 MB · 100 MB · Custom · **Resize** → 1080p · 720p · 480p · **Mute**, with **Auto** in the center.

- **Auto** (and Compress without a size): H.264 MP4 (Compress keeps MOV/MP4/M4V) at ~0.08 bits per pixel per frame, never above 70% of the source's video bitrate, AAC 128 kbps, size guard on (`-min` when the name would clash).
- **Convert → MP4** remuxes (copies the streams, instant and lossless) when they're already H.264/HEVC + AAC, otherwise encodes H.264. **HEVC** encodes at ~0.05 bpp → `-hevc.mp4` (says "This Mac can't encode HEVC video." where there's no encoder). **GIF** (rebuilt 2026-10-31 after the owner said ImageIO's GIFs were "very bad": banding, colors breaking, lag): our own encoder, `Video/GIFEncoder.swift` (portable, no dependencies). One palette for the whole clip (exact colors when there are ≤ 255, else median cut + k-means over a 15-bit histogram), Floyd–Steinberg dithering (serpentine, strength 0.85), and only pixels that changed since they were drawn are redrawn (transparent elsewhere, frame cropped to what moved), so still areas don't shimmer. Frames come from `AVAssetReader` (every frame up to 30 fps, then every 2nd/3rd… so motion stays even), turned upright from the track transform, Lanczos-scaled to ≤ 800 px and color-managed to sRGB by Core Image (`GIFFrameReader`). Delays come from the real timestamps (3, 3, 4 cs at 30 fps); identical frames merge. Two passes (palette, then encode), loops forever, the first 30 seconds (the card says so). About 30 ms per 800 × 450 frame. Conversions are exempt from Rule 3.
- **Compress to a size**: video bitrate = size × 8 × 0.92 ÷ duration − audio. When that's too low for the frame (< 0.03 bpp), it drops to the largest standard size that suits it (1080p … 360p). If the encoder overshoots, it retries: a lower bitrate first, then fewer pixels (`VideoTuning.shortSide(below:pixelShare:)`), up to 4 encodes in all, then "Couldn't get it under 25 MB." The card says "Scaled to 480p to fit". Named `clip-25mb.mov`. "Already under 25 MB." if it is.
- **Resize**: the short side to 1080/720/480, aspect kept, even sizes, never upscales ("Already 720p or smaller."). Named `-720p`.
- **Mute**: passthrough copy without the audio track (`-muted`), exempt from Rule 3. "This video has no sound to remove." if there's none.
- **Engine** (`Video/VideoOptimizer.swift`): `AVAssetReader` (decoded 4:2:0) → `AVAssetWriter` (VideoToolbox H.264 High / HEVC, keyframe every 2 s, rotation kept via the track transform, index at the front for the web); passthrough `AVAssetExportSession` for remux and mute. Writes to a temp file, then `OutputWriter.move` puts it next to the original. Sizes are read with `FileManager` (URL resource values are cached and would go stale between retries).
- **Runner**: a batch with any video runs one file at a time; progress moves per frame (`ProgressReporter.within`, 1% steps), retries keep the ring moving forward, and cancel stops the encode. The output file goes on the clipboard as a file URL, like images.
- **Deferred:** WebM and FFmpeg "max quality" + VMAF auto-tune need FFmpeg (LGPL) or libvpx + libwebm (BSD-3), which needs the owner's OK (Rule 7, `CORE.md` §13). HDR sources aren't tone-mapped for MP4 yet (see *Risks*; GIFs go through Core Image's color management).

**Drag from any app (owner asked, 2026-11-01; owner confirmed "drag works" on their Mac, 2026-11-02, the first feature a person has tried):** besides Finder files, the bubble takes **promised files** (`NSFilePromiseReceiver`: Photos, Mail and Messages attachments, Safari and most browsers' images, any app that can drag a file to the Desktop) and, failing that, **picture data** (PNG, JPEG, HEIC, WebP, AVIF, GIF, then TIFF), named after the picture's web address when there is one. `Bubble/DroppedItems.swift` reads the drag: kinds for the menu at drag-enter (from the promise's file types; nothing is fetched), everything at the drop. Promised files can take a while (Photos may download from iCloud), so the bubble spins while they arrive (up to 90 s, then it goes on with what came; a click cancels). They land in `ReceivedFiles` (a temp folder, cleared on the next drop and at launch) and **results go to Downloads** (`OutputWriter.folder(for:fallback:)`); the card says "Saved to Downloads". The free plan counts and caps them like any files. Web links themselves are never downloaded (Rule 4).

**Free plan and Pro (owner's decision, 2026-11-01; `CORE.md` §8.1):** free = **3 files a day**, any action, counted per output file, reset at local midnight; Pro = unlimited, **$5/month or $50 lifetime**, sold through **Lemon Squeezy** (license keys).

- **Counting** (`Store/Allowance.swift`, portable): `ProStore.grant(n)` caps a drop to what's left; `record(outputs)` counts what came out (failures don't count). A drop with more files than are left runs the first ones and the card says "Free plan: 2 of 5. Pro does all"; the last free file says "That was today's last free file". With none left, dragging over the bubble shows "No free files left today. Click for Pro." (it stays a moment after the drag leaves; clicking opens the Pro window). Stored in UserDefaults (`pro.allowance`), so a determined user can reset it; fine for a $5 utility.
- **Pro window** (`App/Pro.swift`, menu bar → **Upgrade to Pro…**, or "Droptimize Pro…" before it's on sale): benefits, **$5 a month** and **$50 once** buttons (open the Lemon Squeezy checkout in the browser), and a field for the license key from the purchase email. With Pro: plan, masked key, email, Manage Subscription (monthly), Deactivate on This Mac. The menu shows "Free plan: 2 of 3 files left today" or "Droptimize Pro" at the top.
- **License** (`Store/License.swift`, portable; network in `ProStore`): Lemon Squeezy's public License API: `activate` (key + the Mac's name → instance ID), `validate` (daily for monthly, weekly for lifetime, at launch and every 6 h), `deactivate`. Only keys from our store and our two products are accepted (others are given straight back). A definite "no" (expired, refunded, disabled) ends Pro; network trouble, 429 or 5xx change nothing, and monthly Pro keeps working 14 days offline. Rule 4 amended for this one call; it never sends anything about files.
- **Off until configured:** `StoreConfig` (top of `Store/License.swift`) holds the store ID, the two product IDs and the two checkout links, all `nil` now. Until they're all filled in, `isSelling` is false: the buy buttons are disabled, the window says Pro goes on sale soon, and **nothing is limited** (so preview builds stay unlimited for testing).

**History (owner asked for it in the app, 2026-10-30):** menu bar → **History…** (⌘Y in the menu) opens a normal window (`App/HistoryWindow.swift`; it activates the app, since you asked to look at it). Every file made, newest first: thumbnail, output name, action · option ("Compress · Under 500 KB"), relative date, change ("−84%" in green, "+12%" grey) and before → after sizes, with a total "saved" figure at the top. Double-click or 🔍 shows it in Finder; drag a row into any app; the context menu has Open, Copy, Show Original and Remove; "Clear History…" asks first and never touches files. Files that were moved or deleted are dimmed. Stored as JSON in `~/Library/Application Support/Droptimize/history.json`, kept on the Mac only (Rule 4), at most 500 entries (`HistoryLog.limit`). The menu bar's Recent list now comes from it. Model: `Pipeline/History.swift` (portable, tested on Linux); `JobResult.items` carries each original with its result.

**Image menu (restructured 2026-10-30, owner approved):** **Convert** → WebP · AVIF · JPG · PNG · HEIC · **Compress** → sizes · **Half size** · **Remove BG** → backgrounds, with **Auto** in the center. One slot is free for later (Resize presets or Crop). Dropping on Convert itself = WebP, like Auto. Converting to another format is **exempt from Rule 3** (the owner agreed: WebP → PNG is often bigger), and Convert to the source's own format counts as a recompress (`-min`, size guard applies). JPG output flattens transparency onto white and says so on the card.

**Option bubbles (the owner's design, 2026-10-30):** hovering a segment that has options fans out a second ring of smaller bubbles beyond it; dropping on the segment itself still does its default.

- **Compress** → **100K · 250K · 500K · 1M · 2M · Custom**. Compress to at most that size, same format: bisection over the encoder's quality (`SizeSearch`, 6 steps) for the best quality that fits. If even the lowest quality is too big, it shrinks the image in 0.8× steps (never under 64 px), and the card says "Resized to W × H to fit". "Already under 500 KB." if it already is; "Couldn't get it under 100 KB." if impossible. PNG has no quality knob, so PNG targets work by shrinking only (pngquant would do better; waits on free vs paid). Named `photo-500kb.jpg`.
- **Remove BG** (now built, Phase 1 step 4 brought forward) → **None (transparent) · White · Black · last custom color · Custom**. Uses Vision's `VNGenerateForegroundInstanceMaskRequest` (on device, macOS 14), applies the soft mask as alpha (`Compositor`), and lays it over the color if one was chosen. Always PNG, named `-nobg` / `-bg`. **Exempt from the size guard**: it isn't an optimization, and a cut-out PNG can be bigger than the JPEG it came from. The card shows "Done" plus "Background removed" or "Background: #HEX".
- **Custom** (both menus): you can't type mid-drag, so dropping on Custom shows a small panel beside the bubble (`Bubble/InputPanel.swift`). Size: a number plus KB/MB (decimal, as Finder shows). Color: a hex field, 8 preset swatches and the system eyedropper (`NSColorSampler`). It takes the keyboard without activating the app, handles ⌘C/⌘V itself (menu bar apps have no Edit menu), Return confirms, Esc or Cancel cancels, and clicking the bubble cancels. The last size pre-fills the field; the last color becomes its own bubble next time (`OptionMemory`, UserDefaults).
- **Geometry** (`SubmenuLayout`, `MenuGeometry` in `Bubble/BubbleLayout.swift`): options sit 56 pt beyond the main ring, centered on their segment's angle but clamped within 85° of straight into the screen, so none goes past the edge. Past the midpoint between the rings the pointer picks options; inside it, segments. Options stay open while the pointer is out among them. The bubble now keeps ~180 pt from the top and bottom of the screen so the outer ring fits (`BubbleLayout.verticalClearance`).

**Verified:**

- `scripts/check-linux.sh`: every file parses; **117 portable tests pass on Linux** (including the video plans and bitrate maths in `Tests/VideoPlanTests.swift`), including exact PNG round trips (checked by a test-only PNG reader that verifies CRCs and undoes filters itself), exact lossless WebP, lossy WebP closeness, alpha kept, naming, size guard, writer, plans.
- CI on macOS: see the Snapshot. The macOS tests (`Tests/PipelineMacTests.swift`) cover EXIF rotation, P3→sRGB conversion, transparency, half size, ImageIO reading our PNG/WebP exactly, real files end to end, Rule 2 (original untouched), Rule 3 (nothing written when it can't get smaller), clashes, and batch plus clipboard. `Tests/VideoMacTests.swift` makes synthetic videos (720p noise, the worst case for an encoder, plus an AAC tone) and covers remux, Auto, Resize, never upscaling, compress to a size, Mute (with and without sound), GIF, HEVC (skipped without an encoder) and progress within a video.

**Not verified (needs a person on a Mac):** the feel, including reaching the option bubbles mid-drag; the window behaviour (see *Risks*); typing into the Custom panel while another app is in front; **Remove BG quality on real photos** (CI ran Vision on a synthetic image, which it may not treat as a subject; the tests accept either outcome); how the clipboard pastes into Figma, Slack, Chrome, Notes and Messages (CORE.md §6.6); and real-world savings on a variety of images. **Video on real footage**: iPhone clips (HDR, portrait rotation), screen recordings, long 4K files (speed, cancel), and how the results play in Safari, Chrome, Slack and Discord.

## ✱ Next steps (in order)

0. **Make sure CI is green** on the branch. If it's red, open the run, read the failing step's log and fix it. Use `mcp__github__get_job_logs` with `failed_only: true` if you don't have a browser.
1. **Selling Pro: the owner sets up Lemon Squeezy** (they create the account; nothing to code until they send the IDs). Steps to give them: sign up at lemonsqueezy.com and create a store (it asks for identity and payout details before it can take real payments; test mode works before that). Create two products, each with **"Generate license keys"** on and an activation limit (3 Macs suggested): **Droptimize Pro Monthly**, a subscription at $5/month, and **Droptimize Pro Lifetime**, a single payment of $50. Then send: the store ID (Settings → Stores), both product IDs, and both checkout links (each product's Share button). Put them in `StoreConfig`, buy each in **test mode** to check activation, the monthly key expiring after a cancelled test subscription, and Deactivate, then push. That switches the free limit on in the next preview.
2. **Owner tries the preview DMG** (the Snapshot link). History: on 2026-10-30 they said they couldn't run it on their Mac (reason never confirmed); they were given step-by-step DMG instructions, saw the Phase 0 build's pretend actions, asked for real functionality, and approved libwebp. Ask what they saw with real files, and fix what they report. Run through the *Manual test checklist* below as far as they're willing; tune `Bubble/Motion.swift` from their feedback.
3. **Phase 1 step 2** (`CORE.md` §11), still to do: the **Auto classification** (photo → lossy WebP; graphic → lossless WebP vs PNG, smaller wins; replace `RGBAImage.looksLikeGraphic`), and the fuller PNG pipeline (pngquant is GPL, so a paid app needs its commercial license or a permissive quantizer; ask before buying one).
4. **JobQueue** (`CORE.md` §5): drops while a job runs are still ignored (`BubbleController.dragEntered` returns false while working). Make new drops queue, and move cancellation into the queue.
5. Phase 1 step 3: SSIMULACRA 2 auto-tune (replaces the fixed values in `EncoderTuning`). (Step 4, Remove BG, is done.)
6. **Video follow-ups:** check HDR iPhone clips (Risk 9); ask the owner how the new GIFs look (tune `VideoTuning.gif*`: frame rate, size, change threshold, dither strength); ask the owner about WebM (FFmpeg or libvpx + libwebm) and then VMAF auto-tune (`CORE.md` §7.3); a notification when a long video finishes.
7. Smaller items: post a notification for jobs over ~10s; a Settings window (`CORE.md` §10), which could also offer "save results from other apps to…" instead of always Downloads.

## ✱ Risks to check first on a real Mac

1. **Drags between segments.** Transparent pixels let drags fall through to the window below, so the open menu draws a near-invisible disc (`Motion.hitCatchOpacity` = 0.01). If the menu collapses when crossing a gap, raise it.
2. **Growing the panel mid-drag.** The panel is resized inside `draggingEntered`. If hover or the drop misbehaves right after the menu opens, check `draggingUpdated` keeps arriving.
3. **Hover on a non-key panel.** This relies on the `.activeAlways` tracking area in `BubbleHostView`.
4. **Folder permission prompts.** Saving next to a file in Desktop, Documents or Downloads makes macOS ask for access to that folder once. With ad-hoc signing, every new build has a new identity, so it may ask again after each DMG update. Developer ID signing (Phase 3) fixes that.
5. **JPEG and HEIC through ImageIO** embed an sRGB ICC profile (~3 KB), which matters on small JPEGs. jpegli replaces this.
6. **Option bubbles mid-drag.** Moving outward from Compress to a size bubble is a longer reach. If it feels fiddly, tune `Motion.optionRingDistance`, `optionDiameter` and the boundary in `SubmenuLayout.innerBoundary`.
7. **Custom panel focus.** It relies on a `.nonactivatingPanel` becoming key while another app stays active. If typing doesn't reach it, the fallback is `NSApp.activate()` while it's open (which breaks Rule 1 briefly).
8. **Drags from other apps** (built 2026-11-01; the owner says drag works, but not which apps they tried): Photos, Mail, Messages and browsers each package drags their own way. If one doesn't work, log `sender.draggingPasteboard.types` in `BubbleHostView.draggingEntered` to see what it offers. Haptics only fire on Force Touch trackpads.
9. **HDR video.** iPhones record HDR (HLG / Dolby Vision, 10-bit HEVC). Re-encodes decode to 8-bit 4:2:0 without asking for a color space, so an H.264 result may look washed out or dim. If it does, set `AVVideoColorPropertiesKey` (BT.709) on the reader output and the writer in `VideoOptimizer.transcode` so Apple tone-maps it, and keep HDR for HEVC (`CORE.md` §7.4). Remux and Mute copy the streams, so they're unaffected.
10. **Encoder overshoot.** On busy footage VideoToolbox can come out far over the asked bitrate (the noise test video comes out ~3× over). Compress-to-size retries; Auto relies on the size guard. If real clips often miss, tune `VideoTuning`.

## Manual test checklist

1. Launch: no Dock icon, the logo (nested circles) in the menu bar and on the bubble; the app icon in Finder and Applications, and the bubble on the right edge, vertically centered, at about 60% opacity.
2. Hover: full opacity and a slight grow.
3. Drag the bubble toward the left: it springs to the left edge. Quit and relaunch: it's still there.
4. Drag a PNG from Finder over it: the bubble grows and 4 segments fan out with a stagger. Hover each: it highlights, its label shows in the bubble, and there's a haptic tick.
5. Hover **Convert** and drop on **WebP**: ripple, spinner, checkmark, and a card with the real saving and a thumbnail. `photo.webp` appears next to the original. Paste in Finder (the file) and in Notes (the picture).
6. **Compress** a screenshot PNG → `-min.png`; a camera JPEG → `-min.jpg`. **Half size** → `-half` at half the width and height.
7. Compress the `-min.png` again: shake and "Already as small as it gets.", and no new file.
8. Drag the card into a Finder folder (it copies), and onto a Slack or Chrome upload field. Click the card: Finder reveals the new file.
9. Drop 10 images at once on Compress: the count goes up, then "10 files" on the card.
10. Hover **Compress**: six small bubbles fan out. Drop on **500K** with a big photo → `photo-500kb.jpg` under 500 KB. Drop on **…** → a size panel; type 300, KB, Return.
11. Hover **Remove BG**: None · White · Black · … Drop a portrait on **None** → `-nobg.png` with a transparent background. Drop on **…** → a color panel; try a hex, a swatch and the eyedropper. Next time, that color is its own bubble.
12. **Convert → AVIF** on a photo → `photo.avif`, usually smaller than the WebP. **Convert → JPG** on a transparent PNG → white background and a note. **Convert → PNG** on a WebP → a PNG even if it's bigger. Quick Look shows it.
13. **Video:** drag a `.mov` screen recording over the bubble: Convert · Compress · Resize · Mute. Drop on the center → a smaller `.mp4`, the ring filling as it goes. **Convert → MP4** on an iPhone clip is instant. **Compress → 10 MB** on a big clip → `-10mb.mov` under 10 MB (maybe "Scaled to 720p to fit"). **Resize → 720p**, **Mute**, **Convert → GIF** (plays smoothly in Quick Look and a browser, loops; gradients and skin tones without bands; still backgrounds don't crawl). Click the bubble mid-encode to cancel. Check portrait clips stay upright and HDR clips don't look washed out.
14. Drag a `.txt` over it: "Can't open this file type yet." while over, gone on exit.
15. **From other apps:** drag a photo out of **Photos**, an attachment out of **Mail**, and an image from **Safari** and **Chrome** onto the bubble. Each gets the image menu; the result lands in **Downloads** ("Saved to Downloads" on the card) and on the clipboard.
16. While a big batch works: hovering shows ×, and a click cancels.
17. Type in TextEdit and drop on the bubble mid-sentence: TextEdit keeps focus.
18. Menu bar → **History…**: every file you made, newest first. Double-click one (Finder), drag one into Slack, right-click → Copy. Clear History asks first.
19. Menu bar → **Droptimize Pro…**: the Pro window (buy buttons disabled until it's on sale). Once `StoreConfig` is filled in: the menu says "Free plan: 3 of 3 files left today"; make 3 files, then drag a 4th over the bubble: "No free files left today. Click for Pro."; click it. Buy in Lemon Squeezy test mode, paste the key, Activate: Pro, unlimited.
20. Switch Spaces and enter a full-screen app: the bubble is still there. ⌃⌥⌘D hides and shows it.
21. Turn on Reduce Motion (System Settings → Accessibility → Display): fades only. Check light and dark mode.
22. With two displays: move the bubble to the second one, relaunch, and it's still there.

## ✱ Decisions made so far (also in `CORE.md` §14)

- **Logo** (owner's pick, 2026-10-31, replacing the drop, which they called "the most sloppy logo ever"): "Shrink", a circle, a smaller circle inside it, and a solid dot, all touching at the bottom left: the same thing, smaller and smaller, echoing the bubble. One geometry in `Bubble/Logo.swift` (24-unit grid) draws the bubble glyph (`LogoMark`) and the menu bar template image. The app icon (the app had none before) is the mark in white on a dark tile with a mint dot (#3DDC97 → #22C47E), from `scripts/app-icon.svg`. The other concepts shown: Scale down, Squeeze, Compact.
- The bubble docks to the **left or right** edge only. The top has the menu bar and the bottom usually the Dock.
- The menu is a **160° arc facing into the screen**, segments top to bottom, instead of a full ring. The ring grows for 6 segments so neighbours never touch.
- The hovered action's **label shows inside the bubble**, because the drag image covers the segment. Segments are picked **by angle** outside the center.
- Results and messages appear **beside the bubble**, on the side facing into the screen.
- **libwebp 1.6.0** (BSD-3), approved by the owner. It's built from the pinned, SHA-256-checked release by `scripts/build-deps.sh`, not committed (`Vendor/` is generated).
- **libaom 3.15.2 + libavif 1.4.2** (BSD-2, plus the AOM Patent License 1.0, royalty-free), approved by the owner. libaom comes from its checksummed release tarball; libavif is cloned at the pinned commit of tag v1.4.2 (its GitHub tarball can't be downloaded through the agent proxy, and a pinned commit is just as reliable). Built with CMake; `nasm` makes the Intel slice fast (CI installs it).
- PNG Compress uses **our own lossless optimizer** with the system zlib, so it's license-free (the app is closed source and paid, so GPL tools are out). JPEG and HEIC use **ImageIO** until jpegli.
- **Auto = WebP** until classification (Phase 1 step 2). Half size uses the suffix **`-half`**.
- **Option bubbles** (owner's choice): Compress → target file sizes 100 KB · 250 KB · 500 KB · 1 MB · 2 MB · Custom. Background choices live **inside Remove BG** (None · White · Black · last color · Custom hex), not as a separate bubble. Custom values are asked for after the drop. Sizes are decimal (1 KB = 1000 bytes). Hitting a size shrinks the image only as a last resort, and says so.
- **Remove BG is exempt from Rule 3** (never bigger): it changes content rather than optimizing. Always PNG.
- **Menu: Convert replaces the separate WebP and AVIF buttons** (owner approved): Convert → WebP · AVIF · JPG · PNG · HEIC. Conversions only into formats web pages and uploads take; no general-purpose conversion (PDF, SVG, RAW, documents). **Conversions to another format are exempt from Rule 3.**
- Fixed encoder settings in `EncoderTuning` (`Image/RGBAImage.swift`) until auto-tune: WebP q80/method 4, JPEG 0.8, HEIC 0.75.
- If the original's folder is read-only, results go to **Downloads**.
- **Swift 5 language mode** for now. Ad-hoc signing; hardened runtime on Release only (Phase 3 switches to Developer ID).
- **Video uses AVFoundation only** for now (no new dependencies): the video menu mirrors images (Convert · Compress · Resize · Mute, Auto in the center). Compress's sizes are common upload limits (10, 25, 50, 100 MB). Video conversions and Mute are exempt from Rule 3, like image conversions. WebM waits for the owner's OK on FFmpeg or libvpx. Made while the owner was away ("do the recommended stuff"); revisit anything they dislike.
- **Freemium** (owner, 2026-11-01): free 3 files a day, any action, per file; Pro $5/month or $50 lifetime through Lemon Squeezy license keys (direct, not the Mac App Store, whose sandbox would fight saving next to the original). Closed source, so GPL/AGPL libraries are out. The license check is the only network call.
- CI runs on GitHub's macOS runners (free: the repo is public) and publishes a DMG, a zip and `install.sh` to the public `preview` release (the owner approved). Updates are a Terminal one-liner for now; an in-app "Check for Updates" arrives with Sparkle (Phase 3), since the app itself makes no network calls (Rule 4).

## ✱ Questions for the owner

1. **Set up Lemon Squeezy** and send the IDs (Next steps 1). How many Macs should one Pro key cover (3 suggested)?
2. Is the label inside the bubble right, or would you rather see it next to the hovered segment?
3. Is ⌃⌥⌘D OK as the show/hide shortcut?
4. **WebM for video?** It needs FFmpeg (LGPL, linked dynamically) or libvpx + libwebm (BSD-3), adding several MB. MP4 already plays everywhere, so it's only worth it if you want WebM files specifically.

## How to build, run and test

**On a Mac** (macOS 14+, current Xcode):

```bash
brew install xcodegen
```

```bash
xcodegen generate && open Droptimize.xcodeproj
```

`xcodegen generate` first runs `scripts/build-deps.sh`, which downloads and builds libwebp, libaom and libavif into `Vendor/` (several minutes the first time, then a no-op). It needs `brew install cmake nasm`. Then Run (⌘R) or Test (⌘U). From the command line:

```bash
xcodegen generate && xcodebuild test -project Droptimize.xcodeproj -scheme Droptimize -destination 'platform=macOS'
```

**Without Xcode** (how the owner runs it): in Terminal, run `curl -fsSL https://github.com/bimanshu/Droptimize/releases/download/preview/install.sh | bash`. `scripts/install.sh` checks for macOS 14+, downloads `Droptimize.zip` from the preview release, verifies the signature, quits the running copy, swaps the app in `/Applications` (or `~/Applications` if that isn't writable) and opens it. curl downloads aren't quarantined, so no Gatekeeper step. CI runs it on every build (fresh install, then update) before publishing. The same works for a first install. By hand instead: download the DMG from https://github.com/bimanshu/Droptimize/releases/download/preview/Droptimize.dmg, open it, and drag Droptimize into Applications. Run `xattr -cr /Applications/Droptimize.app` (it's ad-hoc signed, so Gatekeeper blocks it until Phase 3 notarization), then open it. It needs macOS 14+. There's no window or Dock icon: look for the logo (nested circles) in the menu bar and the bubble on the right edge of the screen. The DMG also contains `READ ME FIRST.txt` (from `scripts/dmg-readme.txt`; keep it current when the steps or features change).

**How the preview is published:** the `publish` job in `.github/workflows/build.yml` runs after every green push (not for PRs). It swaps the files of the `preview` pre-release in place (`gh release upload --clobber`, install.sh first), moves the `preview` tag to the pushed commit, and updates the notes, so the links never change. (It used to delete and recreate the release. On 2026-10-30 the owner hit "The requested URL returned error" running the install command during one of those ~15-second gaps; `install.sh` now also retries its download.) It publishes from **any** branch, so the preview is always the most recent green push. Each run's DMG is also kept as the `Droptimize-dmg` artifact for 14 days. Release notes are written inline in the workflow; keep them current too.

**Checking code without a Mac** (Linux containers, like the one used so far): AppKit and SwiftUI can't compile on Linux. Download a Swift toolchain (about 900 MB; Swift 6.1.2 for Ubuntu 24.04 is at `https://download.swift.org/swift-6.1.2-release/ubuntu2404/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-ubuntu24.04.tar.gz`), extract it, put its `usr/bin` on `PATH`, then run:

```bash
./scripts/check-linux.sh
```

It parses every Swift file, builds libwebp, libaom and libavif for Linux (needs `cc`, cmake, perl and zlib headers, all present in the usual containers; about 2 minutes the first time), and runs the portable tests, including the real encoders. When you add Foundation-only code with tests, add it to the lists at the top of the script. Then push and read CI for the real compile.

## Map of the code

| File | What it does |
|---|---|
| `project.yml` | XcodeGen spec (app and test targets, macOS 14, LSUIElement, C module paths, runs `build-deps.sh` first). The `.xcodeproj` is generated and git-ignored. |
| `App/DroptimizeApp.swift` | `@main`: starts `NSApplication` with the delegate. |
| `App/AppDelegate.swift` | Creates the bubble, menu bar and hot key (skipped under unit tests). |
| `App/MenuBar.swift` | Status item and menu, Recent list, the shortcut constants. |
| `App/HotKey.swift` | Carbon global hot key wrapper. |
| `Bubble/Motion.swift` | **Every** size, spring, delay and opacity. Tune here. |
| `Bubble/BubbleLayout.swift` | Pure geometry: `DockSide`, `MenuTarget`, `RadialLayout` (arc and hit-testing), `BubbleLayout` (panel frame per state, canvas size). |
| `Bubble/DockPosition.swift` | Edge plus height fraction, nearest-edge snapping, vertical clamp, per-display `DockStore`. |
| `Bubble/Spring.swift` | Pure spring integrator (SwiftUI's response/damping model). |
| `Bubble/PanelMover.swift` | Drives the spring with a `CADisplayLink` to move the panel. |
| `Bubble/BubblePanel.swift` | The `NSPanel` configuration. |
| `Bubble/BubbleHostView.swift` | The panel's content view: **all events** (drag destination, drag source for the card, hover, click, move). |
| `Bubble/BubbleController.swift` | The state machine (idle → menu → working → done or message), panel sizing, position, jobs, dismiss timers. |
| `Bubble/BubbleModel.swift` | `ObservableObject` the views draw from, plus `DoneInfo` and `Ripple`. |
| `Bubble/BubbleView.swift` | SwiftUI drawing: bubble, glyphs, progress ring and spinner, card, message pill, ripple, shake. |
| `Bubble/RadialMenu.swift` | SwiftUI segments with fan-out and stagger. |
| `Bubble/Logo.swift` | The logo's geometry (`Logo`), its SwiftUI view (`LogoMark`, the bubble glyph) and the menu bar template image. |
| `App/Assets.xcassets` | The app icon, PNGs rendered from `scripts/app-icon.svg` by `scripts/make-app-icon.js` (Node + Playwright, a dev tool only). |
| `Bubble/DroppedItems.swift` | What a drag carries: Finder files, promised files from other apps, or picture data; turns them into files on disk. |
| `Bubble/Thumbnails.swift` | QuickLook thumbnails for the card. |
| `Bubble/InputPanel.swift` | The post-drop panel for Custom: size (KB/MB) or color (hex, swatches, eyedropper); key without activating; `Color(rgb:)`. |
| `Image/RGBAImage.swift` | Portable pixel buffer (sRGB, straight alpha) with opacity and color-count checks; `EncoderTuning` (all encoder settings). |
| `Image/ImageFormat.swift` | Portable list of readable formats and their extensions. |
| `Image/Decode.swift` | macOS: ImageIO decode, orientation, sRGB, vImage resize, unpremultiply; `ImageFormat(typeIdentifier:)`; `RGBAImage.makeCGImage()`. |
| `Image/Encoders/WebP.swift` | Portable: libwebp lossy and lossless. |
| `Image/Encoders/AVIF.swift` | Portable: libavif + libaom (8-bit sRGB, 4:4:4 or 4:2:0, lossless alpha). |
| `Image/Encoders/PNG.swift` | Portable: our lossless PNG optimizer (zlib). |
| `Image/Encoders/ImageIOEncoder.swift` | macOS: JPEG, HEIC and plain PNG via ImageIO. |
| `Image/RGBColor.swift` | Portable: `RGBColor` (hex in and out) and `ByteCount` (500 KB, 500K, -500kb). |
| `Image/SizeSearch.swift` | Portable: bisection for the best quality under a size, and the shrink steps. |
| `Image/Compositor.swift` | Portable: applies a subject mask as alpha, optionally over a color. |
| `Image/SubjectMask.swift` | macOS: Vision foreground mask for Remove BG. |
| `Pipeline/Action.swift` | `Action` (titles, SF Symbols, VoiceOver labels), `MediaKind`, `ActionMenu`. |
| `Pipeline/MediaKind+Files.swift` | Image/video detection from a URL via UTType. |
| `Pipeline/Job.swift` | `Job`, `JobProgress`, `JobResult`, `JobError` (every user-facing error line), and the `JobRunner` protocol. |
| `Pipeline/ImagePlan.swift` | Portable: action + option + source format → encoder, extension, suffix, scale; "coming soon" errors. |
| `Pipeline/ActionOptions.swift` | Portable: `ActionOption`, `MenuOption`, each action's option bubbles, `OptionMemory` (last size and color). |
| `Pipeline/Output.swift` | Portable: `OutputNaming`, `SizeGuard` (Rule 3), `OutputWriter` (never overwrites; Downloads fallback), `ReceivedFiles` (copies of files dragged in from other apps; their results go to Downloads). |
| `Pipeline/ImageJobRunner.swift` | macOS: `ImageOptimizer` (one file: plain, compress-to-fit, Remove BG) and `ImageJobRunner` (parallel batches, one at a time with videos, which go to `VideoOptimizer`; progress within a file; clipboard, notes). |
| `Pipeline/Clipboard.swift` | macOS: file URLs plus a PNG picture on the pasteboard. |
| `Pipeline/History.swift` | Portable: `HistoryEntry`, `HistoryLog` (newest first, 500 max, Recent, totals), `HistoryFile` (JSON in Application Support), `ActionOption.title`. |
| `Video/VideoPlan.swift` | Portable: `VideoFormat`, `VideoPlan` (action + option → work, extension, suffix, size guard) and `VideoTuning` (every video setting and the bitrate/size maths). |
| `Video/VideoOptimizer.swift` | macOS: one video → a new file: passthrough remux/mute, AVAssetReader → AVAssetWriter encode with compress-to-size retries, GIF; `VideoSource` (probe); `GIFFrameReader` (even frames, upright, scaled, sRGB via Core Image). |
| `Video/GIFEncoder.swift` | Portable: `GIFPalette` (histogram, exact colors or median cut + k-means), `GIFWriter` (dithering, redraw only what changed, timing), `LZWEncoder`. |
| `Store/Allowance.swift` | Portable: `FreeAllowance`, the free plan's 3 files a day. |
| `Store/License.swift` | Portable: `StoreConfig` (Lemon Squeezy IDs and links, nil until the store exists), `License`, `LemonSqueezy` (requests and answers). |
| `App/Pro.swift` | macOS: `ProStore` (count, license, network), the Pro window. |
| `App/HistoryWindow.swift` | macOS: `HistoryStore` (saves on every change), the History window and its rows. |
| `Modules/module.modulemap` | Lets Swift import libwebp (`CWebP`), libavif + libaom (`CAvif`) and zlib (`CZlib`, where the SDK has no `zlib` module). |
| `scripts/build-deps.sh` | Builds pinned libwebp, libaom and libavif into `Vendor/` (universal static libs on macOS, host builds on Linux). Needs cmake, and nasm for a fast Intel slice. |
| `scripts/check-linux.sh` | Parse, build libwebp, and run the portable tests without a Mac. |
| `scripts/install.sh` | One-command install/update from the preview release (published as a release asset; tested in CI). |
| `scripts/dmg-readme.txt` | The "READ ME FIRST" note inside the DMG. |
| `.github/workflows/build.yml` | macOS CI: deps (cached), generate, build, test (warnings fail), universal Release build, DMG and zip, install-script test; then publishes DMG, zip and `install.sh` to the `preview` release. |
| `Tests/` | XCTest. Portable (also run on Linux): `LayoutTests`, `DockPositionTests`, `SpringTests`, `ActionTests`, `OutputTests`, `EncoderTests`, `OptionTests`, `AVIFTests`, `HistoryTests`, `VideoPlanTests`, `GIFTests`, `StoreTests`, `Support/TestPNGReader`, `Support/TestGIFReader` (a GIF decoder written from the spec, independent of the encoder) (test-only PNG reader plus test images). macOS only: `MacTests`, `PipelineMacTests`, `OptionMacTests`, `VideoMacTests` (synthetic videos). |

## How the bubble works (so you don't have to rediscover it)

- **Events go through AppKit only.** `BubbleHostView.hitTest` returns itself, so the SwiftUI canvas never gets events. The host view calls `BubbleController`, which changes `BubbleModel`, and the SwiftUI views re-render with implicit `.animation(_:value:)` animations.
- **Fixed canvas, resizing window.** The SwiftUI canvas is a fixed square (`BubbleLayout.canvasSide`) always centered on the bubble. Only the panel's frame changes per state (`BubbleLayout.panelFrame`), and `host.bubbleCenter` repositions the canvas so nothing visibly moves. The panel grows at once, so segments are real drop targets straight away. It shrinks after `Motion.collapseSettle` so the fold-in and ripple can finish.
- **Coordinates.** The controller works in screen coordinates (`center` is the bubble's center on screen) and reads the pointer with `NSEvent.mouseLocation`. Geometry offsets use y-up; SwiftUI offsets negate `dy`.
- **Phases.** `BubbleModel.Phase` decides the panel content: `.idle` and `.working` → bubble only, `.menu` → arc, `.done` and `.message` → accessory beside the bubble.
- **Drag in vs drag out.** The host view ignores drags it started itself (`isOwnDrag`), and as a drag source it only allows `.copy` outside the app.

## How an image is processed

`BubbleController.drop` → `ImageJobRunner.run` (parallel, off the main thread) → per file `ImageOptimizer.process`: `ImageDecoder.decode` (orientation, sRGB, optional half size) → `ImagePlan.make` (encoder, extension, suffix) → encode → `SizeGuard` → `OutputWriter` → back on the main actor: `Clipboard.put`, then the done card with a QuickLook thumbnail of the first output.


## How a video is processed

`ImageJobRunner.run` sees a video (`MediaKind`) → `VideoOptimizer.process`: `VideoPlan.make` (work, extension, suffix, target, size guard) → "already under/at most" checks → `VideoSource.load` (tracks, size, fps, codecs, bitrate) → remux, mute, encode (with retries for a target size) or GIF into a temp file → target and `SizeGuard` checks → `OutputWriter.move` next to the original → the same clipboard, card and History as images.

# Handoff

> **Read this first, then `CORE.md`.** This file says where the work stands right now and exactly what to do next. `CORE.md` says what we're building and the rules.
> Whoever ends a session updates the ✱ sections before pushing. Keep it current, not historical: history goes in `CORE.md` §14 and the git log.

## ✱ Snapshot

| | |
|---|---|
| Last updated | 2026-10-30 |
| Branch | `claude/fervent-thompson-2620yn` (the only branch so far; no `main` yet, nothing merged, no PR) |
| Phase | **1: WebP, AVIF, Compress (incl. target sizes), Half size and Remove BG (with background choices) work.** Option bubbles fan out of Compress and Remove BG. The feel hasn't been tuned by a person yet. |
| CI | [Build workflow](https://github.com/bimanshu/Droptimize/actions/workflows/build.yml): green at `42d2849` (Xcode 16.4, macOS 15 runner): **135/135 tests** (105 of them also on Linux), 0 warnings (warnings fail the build), universal libwebp/libaom/libavif and app, install script tested, preview published. The app is now ~8.5 MB (DMG), mostly libaom. The first deps build after a `build-deps.sh` change takes ~3 minutes in CI; otherwise it's cached |
| Install / update | One Terminal command: **`curl -fsSL https://github.com/bimanshu/Droptimize/releases/download/preview/install.sh \| bash`** (or the [DMG](https://github.com/bimanshu/Droptimize/releases/download/preview/Droptimize.dmg)). Both come from the [preview release](https://github.com/bimanshu/Droptimize/releases/tag/preview), which CI replaces on every green push. |
| Owner | Doesn't build with Xcode. Updates with the one-line command above (asked for this instead of re-downloading DMGs). Not technical about Terminal: give exact click-by-click steps. |
| Next | Owner tries the new menu and the History window via the update command → fix what they report → Auto classification (Phase 1 step 2) |

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
- **Every video action** answers "Video is coming soon."

**History (owner asked for it in the app, 2026-10-30):** menu bar → **History…** (⌘Y in the menu) opens a normal window (`App/HistoryWindow.swift`; it activates the app, since you asked to look at it). Every file made, newest first: thumbnail, output name, action · option ("Compress · Under 500 KB"), relative date, change ("−84%" in green, "+12%" grey) and before → after sizes, with a total "saved" figure at the top. Double-click or 🔍 shows it in Finder; drag a row into any app; the context menu has Open, Copy, Show Original and Remove; "Clear History…" asks first and never touches files. Files that were moved or deleted are dimmed. Stored as JSON in `~/Library/Application Support/Droptimize/history.json`, kept on the Mac only (Rule 4), at most 500 entries (`HistoryLog.limit`). The menu bar's Recent list now comes from it. Model: `Pipeline/History.swift` (portable, tested on Linux); `JobResult.items` carries each original with its result.

**Image menu (restructured 2026-10-30, owner approved):** **Convert** → WebP · AVIF · JPG · PNG · HEIC · **Compress** → sizes · **Half size** · **Remove BG** → backgrounds, with **Auto** in the center. One slot is free for later (Resize presets or Crop). Dropping on Convert itself = WebP, like Auto. Converting to another format is **exempt from Rule 3** (the owner agreed: WebP → PNG is often bigger), and Convert to the source's own format counts as a recompress (`-min`, size guard applies). JPG output flattens transparency onto white and says so on the card.

**Option bubbles (the owner's design, 2026-10-30):** hovering a segment that has options fans out a second ring of smaller bubbles beyond it; dropping on the segment itself still does its default.

- **Compress** → **100K · 250K · 500K · 1M · 2M · Custom**. Compress to at most that size, same format: bisection over the encoder's quality (`SizeSearch`, 6 steps) for the best quality that fits. If even the lowest quality is too big, it shrinks the image in 0.8× steps (never under 64 px), and the card says "Resized to W × H to fit". "Already under 500 KB." if it already is; "Couldn't get it under 100 KB." if impossible. PNG has no quality knob, so PNG targets work by shrinking only (pngquant would do better; waits on free vs paid). Named `photo-500kb.jpg`.
- **Remove BG** (now built, Phase 1 step 4 brought forward) → **None (transparent) · White · Black · last custom color · Custom**. Uses Vision's `VNGenerateForegroundInstanceMaskRequest` (on device, macOS 14), applies the soft mask as alpha (`Compositor`), and lays it over the color if one was chosen. Always PNG, named `-nobg` / `-bg`. **Exempt from the size guard**: it isn't an optimization, and a cut-out PNG can be bigger than the JPEG it came from. The card shows "Done" plus "Background removed" or "Background: #HEX".
- **Custom** (both menus): you can't type mid-drag, so dropping on Custom shows a small panel beside the bubble (`Bubble/InputPanel.swift`). Size: a number plus KB/MB (decimal, as Finder shows). Color: a hex field, 8 preset swatches and the system eyedropper (`NSColorSampler`). It takes the keyboard without activating the app, handles ⌘C/⌘V itself (menu bar apps have no Edit menu), Return confirms, Esc or Cancel cancels, and clicking the bubble cancels. The last size pre-fills the field; the last color becomes its own bubble next time (`OptionMemory`, UserDefaults).
- **Geometry** (`SubmenuLayout`, `MenuGeometry` in `Bubble/BubbleLayout.swift`): options sit 56 pt beyond the main ring, centered on their segment's angle but clamped within 85° of straight into the screen, so none goes past the edge. Past the midpoint between the rings the pointer picks options; inside it, segments. Options stay open while the pointer is out among them. The bubble now keeps ~180 pt from the top and bottom of the screen so the outer ring fits (`BubbleLayout.verticalClearance`).

**Verified:**

- `scripts/check-linux.sh`: every file parses; **62 portable tests pass on Linux**, including exact PNG round trips (checked by a test-only PNG reader that verifies CRCs and undoes filters itself), exact lossless WebP, lossy WebP closeness, alpha kept, naming, size guard, writer, plans.
- CI on macOS: see the Snapshot. The macOS tests (`Tests/PipelineMacTests.swift`) cover EXIF rotation, P3→sRGB conversion, transparency, half size, ImageIO reading our PNG/WebP exactly, real files end to end, Rule 2 (original untouched), Rule 3 (nothing written when it can't get smaller), clashes, and batch plus clipboard.

**Not verified (needs a person on a Mac):** the feel, including reaching the option bubbles mid-drag; the window behaviour (see *Risks*); typing into the Custom panel while another app is in front; **Remove BG quality on real photos** (CI ran Vision on a synthetic image, which it may not treat as a subject; the tests accept either outcome); how the clipboard pastes into Figma, Slack, Chrome, Notes and Messages (CORE.md §6.6); and real-world savings on a variety of images.

## ✱ Next steps (in order)

1. **Make sure CI is green** on the branch. If it's red, open the run, read the failing step's log and fix it. Use `mcp__github__get_job_logs` with `failed_only: true` if you don't have a browser.
2. **Owner tries the preview DMG** (the Snapshot link). History: on 2026-10-30 they said they couldn't run it on their Mac (reason never confirmed); they were given step-by-step DMG instructions, saw the Phase 0 build's pretend actions, asked for real functionality, and approved libwebp. Ask what they saw with real files, and fix what they report. Run through the *Manual test checklist* below as far as they're willing; tune `Bubble/Motion.swift` from their feedback.
3. **Phase 1 step 2** (`CORE.md` §11), still to do: the **Auto classification** (photo → lossy WebP; graphic → lossless WebP vs PNG, smaller wins; replace `RGBAImage.looksLikeGraphic`), and the fuller PNG pipeline once **free vs paid** is decided (pngquant is GPL).
4. **JobQueue** (`CORE.md` §5): drops while a job runs are still ignored (`BubbleController.dragEntered` returns false while working). Make new drops queue, and move cancellation into the queue.
5. Phase 1 step 3: SSIMULACRA 2 auto-tune (replaces the fixed values in `EncoderTuning`). (Step 4, Remove BG, is done.)
6. Smaller items: accept file promises (`NSFilePromiseReceiver`) so drags from Photos, Safari and Mail work; post a notification for jobs over ~10s; a Settings window (`CORE.md` §10).

## ✱ Risks to check first on a real Mac

1. **Drags between segments.** Transparent pixels let drags fall through to the window below, so the open menu draws a near-invisible disc (`Motion.hitCatchOpacity` = 0.01). If the menu collapses when crossing a gap, raise it.
2. **Growing the panel mid-drag.** The panel is resized inside `draggingEntered`. If hover or the drop misbehaves right after the menu opens, check `draggingUpdated` keeps arriving.
3. **Hover on a non-key panel.** This relies on the `.activeAlways` tracking area in `BubbleHostView`.
4. **Folder permission prompts.** Saving next to a file in Desktop, Documents or Downloads makes macOS ask for access to that folder once. With ad-hoc signing, every new build has a new identity, so it may ask again after each DMG update. Developer ID signing (Phase 3) fixes that.
5. **JPEG and HEIC through ImageIO** embed an sRGB ICC profile (~3 KB), which matters on small JPEGs. jpegli replaces this.
6. **Option bubbles mid-drag.** Moving outward from Compress to a size bubble is a longer reach. If it feels fiddly, tune `Motion.optionRingDistance`, `optionDiameter` and the boundary in `SubmenuLayout.innerBoundary`.
7. **Custom panel focus.** It relies on a `.nonactivatingPanel` becoming key while another app stays active. If typing doesn't reach it, the fallback is `NSApp.activate()` while it's open (which breaks Rule 1 briefly).
8. File promises aren't handled yet (see step 6). Haptics only fire on Force Touch trackpads.

## Manual test checklist

1. Launch: no Dock icon, a drop icon in the menu bar, and the bubble on the right edge, vertically centered, at about 60% opacity.
2. Hover: full opacity and a slight grow.
3. Drag the bubble toward the left: it springs to the left edge. Quit and relaunch: it's still there.
4. Drag a PNG from Finder over it: the bubble grows and 5 segments fan out with a stagger. Hover each: it highlights, its label shows in the bubble, and there's a haptic tick.
5. Hover **Convert** and drop on **WebP**: ripple, spinner, checkmark, and a card with the real saving and a thumbnail. `photo.webp` appears next to the original. Paste in Finder (the file) and in Notes (the picture).
6. **Compress** a screenshot PNG → `-min.png`; a camera JPEG → `-min.jpg`. **Half size** → `-half` at half the width and height.
7. Compress the `-min.png` again: shake and "Already as small as it gets.", and no new file.
8. Drag the card into a Finder folder (it copies), and onto a Slack or Chrome upload field. Click the card: Finder reveals the new file.
9. Drop 10 images at once on Compress: the count goes up, then "10 files" on the card.
10. Hover **Compress**: six small bubbles fan out. Drop on **500K** with a big photo → `photo-500kb.jpg` under 500 KB. Drop on **…** → a size panel; type 300, KB, Return.
11. Hover **Remove BG**: None · White · Black · … Drop a portrait on **None** → `-nobg.png` with a transparent background. Drop on **…** → a color panel; try a hex, a swatch and the eyedropper. Next time, that color is its own bubble.
12. **Convert → AVIF** on a photo → `photo.avif`, usually smaller than the WebP. **Convert → JPG** on a transparent PNG → white background and a note. **Convert → PNG** on a WebP → a PNG even if it's bigger. Quick Look shows it. A `.mov`: the video menu, then "Video is coming soon."
13. Drag a `.txt` over it: "Can't open this file type yet." while over, gone on exit.
14. While a big batch works: hovering shows ×, and a click cancels.
15. Type in TextEdit and drop on the bubble mid-sentence: TextEdit keeps focus.
16. Menu bar → **History…**: every file you made, newest first. Double-click one (Finder), drag one into Slack, right-click → Copy. Clear History asks first.
17. Switch Spaces and enter a full-screen app: the bubble is still there. ⌃⌥⌘D hides and shows it.
18. Turn on Reduce Motion (System Settings → Accessibility → Display): fades only. Check light and dark mode.
19. With two displays: move the bubble to the second one, relaunch, and it's still there.

## ✱ Decisions made so far (also in `CORE.md` §14)

- The bubble docks to the **left or right** edge only. The top has the menu bar and the bottom usually the Dock.
- The menu is a **160° arc facing into the screen**, segments top to bottom, instead of a full ring. The ring grows for 6 segments so neighbours never touch.
- The hovered action's **label shows inside the bubble**, because the drag image covers the segment. Segments are picked **by angle** outside the center.
- Results and messages appear **beside the bubble**, on the side facing into the screen.
- **libwebp 1.6.0** (BSD-3), approved by the owner. It's built from the pinned, SHA-256-checked release by `scripts/build-deps.sh`, not committed (`Vendor/` is generated).
- **libaom 3.15.2 + libavif 1.4.2** (BSD-2, plus the AOM Patent License 1.0, royalty-free), approved by the owner. libaom comes from its checksummed release tarball; libavif is cloned at the pinned commit of tag v1.4.2 (its GitHub tarball can't be downloaded through the agent proxy, and a pinned commit is just as reliable). Built with CMake; `nasm` makes the Intel slice fast (CI installs it).
- PNG Compress uses **our own lossless optimizer** with the system zlib, so it's license-free while free vs paid is open. JPEG and HEIC use **ImageIO** until jpegli.
- **Auto = WebP** until classification (Phase 1 step 2). Half size uses the suffix **`-half`**.
- **Option bubbles** (owner's choice): Compress → target file sizes 100 KB · 250 KB · 500 KB · 1 MB · 2 MB · Custom. Background choices live **inside Remove BG** (None · White · Black · last color · Custom hex), not as a separate bubble. Custom values are asked for after the drop. Sizes are decimal (1 KB = 1000 bytes). Hitting a size shrinks the image only as a last resort, and says so.
- **Remove BG is exempt from Rule 3** (never bigger): it changes content rather than optimizing. Always PNG.
- **Menu: Convert replaces the separate WebP and AVIF buttons** (owner approved): Convert → WebP · AVIF · JPG · PNG · HEIC. Conversions only into formats web pages and uploads take; no general-purpose conversion (PDF, SVG, RAW, documents). **Conversions to another format are exempt from Rule 3.**
- Fixed encoder settings in `EncoderTuning` (`Image/RGBAImage.swift`) until auto-tune: WebP q80/method 4, JPEG 0.8, HEIC 0.75.
- If the original's folder is read-only, results go to **Downloads**.
- **Swift 5 language mode** for now. Ad-hoc signing; hardened runtime on Release only (Phase 3 switches to Developer ID).
- CI runs on GitHub's macOS runners (free: the repo is public) and publishes a DMG, a zip and `install.sh` to the public `preview` release (the owner approved). Updates are a Terminal one-liner for now; an in-app "Check for Updates" arrives with Sparkle (Phase 3), since the app itself makes no network calls (Rule 4).

## ✱ Questions for the owner

1. **Free/open-source or paid?** ("Decide later" for now.) It decides pngquant (better PNG compression), x264/x265 and gifski.
2. Is the label inside the bubble right, or would you rather see it next to the hovered segment?
3. Is ⌃⌥⌘D OK as the show/hide shortcut?

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

**Without Xcode** (how the owner runs it): in Terminal, run `curl -fsSL https://github.com/bimanshu/Droptimize/releases/download/preview/install.sh | bash`. `scripts/install.sh` checks for macOS 14+, downloads `Droptimize.zip` from the preview release, verifies the signature, quits the running copy, swaps the app in `/Applications` (or `~/Applications` if that isn't writable) and opens it. curl downloads aren't quarantined, so no Gatekeeper step. CI runs it on every build (fresh install, then update) before publishing. The same works for a first install. By hand instead: download the DMG from https://github.com/bimanshu/Droptimize/releases/download/preview/Droptimize.dmg, open it, and drag Droptimize into Applications. Run `xattr -cr /Applications/Droptimize.app` (it's ad-hoc signed, so Gatekeeper blocks it until Phase 3 notarization), then open it. It needs macOS 14+. There's no window or Dock icon: look for the drop icon in the menu bar and the bubble on the right edge of the screen. The DMG also contains `READ ME FIRST.txt` (from `scripts/dmg-readme.txt`; keep it current when the steps or features change).

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
| `Pipeline/Output.swift` | Portable: `OutputNaming`, `SizeGuard` (Rule 3), `OutputWriter` (never overwrites; Downloads fallback). |
| `Pipeline/ImageJobRunner.swift` | macOS: `ImageOptimizer` (one file: plain, compress-to-fit, Remove BG) and `ImageJobRunner` (parallel batches, clipboard, notes). |
| `Pipeline/Clipboard.swift` | macOS: file URLs plus a PNG picture on the pasteboard. |
| `Pipeline/History.swift` | Portable: `HistoryEntry`, `HistoryLog` (newest first, 500 max, Recent, totals), `HistoryFile` (JSON in Application Support), `ActionOption.title`. |
| `App/HistoryWindow.swift` | macOS: `HistoryStore` (saves on every change), the History window and its rows. |
| `Modules/module.modulemap` | Lets Swift import libwebp (`CWebP`), libavif + libaom (`CAvif`) and zlib (`CZlib`, where the SDK has no `zlib` module). |
| `scripts/build-deps.sh` | Builds pinned libwebp, libaom and libavif into `Vendor/` (universal static libs on macOS, host builds on Linux). Needs cmake, and nasm for a fast Intel slice. |
| `scripts/check-linux.sh` | Parse, build libwebp, and run the portable tests without a Mac. |
| `scripts/install.sh` | One-command install/update from the preview release (published as a release asset; tested in CI). |
| `scripts/dmg-readme.txt` | The "READ ME FIRST" note inside the DMG. |
| `.github/workflows/build.yml` | macOS CI: deps (cached), generate, build, test (warnings fail), universal Release build, DMG and zip, install-script test; then publishes DMG, zip and `install.sh` to the `preview` release. |
| `Tests/` | XCTest. Portable (also run on Linux): `LayoutTests`, `DockPositionTests`, `SpringTests`, `ActionTests`, `OutputTests`, `EncoderTests`, `OptionTests`, `AVIFTests`, `HistoryTests`, `Support/TestPNGReader` (test-only PNG reader plus test images). macOS only: `MacTests`, `PipelineMacTests`, `OptionMacTests`. |

## How the bubble works (so you don't have to rediscover it)

- **Events go through AppKit only.** `BubbleHostView.hitTest` returns itself, so the SwiftUI canvas never gets events. The host view calls `BubbleController`, which changes `BubbleModel`, and the SwiftUI views re-render with implicit `.animation(_:value:)` animations.
- **Fixed canvas, resizing window.** The SwiftUI canvas is a fixed square (`BubbleLayout.canvasSide`) always centered on the bubble. Only the panel's frame changes per state (`BubbleLayout.panelFrame`), and `host.bubbleCenter` repositions the canvas so nothing visibly moves. The panel grows at once, so segments are real drop targets straight away. It shrinks after `Motion.collapseSettle` so the fold-in and ripple can finish.
- **Coordinates.** The controller works in screen coordinates (`center` is the bubble's center on screen) and reads the pointer with `NSEvent.mouseLocation`. Geometry offsets use y-up; SwiftUI offsets negate `dy`.
- **Phases.** `BubbleModel.Phase` decides the panel content: `.idle` and `.working` → bubble only, `.menu` → arc, `.done` and `.message` → accessory beside the bubble.
- **Drag in vs drag out.** The host view ignores drags it started itself (`isOwnDrag`), and as a drag source it only allows `.copy` outside the app.

## How an image is processed

`BubbleController.drop` → `ImageJobRunner.run` (parallel, off the main thread) → per file `ImageOptimizer.process`: `ImagePlan.scale(for:)` (fails fast for unbuilt actions) → `ImageDecoder.decode` (orientation, sRGB, optional half size) → `ImagePlan.make` (encoder, extension, suffix) → encode → `SizeGuard` → `OutputWriter` → back on the main actor: `Clipboard.put`, then the done card with a QuickLook thumbnail of the first output.

# Handoff

> **Read this first, then `CORE.md`.** This file says where the work stands right now and exactly what to do next. `CORE.md` says what we're building and the rules.
> Whoever ends a session updates the ✱ sections before pushing. Keep it current, not historical: history goes in `CORE.md` §14 and the git log.

## ✱ Snapshot

| | |
|---|---|
| Last updated | 2026-10-30 |
| Branch | `claude/fervent-thompson-2620yn` (the only branch so far; no `main` yet, nothing merged, no PR) |
| Phase | **0: code complete, compiles and passes tests in CI, not yet run by a person on a Mac** |
| CI | [Build workflow](https://github.com/bimanshu/Droptimize/actions/workflows/build.yml): green on this branch (Xcode 16.4, macOS 15 runner). Compiler warnings fail the build. |
| Next | Get the owner (or an agent with a Mac) to run it and tune the feel, then start Phase 1 |

## ✱ Where things stand

**Done (Phase 0, `CORE.md` §11):**

- Menu bar app (no Dock icon) with a status item: Show/Hide Bubble, Recent, Settings (disabled until Phase 1), Quit.
- Global show/hide shortcut **⌃⌥⌘D** (Carbon hot key, no permission needed).
- Floating bubble in a non-activating `NSPanel`: on every Space and over full-screen apps, never takes focus.
- Drag the bubble to move it. It springs (custom spring, display-synced) to the nearest **left or right** edge and remembers its place per display.
- A file drag over the bubble grows the panel, and segments fan out on an arc facing into the screen with a stagger. Hovering a segment highlights it, shows its label inside the bubble and plays a haptic tick. Drop on the center = Auto. Drag out = collapse.
- Image, video and mixed menus as in `CORE.md` §4.2. Unsupported files show "Can't open this file type yet." while over the bubble.
- Drop gives a ripple, then a **fake** ~1s job (progress ring, batch count "3/12", hover shows ×, click cancels), then the done state: a checkmark plus a card with a thumbnail and "−NN%". Drag the card into any app, or click it to reveal in Finder. The card stays while hovered and leaves after ~4s.
- Error state: shake plus a one-line pill. **Option-drop simulates "Already as small as it gets."** (a Phase 0 testing aid; remove in Phase 1).
- Reduce Motion: fades only (no scale, fan-out, stagger, ripple or shake). VoiceOver labels on the bubble, segments and card. Light/dark mode via system materials.
- Unit tests: radial layout and hit-testing, panel sizes, dock position and persistence, spring, action menus, media type detection, SF Symbols exist, saving text.

**Verified:**

- `scripts/check-linux.sh` passes (every file parses, 32 portable tests pass).
- CI on macOS (Xcode 16.4): the app compiles, **35/35 tests pass**, the Release build is universal (`x86_64 arm64`), and it's uploaded as the `Droptimize-app` artifact. Zero warnings since the thumbnail `Sendable` fix (check the latest run; if it's red, fixing it is step 1).

**Not verified (needs a person on a Mac):** everything about the feel and the window behaviour. See *Risks* below.

## ✱ Next steps (in order)

1. **Make sure CI is green** on the branch. If it's red, open the run, read the failing step's log and fix it. Use `mcp__github__get_job_logs` with `failed_only: true` if you don't have a browser.
2. **Run Phase 0 on a Mac and tune it** (owner, or an agent on a Mac). Work through the *Manual test checklist* below and adjust `Bubble/Motion.swift` by feel. Phase 0 is done when it feels right and never steals focus. Record the tuned values and any changes in `CORE.md` §14.
3. **Owner decisions needed before Phase 1 goes far** (see *Questions for the owner*): free vs paid (decides pngquant), and how we bundle encoders.
4. **Phase 1, step 1** (`CORE.md` §11), suggested order:
   1. `Pipeline/Output.swift`: output naming (`photo.webp`; same format → `photo-min.png`; clash → `photo-min-2.png`), the size guard (Rule 3), saving next to the original, and the clipboard (file URL plus PNG/TIFF image representation). Unit-test the naming and the size guard.
   2. `Pipeline/JobQueue.swift`: an actor with concurrency limits and cancellation that replaces the direct `Task` in `BubbleController.start`. Let new drops queue instead of being ignored while a job runs.
   3. `Image/Decode.swift` and `Image/Normalize.swift`: ImageIO decode, EXIF orientation applied, sRGB, metadata stripped, alpha kept. Add tests for each.
   4. Encoders behind one `ImageEncoder` protocol. Begin with ImageIO for JPEG/PNG to get the whole flow working end to end, then add `scripts/build-deps.sh` and `Vendor/` for libwebp and jpegli (`CORE.md` §8). ImageIO can't write WebP, so WebP needs libwebp.
   5. Replace `FakeJobRunner` with the real image runner, and remove the Option-drop failure.

## ✱ Risks to check first on a real Mac

These are assumptions the code relies on that couldn't be tested without a Mac:

1. **Drags between segments.** Transparent pixels let clicks and drags fall through to the window below, so the open menu draws a near-invisible disc (`Motion.hitCatchOpacity` = 0.01) to keep catching the drag. If the menu collapses when the pointer crosses a gap, raise that value.
2. **Growing the panel mid-drag.** The panel is resized inside `draggingEntered`. If hover or the drop misbehaves right after the menu opens, check `draggingUpdated` keeps arriving after the resize.
3. **Hover on a non-key panel.** This relies on the `.activeAlways` tracking area in `BubbleHostView`.
4. **File promises aren't handled.** Only file URLs are read. Drags from Photos, Safari images or Mail attachments won't open the menu yet. Add `NSFilePromiseReceiver` in Phase 1.
5. **Fake outputs are the originals.** In Phase 0, dragging the card out copies the original file. Nothing is ever written or moved: the drag source only allows Copy, and only outside the app.
6. Haptics only fire on Force Touch trackpads.

## Manual test checklist (Phase 0)

1. Launch: no Dock icon, a drop icon in the menu bar, and the bubble on the right edge, vertically centered, at about 60% opacity.
2. Hover: full opacity and a slight grow.
3. Drag the bubble toward the left: it springs to the left edge. Quit and relaunch: it's still there.
4. Drag a PNG from Finder over it: the bubble grows and 5 segments fan out with a stagger. Hover each one: it highlights, its label shows in the bubble, and there's a haptic tick.
5. Drop on a segment: ripple, ~1s progress ring, checkmark, and a card with "−NN%" and a thumbnail. The card stays while hovered and leaves about 4s after.
6. Drag the card into a Finder folder: it copies. Drop it on a Slack or Chrome upload field. Click the card: Finder reveals the file.
7. Option-drop: shake and "Already as small as it gets."
8. Drag a `.txt` over it: "Can't open this file type yet." while over, gone on exit.
9. Drag a `.mov`: the video menu. Drag images and a video together: only Compress around Auto.
10. During the fake job: hovering shows ×, and a click cancels.
11. Type in TextEdit and drop on the bubble mid-sentence: TextEdit keeps focus and typing continues.
12. Switch Spaces and enter a full-screen app: the bubble is still there.
13. ⌃⌥⌘D and the menu item both hide and show the bubble.
14. Turn on Reduce Motion (System Settings → Accessibility → Display): fades only.
15. Check light and dark mode.
16. With two displays: move the bubble to the second one, relaunch, and it's still there.

## ✱ Decisions made so far (also in `CORE.md` §14)

- The bubble docks to the **left or right** edge only. The top has the menu bar and the bottom usually the Dock.
- The menu is a **160° arc facing into the screen**, segments ordered top to bottom, instead of a full ring. A docked bubble would put half a ring off-screen. The ring grows when there are 6 segments so neighbours never touch.
- The hovered action's **label shows inside the bubble**, because the drag image under the pointer covers the segment itself.
- Segments are picked **by angle** once outside the center (pie-menu style), which is forgiving at drag speed.
- Results and messages appear as a card or pill **beside the bubble**, on the side facing into the screen.
- While a job runs, new drags are ignored until the JobQueue exists (Phase 1).
- **Swift 5 language mode** for now; move to Swift 6 strict concurrency later. Ad-hoc signing; hardened runtime on Release only (Phase 3 switches to Developer ID).
- CI runs on GitHub's macOS runners, which are free because the repo is public.

## ✱ Questions for the owner

1. Is the label inside the bubble right, or would you rather see it next to the hovered segment?
2. Is ⌃⌥⌘D OK as the show/hide shortcut?
3. Still open from `CORE.md` §13: free/open-source or paid? This decides pngquant (GPL), x264/x265 and gifski, and it's needed early in Phase 1 for the PNG pipeline.

## How to build, run and test

**On a Mac** (macOS 14+, current Xcode):

```bash
brew install xcodegen
```

```bash
xcodegen generate && open Droptimize.xcodeproj
```

Then Run (⌘R) or Test (⌘U). From the command line:

```bash
xcodegen generate && xcodebuild test -project Droptimize.xcodeproj -scheme Droptimize -destination 'platform=macOS'
```

To try a CI build without Xcode, download `Droptimize-app` from a run's artifacts, unzip it, and run `xattr -cr Droptimize.app` (it's ad-hoc signed and quarantined) before opening it.

**Checking code without a Mac** (Linux containers, like the one used to write Phase 0): AppKit and SwiftUI can't compile on Linux. Download a Swift toolchain (about 900 MB; Swift 6.1.2 for Ubuntu 24.04 is at `https://download.swift.org/swift-6.1.2-release/ubuntu2404/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-ubuntu24.04.tar.gz`), extract it, put its `usr/bin` on `PATH`, then run:

```bash
./scripts/check-linux.sh
```

It parses every Swift file and runs the portable tests. When you add Foundation-only code with tests, add it to the lists at the top of the script. Then push and read CI for the real compile.

## Map of the code

| File | What it does |
|---|---|
| `project.yml` | XcodeGen spec (app and test targets, macOS 14, LSUIElement). The `.xcodeproj` is generated and git-ignored. |
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
| `Bubble/BubbleView.swift` | SwiftUI drawing: bubble, glyphs, progress ring, card, message pill, ripple, shake. |
| `Bubble/RadialMenu.swift` | SwiftUI segments with fan-out and stagger. |
| `Bubble/Thumbnails.swift` | QuickLook thumbnails for the card. |
| `Pipeline/Action.swift` | `Action` (titles, SF Symbols, VoiceOver labels), `MediaKind`, `ActionMenu`. |
| `Pipeline/MediaKind+Files.swift` | Image/video detection from a URL via UTType. |
| `Pipeline/Job.swift` | `Job`, `JobProgress`, `JobResult`, `JobError` (the user-facing lines), and the `JobRunner` protocol. |
| `Pipeline/FakeJobRunner.swift` | Phase 0 stand-in. Delete in Phase 1. |
| `Tests/` | XCTest. `LayoutTests`, `DockPositionTests`, `SpringTests` and `ActionTests` are portable (they also run on Linux). `MacTests` needs AppKit. |
| `scripts/check-linux.sh` | Parse and portable tests without a Mac. |
| `.github/workflows/build.yml` | macOS CI: generate, build, test, universal Release build, zipped app artifact. |

## How the bubble works (so you don't have to rediscover it)

- **Events go through AppKit only.** `BubbleHostView.hitTest` returns itself, so the SwiftUI canvas never gets events. The host view calls `BubbleController`, which changes `BubbleModel`, and the SwiftUI views re-render with implicit `.animation(_:value:)` animations.
- **Fixed canvas, resizing window.** The SwiftUI canvas is a fixed square (`BubbleLayout.canvasSide`) always centered on the bubble. Only the panel's frame changes per state (`BubbleLayout.panelFrame`), and `host.bubbleCenter` repositions the canvas so nothing visibly moves. The panel grows at once, so segments are real drop targets straight away. It shrinks after `Motion.collapseSettle` so the fold-in and ripple can finish.
- **Coordinates.** The controller works in screen coordinates (`center` is the bubble's center on screen) and reads the pointer with `NSEvent.mouseLocation`. Geometry offsets use y-up; SwiftUI offsets negate `dy`.
- **Phases.** `BubbleModel.Phase` decides the panel content: `.idle` and `.working` → bubble only, `.menu` → arc, `.done` and `.message` → accessory beside the bubble.
- **Drag in vs drag out.** The host view ignores drags it started itself (`isOwnDrag`), and as a drag source it only allows `.copy` outside the app.

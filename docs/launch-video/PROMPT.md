# Droptimize launch film: the prompt

Written 2026-11-02 from the owner's references (`reference-notes.md`; video A is the favourite and the sound to follow), in the owner's prompt structure (`prompt-reference.md`). Give everything below the line to the agent that makes the film.

---

<inputs>
Already decided. Don't ask again:
- Product: Droptimize, a Mac menu-bar app. Drag any image or video onto a small floating bubble at the screen edge; a radial menu fans out (Convert, Compress, Half size, Remove BG, with Auto in the middle); let go on one and a smaller, web-ready file comes back, saved next to the original and copied to the clipboard. Everything happens on the Mac; nothing is uploaded. Free for 3 files a day; Pro is $9.99 once.
- Font: Geist for everything, Geist Mono for file names and sizes (both SIL Open Font License).
- Palette: light warm-grey canvas `#EDEBE8` with a 1 px grid `#E1DED9` every 48 px; near-black UI `#0E0E0F`; white chips; one accent, Droptimize mint `#3DDC97` (the dot in the app icon), used only for the motif dots, the progress ring and success states.
- Voice-over: ElevenLabs voice "Emma, Professional Commercial Voice" (`voice_id 9HBoEQ8LqyvVZFYDodnr`), model `eleven_v4`. Clear, confident, polished; not hyped. Script in <structure>.
- Format: 1920×1080, 60 fps, about 31 s: 14 bars at 120 BPM (28 s), then 3 s of silence on the end card.

Ask me only for:
1. A royalty-free track (commercial use allowed: Pixabay, Uppbeat, Mixkit…) near 120 BPM that sounds like <direction>'s sound notes, or my OK to shortlist three for me to choose from.
2. Four cold-open photos (Unsplash or Pexels licence, credits listed), or my OK to pick them.
3. The website URL for the end card (the site isn't live yet; leave a placeholder until I give one).
</inputs>

<direction>
Apple-grade launch film: calm, confident, precise. Inspiration (never copy): the "One" launch film, with clean Grok "Build Mode" restraint and a "holo"-style word list.

Look:
- A cinematic cold open of full-bleed photos.
- Then one continuous take on the warm-grey canvas. The camera glides, pushes in and racks between moments; the UI is the hero.
- Shapes carry across scenes as match cuts. The cold open's four corner ticks become four mint dots, and the dots frame every headline.
- Headlines are large, left-aligned, tight tracking (−2%), and arrive word by word: each word blurs in from 10 px with an 8 px rise, landing on a beat.
- Panels are near-black with a 22 px radius and 12–13 px text. They arrive with a slight 3D tilt (rotateY −8° to 0) that settles flat.
- The real Droptimize UI, drawn faithfully at 2.5× its true size:
  - **Bubble:** 44 pt circle, frosted, nested-circles logo, 60% opacity at rest, ×1.06 on hover, ×1.2 when a drag arrives.
  - **Menu:** a 160° arc facing into the screen, ring radius 80 pt, 40 pt segments fanning out 25 ms apart, ×1.15 on hover, the hovered label shown inside the bubble.
  - **Option bubbles:** 34 pt, 56 pt beyond the ring, 20 ms apart.
  - **Progress:** a 54 pt ring with a 3 pt line.
  - **Feedback:** a 0.4 s ripple on drop; the result card (thumbnail, "−96%", file name) beside the bubble.
  - **Glyphs:** SF Symbols, all at one stroke weight: Convert `arrow.triangle.2.circlepath`, Compress `rectangle.compress.vertical`, Half size `arrow.down.right.and.arrow.up.left`, Remove BG `scissors`, Auto `wand.and.stars`.
- A cursor drives everything with real drags and drops; sizes count down like an odometer.
- Springs everywhere, closed-form. UI: response 0.35 s, damping 0.75 (the app's own values; ~3% overshoot at most). Hover: 0.2 s / 0.8. Camera: 0.8 s / 1.0 (no overshoot).

Sound (match the feel of reference A, measured):
- **Tempo:** 120 BPM; start on a downbeat.
- **Intro:** the first ~2.5 s has no bass at all, only airy filtered mids around 1–2 kHz.
- **Drop:** the sub-bass enters on bar 2, beat 2, exactly at the match cut to the canvas.
- **Groove:** not four-on-the-floor. Syncopated, sustained sub-bass notes, soft plucked stabs, sparse hats. The top end is rolled off (8–11 kHz sits ~24 dB under the mids), so it's warm and round, never bright.
- **Breaths:** before big reveals, drop the top end out for exactly one beat.
- **Ending:** one deep sub hit on the final logo, a ~2 s low-passed tail, then silence.
- **UI sounds:** dry, soft and low in the mix (about 18 dB under the music): a soft tick per menu-segment hover (like a trackpad haptic), a low "thup" on drop, a short airy swish on the ripple, a felt click per keycap, quiet ticks as numbers count. No chimes, no risers, no whooshes louder than the music.
- **Voice:** Emma sits on top, warm and close. Duck the music 8 dB under her (80 ms attack, 250 ms release).

Banned: bouncy easing, particle bursts, glows, gradients on UI chrome, lens flares, mismatched icon strokes, dead time, stock-template transitions, fake brand logos, any real company's UI or logo.
</direction>

<structure>
120 BPM, 14 bars (bar.beat). Something happens on every beat. VO lines start on the beat shown; their first syllable lands on it. Emma reads at about 2.3 words a second, so every line ends before the next one starts (about 55 words, 22 s of speech, roughly 320 credits).

1. **1.1–2.1 · Cold open** (no bass).
   - Four full-bleed photos cut on every half bar. Each is framed by four white corner ticks and carries a mono chip with its real-world heft: `IMG_2041.HEIC · 12.4 MB`, `launch.mov · 840 MB`, `hero.png · 6.1 MB`, `shoot.tiff · 48 MB`.
   - VO at 1.2: "Your files are too heavy." (It ends just before the bass drops.)
2. **2.2 · Drop.** The bass enters. Match cut: the corner ticks fly to become four mint dots on the warm-grey grid. The Droptimize bubble rests at the right edge.
   - Headline, word by word: "Drop it."
   - VO at 2.4: "Meet Droptimize."
3. **3.1–4.4 · The core move.**
   - The cursor drags the `IMG_2041.HEIC · 12.4 MB` thumbnail to the bubble. It wakes to ×1.2 and the arc fans out, one segment per 16th note.
   - Hover ticks pass over Convert and then Compress; the label inside the bubble swaps; Compress's size bubbles fan out (100K · 250K · 500K · 1M · 2M · …).
   - Drop on 500K at 4.1: ripple, then the progress ring, then a check. The result card slides out beside the bubble while `12.4 MB` odometers down to `486 KB` and "−96%" lands on 4.4.
   - The headline completes: "Drop it. Done."
   - VO at 3.1: "Drop any photo or video on the bubble. Done."
4. **5.1–6.4 · Convert.**
   - A left-hand word list in the "holo" manner: Convert · Compress · Half size · Remove BG, the active word black with a mint dot, the rest 30% grey.
   - Convert's formats run past as a horizontal carousel with motion blur (WebP · AVIF · JPG · PNG · HEIC) and settle on AVIF. `hero.png 6.1 MB` becomes `hero.avif 412 KB`.
   - VO at 5.1: "Convert to WebP or AVIF in one move."
5. **7.1–8.4 · Remove BG.**
   - The word list steps to Remove BG. A portrait drops on it; the subject lifts off over a checkerboard.
   - Background chips (None · White · Black · a custom hex) appear; the cursor picks one, the eyedropper samples a colour, and the background fills on 8.1.
   - Breath: drop the top end out on 6.4.
   - VO at 7.1: "Lift the background right out."
6. **9.1–10.4 · Video.**
   - `launch.mov · 840 MB` drops on Compress, then on "Under 25 MB". The progress ring fills for real, one segment per beat; the size counts down to `24.1 MB`.
   - Convert offers GIF: one beat of a looping GIF thumbnail.
   - VO at 9.1: "Videos too, down to whatever size you need."
7. **11.1–11.4 · Private.**
   - A panel expands to fill the frame and the scene goes near-black (as in the reference's dark section). A small Mac outline, files moving only inside it, nothing leaving.
   - Headline: "Never leaves your Mac."
   - VO at 11.1: "All on your Mac. Nothing uploaded."
8. **12.1–13.2 · Many at once, already pasted.**
   - Back to light. Ten files drop in a stream; the bubble counts 1/10 → 10/10 and the card reads "10 files · −81%".
   - Physical keycaps ⌘ and V press on 13.1–13.2 (black rounded keys with a 3 px press depth); the image pastes into a plain, unbranded chat composer.
   - VO at 12.2: "Batches in one drop. Already on your clipboard."
9. **13.3–14.4 · End.**
   - The result card pushes toward the camera and blurs away. The nested-circles logo stays alone, then cross-fades to the first cold-open photo, now chipped `486 KB`.
   - End card: logo, "Droptimize", "Drop it. Done.", "Free to start · Pro $9.99 once", the URL.
   - The deep sub hit lands on 14.1, then the tail, then 3 s of silence.
   - VO at 14.1: "Droptimize. Drop it. Done."
</structure>

<build>
1. One HTML file, 1920×1080. Every style is computed from time inside `seek(t)`: no CSS transitions, no timers, no state carried between frames. Fonts are loaded locally (Geist, Geist Mono) and awaited before the first frame.
2. Springs are closed-form step responses. A value that changes target many times is the sum of one spring per change, so it stays a pure function of time.
3. Stretchy pairs ride two springs, so the leading edge runs ahead of the trailing one: the menu arc's fan, the word-list dot, the carousel's selection pill.
4. Drags are direct manipulation: while the cursor is held, positions follow it exactly; on release, they spring from wherever they were. The cursor follows smooth paths with human ease-in/out, never linear.
5. **Music:** analyse the track with numpy (onset envelope, autocorrelation) for the beat grid; start on a downbeat. If the track has no bass-less intro, high-pass the first 2.5 s at 250 Hz and cross-fade into the full mix on 2.2. End with a 2 s low-pass sweep after the final hit.
6. **Voice:**
   - Generate each VO line separately with ElevenLabs (`voice_id 9HBoEQ8LqyvVZFYDodnr`, `eleven_v4`, **one take per line**, price it with `estimate_only` first). Owner's rule: stay within the Starter plan's credits, nothing extra.
   - Trim the silence; place each line so its first syllable's measured onset hits its beat.
   - High-pass the voice at 90 Hz and sidechain-duck the music under it (ffmpeg `sidechaincompress`).
7. **UI sounds:** synthesise them with numpy (short filtered-noise bursts, soft sine blips). Don't use paid sound-effect generation. Place each by its measured peak on the frame of the event.
8. **Render:** Playwright, 4 subframes per frame blended with ffmpeg `tmix` for motion blur, at 60 fps. Then mux the audio with AAC 256 kbps and export H.264 High (CRF 16) plus a ProRes 422 master.
9. Render one frame per beat before the full render. Fix anything off the grid, cramped, hard to read or with text overlapping.
</build>

<gotchas>
- **Sharp text:** never put `will-change` on anything the camera scales, or the text renders blurry; keep text on whole pixels at rest.
- **Text swaps:** text that swaps inside a morphing container needs its own enter and exit timing, or it overlaps.
- **UI accuracy:** the radial menu faces into the screen (the bubble sits at the right edge, so the arc opens to the left), and the option bubbles never cross the screen edge. Labels show inside the bubble, not on the segments.
- **Numbers:** sizes and percentages must agree: 12.4 MB → 486 KB is −96%; 6.1 MB → 412 KB is −93%; 840 MB → 24.1 MB is −97%.
- **Voice timing:** no VO line may run over the next line's beat. If one is long, shorten the copy rather than speed up the voice.
- **Clean ending:** the last 3 s is a still end card in silence; no motion and no tail noise after the low-pass ends.
</gotchas>

<start>
Ask me only for the missing inputs (track, photos, URL). Then show me the beat grid as a table (bar.beat → picture, VO line, sound) and the VO credit estimate before you write any code.
</start>

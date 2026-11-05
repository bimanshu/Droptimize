"""Makes the vertical reel (1080 × 1920) of film v4 from v4.html: same scenes, timing, voice, music and photos,
re-laid out for a phone. Run from docs/launch-video/film/ after any change to v4.html:

    python3 make-reel-v4.py            # writes v4-reel.html
    REEL=1 node render-v4.js frames sub-reel/ 4 8 && REEL=1 node render-v4.js encode sub-reel/ video-reel.mp4 8

Each edit below is an exact replacement in v4.html; the script stops if one no longer matches, so a change to the
landscape film never silently breaks the reel.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

EDITS = [
    # ── Frame and type
    ("const W = 1920, H = 1080;", "const W = 1080, H = 1920;                            // the reel: 9:16"),
    ("html, body { margin: 0; width: 1920px; height: 1080px;", "html, body { margin: 0; width: 1080px; height: 1920px;"),
    (".cap { font-size: 64px;", ".cap { font-size: 72px;"),                                     # phone-sized captions
    # ── Wallpaper: the same drawn landscape gradient, scaled to cover the tall frame
    ("function wallpaper(dark) {\n  const cv = document.createElement('canvas'); cv.width = W; cv.height = H;",
     "function wallpaperLand(dark) {\n  const cv = document.createElement('canvas'); cv.width = 1920; cv.height = 1080;"),
    ("const base = g.createLinearGradient(0, 0, W, H);", "const base = g.createLinearGradient(0, 0, 1920, 1080);"),
    ("g.fillStyle = base; g.fillRect(0, 0, W, H);", "g.fillStyle = base; g.fillRect(0, 0, 1920, 1080);"),
    ("const WALL_L = wallpaper(false), WALL_D = wallpaper(true);",
     "function wallpaper(dark) {\n  const land = wallpaperLand(dark), cv = document.createElement('canvas'); cv.width = W; cv.height = H;\n"
     "  const k = H / 1080; cv.getContext('2d').drawImage(land, (W - 1920 * k) / 2, 0, 1920 * k, H); cv.land = land; return cv;\n}\n"
     "const WALL_L = wallpaper(false), WALL_D = wallpaper(true);"),
    ("cv.getContext('2d').drawImage(WALL_L, 0, 0, cv.width, cv.height); lapScreen.appendChild(cv); }",
     "cv.getContext('2d').drawImage(WALL_L.land, 0, 0, cv.width, cv.height); lapScreen.appendChild(cv); }"),   # a laptop is landscape
    # ── The old way (the routine): the window at 80%, the step chips smaller, captions under it
    ("const RT = AT, RS = 1, RLOOP = { s: 0.62, y: -150 }, CHIP = { w: 200, gap: 40, y: 640, size: 26 };",
     "const RT = AT, RS = 0.86, RLOOP = { s: 0.66, y: -220 }, CHIP = { w: 168, gap: 22, y: 860, size: 22 };"),
    ("const RW = { x: 360, y: 70, w: 1200, h: 740 };", "const RW = { x: -60, y: 330, w: 1200, h: 740 };"),
    ("const RCAP = { x: 960, y: 872, align: 'center' };", "const RCAP = { x: 540, y: 1130, align: 'center' };"),
    ("{ x: 140, y: 470, exit: T(7) - 0.1, hl: { 'drop'", "{ x: 80, y: 290, exit: T(7) - 0.1, hl: { 'drop'"),
    ("[T(6), 3.2, 1310, 455, [0.02, 1]], [T(7), 6.0, 1334, 450, [0.8, 1]],", "[T(6), 3.6, 1319, 400, [0.02, 1]], [T(7), 6.0, 1379, 427, [0.8, 1]],"),
    # ── Desk: the three windows stacked in a column; the Remove BG panel above the bubble
    ("const FINDER = { x: 90, y: 235, w: 430, h: 270 }, PHOTOS = { x: 570, y: 220, w: 440, h: 300 }, WEB = { x: 330, y: 540, w: 560, h: 330 };",
     "const FINDER = { x: 545, y: 140, w: 430, h: 270 }, PHOTOS = { x: 540, y: 450, w: 440, h: 300 }, WEB = { x: 480, y: 790, w: 560, h: 330 };"),
    ("const PV = { x: 650, y: 250, w: 480, h: 400 };", "const PV = { x: 1012, y: -60, w: 416, h: 380 };"),
    ("pvFill.style.clipPath = `circle(${fillR.toFixed(1)}px at ${PV.w + 30}px ${PV.h / 2}px)`;",
     "pvFill.style.clipPath = `circle(${fillR.toFixed(1)}px at ${PV.w * 0.7}px ${PV.h + 40}px)`;"),
    # ── Camera: the menu framed under the captions; cards framed with the bubble
    ("const s0 = 6.0, x0 = 1334, y0 = 450;", "const s0 = 6.0, x0 = 1379, y0 = 427;"),
    ("[T(8), 1.3, 760, 490, [0.75, 1], [1.5, 1]], [AT.A + 1.6, 1.38, 640, 475, CAM], [AT.A + 2.3, 1.38, 770, 470, CAM], [AT.A + 3.25, 1.38, 700, 495, CAM],",
     "[T(8), 1.55, 760, 580, [0.75, 1], [1.5, 1]], [AT.A + 1.6, 1.7, 760, 430, CAM], [AT.A + 2.3, 1.6, 760, 590, CAM], [AT.A + 3.25, 1.55, 760, 640, CAM],"),
    ("[T(10, 2), 3.0, 1240, 450, [1.0, 1]],", "[T(10, 2), 3.6, 1319, 400, [1.0, 1]],"),
    ("[IMG_DROP + 0.45, 4.6, 1372, 450, [0.7, 1]], [T(12, 2), 3.0, 1270, 450, [0.8, 1]],", "[IMG_DROP + 0.45, 4.6, 1404, 430, [0.7, 1]], [DONE_AT + 0.05, 2.6, 1280, 400, [0.8, 1]],"),
    ("[T(12, 4) - 0.1, 2.2, webC[0], webC[1], [1.0, 1]], [T(13) + 0.12, 3.0, 1240, 450, [1.1, 1]], [T(14), 4.0, 1250, 440, [0.8, 1]], [T(15, 2), 3.0, 1270, 450, [0.8, 1]],",
     "[T(12, 4) - 0.1, 1.8, WEB.x + WEB.w / 2, WEB.y + WEB.h / 2, [1.0, 1]], [T(13) + 0.12, 3.6, 1319, 400, [1.1, 1]], [T(14), 4.2, 1330, 395, [0.8, 1]], [T(15, 2), 2.6, 1280, 400, [0.8, 1]],"),
    ("[T(16) - 0.2, 2.0, 1080, 440, [0.9, 1]], [T(17, 3), 2.4, 980, 452, [1.6, 1]],", "[T(16) - 0.2, 2.2, 1225, 271, [0.9, 1]], [T(17, 3), 2.5, 1220, 200, [1.6, 1]],"),
    ("[T(18, 1) + 0.3, 3.2, 1250, 450, [0.25, 1]], [T(19, 3), 3.9, 1262, 450, [0.8, 1]], [T(20, 3), 3.4, 1262, 450, [0.9, 1]],",
     "[T(18, 1) + 0.3, 3.6, 1319, 400, [0.25, 1]], [T(19, 3), 2.7, 1282, 410, [0.8, 1]], [T(20, 3), 2.6, 1280, 400, [0.9, 1]],"),
    ("[T(25), 3.3, 1300, 450, [0.25, 1]], [T(27), 3.1, 1270, 450, [0.8, 1]],", "[T(25), 3.3, 1340, 420, [0.25, 1]], [T(27), 2.6, 1280, 400, [0.8, 1]],"),
    ("[T(21) + 0.3, 3.7, 1262, 450, [0.7, 1]], [AT.P + 2.7, 3.4, 1262, 450, [0.9, 1]],",           # the PDF scene, like the video's
     "[T(21) + 0.3, 2.7, 1282, 410, [0.7, 1]], [AT.P + 2.7, 2.6, 1280, 400, [0.9, 1]],"),
    # ── Captions: above the UI, wrapped for the narrow frame
    ("caption([words(2, [['Meet', 0.01], ['Droptimize.', 0.32]])], { x: 140, y: 500,", "caption([words(2, [['Meet', 0.01], ['Droptimize.', 0.32]])], { x: 540, y: 640, align: 'center',"),
    ("caption([words('A', [['Drag', 0.0], ['from', 0.48], ['anywhere.', 0.79]])], { x: 960, y: 56, align: 'center',",
     "caption([words('A', [['Drag', 0.0], ['from', 0.48], ['anywhere.', 0.79]])], { x: 540, y: 70, align: 'center',"),
    ("caption([words('A', [['Finder,', 1.73], ['Photos,', 2.42], ['or', 3.23], ['the', 3.31], ['web.', 3.38]])], { x: 960, y: 56, align: 'center',",
     "caption([words('A', [['Finder,', 1.73], ['Photos,', 2.42], ['or', 3.23], ['the', 3.31], ['web.', 3.38]])], { x: 540, y: 60, align: 'center', size: 60,"),
    ("caption([words(3, [['Drop', 0.02], ['any', 0.39], ['photo', 0.73]]), words(3, [['or', 1.05], ['video', 1.2], ['on', 1.55], ['the', 1.7], ['bubble.', 1.85]])], { x: 140, y: 230,",
     "caption([words(3, [['Drop', 0.02], ['any', 0.39], ['photo', 0.73]]), words(3, [['or', 1.05], ['video', 1.2], ['on', 1.55]]), words(3, [['the', 1.7], ['bubble.', 1.85]])], { x: 80, y: 290,"),
    ("caption([[['Done.', DONE_AT]]], { x: 140, y: 230,", "caption([[['Done.', DONE_AT]]], { x: 80, y: 290,"),
    ("caption([words(4, [['Convert', 0.0], ['to', 0.55], ['WebP', 0.84]]), words(4, [['or', 1.41], ['AVIF', 1.6], ['in', 2.28], ['one', 2.45], ['move.', 2.7]])], { x: 140, y: 230,",
     "caption([words(4, [['Convert', 0.0], ['to', 0.55], ['WebP', 0.84]]), words(4, [['or', 1.41], ['AVIF', 1.6], ['in', 2.28]]), words(4, [['one', 2.45], ['move.', 2.7]])], { x: 80, y: 290,"),
    ("caption([words(5, [['Lift', 0.01], ['the', 0.29], ['background', 0.41], ['right', 1.05], ['out.', 1.3]])], { x: 580, y: 46, align: 'center',",
     "caption([words(5, [['Lift', 0.01], ['the', 0.29], ['background', 0.41]]), words(5, [['right', 1.05], ['out.', 1.3]])], { x: 540, y: 40, align: 'center',"),
    ("caption([words(6, [['Videos', 0.0], ['too,', 0.5]])], { x: 960, y: 200, align: 'center',", "caption([words(6, [['Videos', 0.0], ['too,', 0.5]])], { x: 540, y: 640, align: 'center',"),
    ("caption([words(6, [['down', 1.17], ['to', 1.4], ['whatever', 1.55]]), words(6, [['size', 2.0], ['you', 2.3], ['need.', 2.45]])], { x: 140, y: 230,",
     "caption([words(6, [['down', 1.17], ['to', 1.4], ['whatever', 1.55]]), words(6, [['size', 2.0], ['you', 2.3], ['need.', 2.45]])], { x: 80, y: 290,"),
    ("{ x: 140, y: 230, exit: T(23) - 0.3,", "{ x: 80, y: 290, exit: T(23) - 0.3,"),                     # PDFs too, under any upload limit.
    ("{ x: 120, y: 360, exit: T(25, 4), hl: { 'Mac.'", "{ x: 80, y: 420, exit: T(25, 4), hl: { 'Mac.'"),
    ("{ x: 120, y: 560, exit: T(25, 4), hl: { 'internet'", "{ x: 80, y: 640, exit: T(25, 4), hl: { 'internet'"),
    ("caption([words(8, [['Batches', 0.0], ['in', 0.58], ['one', 0.75], ['drop.', 1.0]])], { x: 140, y: 230,",
     "caption([words(8, [['Batches', 0.0], ['in', 0.58]]), words(8, [['one', 0.75], ['drop.', 1.0]])], { x: 80, y: 290,"),
    ("{ x: 140, y: 230, exit: T(28) - 0.15, hl: { 'clipboard.'", "{ x: 80, y: 420, exit: T(28) - 0.15, hl: { 'clipboard.'"),
    # ── Pixel dissolves: a tall grid
    ("const PIX = { cols: 24, rows: 14 };", "const PIX = { cols: 14, rows: 24 };"),
    # ── Cold open: the four files around the caption
    # ── Photos / Videos pills
    ("const pillBox = el('div', pills, { left: '320px', top: '400px', width: '1280px', height: '300px', borderRadius: '150px',",
     "const pillBox = el('div', pills, { left: '60px', top: '840px', width: '960px', height: '240px', borderRadius: '120px',"),
    ("const pillSel = el('div', pillBox, { top: '18px', height: '264px', borderRadius: '132px', background: C.ink });",
     "const pillSel = el('div', pillBox, { top: '14px', height: '212px', borderRadius: '106px', background: C.ink });"),
    ("const pillWords = ['Photos', 'Videos'].map((w, i) => el('div', pillBox, { left: (i * 640) + 'px', width: '640px', top: '84px', textAlign: 'center' }, w, 't-hero nowrap'));",
     "const pillWords = ['Photos', 'Videos'].map((w, i) => el('div', pillBox, { left: (i * 480) + 'px', width: '480px', top: '67px', textAlign: 'center' }, w, 't-title nowrap'));"),
    ("const L = track(t, 18, [[T(18, 2), 658]], [0.28, 0.85]), R = track(t, 622, [[T(18, 2), 1262]], [0.42, 0.9]);",
     "const L = track(t, 14, [[T(18, 2), 494]], [0.28, 0.85]), R = track(t, 466, [[T(18, 2), 946]], [0.42, 0.9]);"),
    ("const x = lerp(1560, 1320, p), y = lerp(960, 600, p);", "const x = lerp(860, 770, p), y = lerp(1560, 1000, p);"),
    # ── The laptop, under the captions
    ("const LAP = { x: 760, y: 200, w: 1040, h: 650 };", "const LAP = { x: 20, y: 1000, w: 1040, h: 650 };"),
    ("const s = lerp(2.6, 1, pull);\n  put(lap, { s, ox: 0.6, oy: 0.4, x: lerp(-260, 0, pull) });",
     "const s = lerp(2.6, 0.88, pull);\n  put(lap, { s, ox: 0.5, oy: 0.4, x: lerp(-120, 0, pull) });"),
    # ── Keycaps, under the caption
    ("top: '330px', width: '380px', height: '380px', borderRadius: '56px'", "top: '1000px', width: '380px', height: '380px', borderRadius: '56px'"),
    ("const kCmd = keycap(820, '⌘', 'command'), kV = keycap(1270, 'V');", "const kCmd = keycap(130, '⌘', 'command'), kV = keycap(570, 'V');"),
    ("kCmd.style.left = '820px'; kV.style.left = '1270px';", "kCmd.style.left = '130px'; kV.style.left = '570px';"),
    # ── Composer: the same layout at 80%, centred; the zoom-through aims at the sent photo
    ("const comp = el('div', compose, { left: '360px', top: '150px', width: '1200px', height: '780px',",
     "const comp = el('div', compose, { left: '-60px', top: '570px', transform: 'scale(0.8)', transformOrigin: '50% 50%', width: '1200px', height: '780px',"),
    ("ox: 0.66, oy: 0.4 });", "ox: 0.70, oy: 0.467 });"),
    # ── End card, centred in the tall frame
    ("const endGlow = el('div', endL, { left: W / 2 - 220 + 'px', top: '120px',", "const endGlow = el('div', endL, { left: W / 2 - 220 + 'px', top: '475px',"),
    ("const endLogo = icon(endL, 'logo', 150, '#FFFFFF', { left: W / 2 - 75 + 'px', top: '265px' });", "const endLogo = icon(endL, 'logo', 150, '#FFFFFF', { left: W / 2 - 75 + 'px', top: '620px' });"),
    ("const endTitle = el('div', endL, { width: W + 'px', top: '450px',", "const endTitle = el('div', endL, { width: W + 'px', top: '800px',"),
    ("const endTag = el('div', endL, { width: W + 'px', top: '612px',", "const endTag = el('div', endL, { width: W + 'px', top: '962px',"),
    ("const endPrice = el('div', endL, { width: W + 'px', top: '720px',", "const endPrice = el('div', endL, { width: W + 'px', top: '1070px',"),
    ("<title>Droptimize film v4</title>", "<title>Droptimize film v4 (reel)</title>"),
]


def main():
    s = open(os.path.join(HERE, 'v4.html'), encoding='utf-8').read()
    for old, new in EDITS:
        n = s.count(old)
        if n != 1:
            raise SystemExit(f'v4.html no longer matches this edit ({n} matches):\n  {old[:110]}')
        s = s.replace(old, new)
    s = s.replace('<!--\n  Launch film v4 (Shotbase style).', '<!--\n  GENERATED by make-reel-v4.py from v4.html: edit v4.html and re-run, not this file.\n  Launch film v4 (Shotbase style), vertical reel.', 1)
    open(os.path.join(HERE, 'v4-reel.html'), 'w', encoding='utf-8').write(s)
    print(f'wrote v4-reel.html ({len(EDITS)} edits)')


if __name__ == '__main__':
    main()

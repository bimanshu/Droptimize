'use strict';
// Film v9 · timeline: Emma's lines, what happens when, where the pointer and the camera are, the captions.
// The voice, music and beat grid are v8's (mix-v4.py's LINES match AT below), so only the picture is new.

// ───────────────────────────── The desk's geometry, in points (the app's own sizes: Bubble/Motion.swift) ─────────────────────────────
const B = { x: 1404, y: 450 }, BD = 44;                 // the bubble: 44 pt, docked at the right edge
const RING_R = 80, SEG_D = 40, OPT_D = 34, OPT_R = RING_R + 56;
const FINDER = { x: 90, y: 235, w: 430, h: 270 }, PHOTOS = { x: 570, y: 220, w: 440, h: 300 }, WEB = { x: 330, y: 540, w: 560, h: 330 };
const cellPos = i => ({ x: 16 + (i % 3) * 138, y: 44 + Math.floor(i / 3) * 124, w: 130, h: 116 });
const SEG_ANGLES = [260, 206.67, 153.33, 100].map(a => a * Math.PI / 180);
const PDF_ANGLES = [Math.PI];                         // one segment (Compress) sits straight out, as in the app
const segPos = (i, angles = SEG_ANGLES) => [B.x + Math.cos(angles[i]) * RING_R, B.y + Math.sin(angles[i]) * RING_R];
/** Where option j of a set ({opts, optSeg, angles?}) sits on its arc. */
function optPos(sc, j) {
  const n = sc.opts.length, base = (sc.angles || SEG_ANGLES)[sc.optSeg], spacing = (OPT_D + 12) / OPT_R;
  const lim = 85 * Math.PI / 180, mid = Math.PI;
  const first = base - (n - 1) / 2 * spacing, last = base + (n - 1) / 2 * spacing;
  let shift = 0; if (first < mid - lim) shift = (mid - lim) - first; if (last > mid + lim) shift = (mid + lim) - last;
  const a = base + (j - (n - 1) / 2) * spacing + shift;
  return [B.x + Math.cos(a) * OPT_R, B.y + Math.sin(a) * OPT_R];
}

// ───────────────────────────── Emma's lines: film time of each line's start (word onsets are in the captions) ─────────────────────────────
// n1–n7: the routine exactly as she read it, one uncut piece.
const AT = { n1: 0.10, n2: 1.63, n3: 2.90, n4: 3.94, n5: 4.90, n6: 5.86, n7: 6.96, n8: T(6) + 0.12, 2: T(7, 2), A: T(8), 3: T(10, 3), 4: T(13, 2), 5: T(16, 2), 6: T(18, 2), P: T(20, 4) + 0.1, 7: T(23, 2), B: T(24, 4), 8: T(26, 2), 9: T(29) };
const DONE_AT = AT[3] + 2.92;                         // her "Done." lands with the check
const IMG_ENTER = T(10, 3), IMG_DROP = T(11, 3);

// ───────────────────────────── Drops on the bubble ─────────────────────────────
// hovers: [time, segment, label]; opts fan out of segment optSeg at optsAt; optHover: [time, option]
const SCENES = [
  { id: 'drop', photo: 'river', grab: T(6) - 0.5, midDrag: T(6), enter: T(6) + 0.14, release: T(6, 3), kind: 'image',
    hovers: [[T(6) + 0.3, -1, 'Auto']], opts: [], optsAt: Infinity, optSeg: 0, optHover: [],
    work: [T(6, 3), T(6, 4)], done: T(6, 4) + 0.1, collapse: T(6, 3) + 0.3 },
  { id: 'img', photo: 'dog', grab: T(10), enter: IMG_ENTER, release: IMG_DROP, kind: 'image',
    hovers: [[T(10, 4), 0, 'Convert'], [T(11), 1, 'Compress']],
    opts: ['100K', '250K', '500K', '1M', '2M', '…'], optsAt: T(11, 2), optSeg: 1, optHover: [[T(11, 2, 2), 1], [T(11, 2, 3), 2]],
    work: [IMG_DROP, DONE_AT - 0.1], done: DONE_AT, collapse: IMG_DROP + 0.35 },
  { id: 'hero', photo: 'street', grab: T(13) + 0.05, enter: T(13, 3), release: T(15), kind: 'image',
    hovers: [[T(13, 3) + 0.12, 0, 'Convert']],
    opts: ['WebP', 'AVIF', 'JPG', 'PNG', 'HEIC'], optsAt: T(13, 3) + 0.18, optSeg: 0, optHover: [[AT[4] + 0.84, 0], [AT[4] + 1.6, 1]],
    work: [T(15), T(15) + 0.4], done: T(15, 2), collapse: T(15) + 0.3 },
  { id: 'pine', photo: 'pine', grab: T(15, 4), enter: AT[5], release: T(17, 2), kind: 'image', midDrag: T(16),
    hovers: [[AT[5] + 0.23, 3, 'Remove BG']],
    opts: ['checker', 'white', 'black', 'eyedropper'], optsAt: T(16, 3), optSeg: 3, optHover: [[T(16, 3) + 0.24, 0], [T(17) + 0.05, 1]], labels: ['No background', 'White', 'Black', 'Custom'],
    work: [T(17, 2), T(17, 2) + 0.45], done: T(17, 3), collapse: T(17, 2) + 0.3 },
  { id: 'video', photo: 'cliffs', grab: T(18, 2), enter: T(18, 4), release: T(19, 3), kind: 'video', midDrag: T(18, 3),
    hovers: [[T(18, 4) + 0.1, 0, 'Convert'], [T(19) + 0.12, 1, 'Compress']],
    // Convert's formats fan out first, WebM leading (the app's default for videos), then Compress's sizes
    pre: { opts: ['WebM', 'AV1', 'MP4', 'HEVC', 'GIF'], optsAt: T(18, 4) + 0.15, optSeg: 0, optHover: [[T(18, 4) + 0.33, 0]], until: T(19) + 0.12 },
    opts: ['10M', '25M', '50M', '100M', '…'], optsAt: T(19) + 0.3, optSeg: 1, optHover: [[T(19, 2), 0], [T(19, 2, 2), 1]],
    quarters: [T(19, 4), T(20), T(20, 2), T(20, 3)], done: T(20, 3), collapse: T(19, 3) + 0.35 },
  { id: 'pdf', photo: 'pdf', grab: T(21) - 0.25, midDrag: T(21) - 0.25, enter: T(21) + 0.4, release: AT.P + 2.4, kind: 'pdf', angles: PDF_ANGLES,
    hovers: [[T(21) + 0.58, 0, 'Compress']],
    opts: ['200K', '500K', '1M', '2M', '5M', '…'], optsAt: T(21) + 0.66, optSeg: 0, optHover: [[AT.P + 1.34, 1], [AT.P + 1.72, 2]],
    work: [AT.P + 2.4, AT.P + 2.95], done: AT.P + 3.0, collapse: AT.P + 2.75 },
];
const SC = Object.fromEntries(SCENES.map(s => [s.id, s]));
const BATCH = { enter: T(26) + 0.23, release: AT[8], stream: i => AT[8] + i * BEAT / 4, done: T(27), out: T(27, 3) - 0.1 };

// ───────────────────────────── The pointer on the desk, in points: [time, x, y, pressed] ─────────────────────────────
const cell0 = (() => { const c = cellPos(0); return [PHOTOS.x + c.x + c.w / 2, PHOTOS.y + c.y + c.h / 2]; })();
const webC = [WEB.x + 24 + 150, WEB.y + 52 + 100];
const entry = [B.x - 72, B.y - 6];
const CUR = [
  [0, 1000, 760, 0], [T(6) - 0.01, B.x - 190, B.y + 60, 1], [T(6) + 0.14, ...entry, 1], [T(6, 2), B.x + 2, B.y + 3, 1], [T(6, 3), B.x + 2, B.y + 3, 0], [T(6, 4) + 0.4, B.x - 40, B.y + 90, 0],
  [T(9, 3) - 0.01, 1000, 760, 0], [T(9, 3), 1000, 760, 0], [T(10) - 0.12, ...cell0, 0], [T(10), ...cell0, 1], [IMG_ENTER, ...entry, 1],
  [T(10, 4), ...segPos(0), 1], [T(11), ...segPos(1), 1], [T(11, 2, 2), 0, 0, 1], [T(11, 2, 3), 0, 0, 1], [IMG_DROP, 0, 0, 0],
  [T(12, 2), 1250, 640, 0], [T(12, 3), 1250, 640, 0], [T(13) - 0.1, ...webC, 0], [T(13) + 0.05, ...webC, 1], [T(13, 3), ...entry, 1],
  [T(13, 3) + 0.12, ...segPos(0), 1], [AT[4] + 0.84, 0, 0, 1], [AT[4] + 1.6, 0, 0, 1], [T(15), 0, 0, 0],
  [T(15, 3), 1250, 660, 0], [T(16) - 0.01, 1250, 660, 0], [T(16), 1170, 590, 1], [AT[5], ...entry, 1],
  [AT[5] + 0.23, ...segPos(3), 1], [T(16, 3) + 0.24, 0, 0, 1], [T(17) + 0.05, 0, 0, 1], [T(17, 2), 0, 0, 0],
  [T(17, 4), 1260, 680, 0], [T(18, 3) - 0.01, 1260, 680, 0], [T(18, 3), 1180, 600, 1], [T(18, 4), ...entry, 1],
  [T(18, 4) + 0.1, ...segPos(0), 1], [T(18, 4) + 0.33, 0, 0, 1], [T(19) + 0.12, ...segPos(1), 1], [T(19, 2), 0, 0, 1], [T(19, 2, 2), 0, 0, 1], [T(19, 3), 0, 0, 0],
  [T(20), 1270, 690, 0], [T(21) - 0.26, 1190, 640, 0], [T(21) - 0.25, 1190, 640, 1], [T(21) + 0.4, ...entry, 1],
  [T(21) + 0.58, ...segPos(0, PDF_ANGLES), 1], [AT.P + 1.34, 0, 0, 1], [AT.P + 1.72, 0, 0, 1], [AT.P + 2.4, 0, 0, 0],
  [AT.P + 3.2, 1270, 700, 0], [T(26) - 0.01, 1230, 640, 0], [T(26), 1200, 600, 1], [BATCH.enter, B.x + 2, B.y + 4, 1], [BATCH.release, B.x + 2, B.y + 4, 0],
  [T(27), 1270, 660, 0], [END, 1270, 660, 0],
];
(function fillOptionWaypoints() {
  const fill = (t, xy) => { const k = CUR.find(c => Math.abs(c[0] - t) < 1e-6); if (k) { k[1] = xy[0]; k[2] = xy[1]; } };
  for (const s of SCENES) {
    for (const [t, j] of s.optHover) fill(t, optPos(s, j));
    if (s.pre) for (const [t, j] of s.pre.optHover) fill(t, optPos(s.pre, j));
    if (s.optHover.length) fill(s.release, optPos(s, s.optHover[s.optHover.length - 1][1]));
  }
})();
function cursorAt(t) {
  let i = 0; while (i < CUR.length - 1 && CUR[i + 1][0] <= t) i++;
  const a = CUR[i], b = CUR[Math.min(i + 1, CUR.length - 1)];
  const p = b[0] > a[0] ? inOut((t - a[0]) / (b[0] - a[0])) : 0;
  return { x: lerp(a[1], b[1], p), y: lerp(a[2], b[2], p), pressed: a[3] };
}

// ───────────────────────────── The camera over the desk: px per point, and its centre in points. Springs, no overshoot. ─────────────────────────────
const CAMK = [
  [T(6), 3.2, 1310, 455, [0.02, 1]], [T(7), 6.0, 1334, 450, [0.8, 1]],
  [T(8), 1.3, 760, 490, [0.75, 1], [1.5, 1]], [AT.A + 1.6, 1.38, 640, 475, CAM], [AT.A + 2.3, 1.38, 770, 470, CAM], [AT.A + 3.25, 1.38, 700, 495, CAM],
  [T(10) - 0.15, 2.3, cell0[0], cell0[1], [0.7, 1]], [T(10, 2), 3.0, 1240, 450, [1.0, 1]],
  [IMG_DROP + 0.45, 3.5, 1262, 450, [0.7, 1]], [T(12, 2), 3.0, 1240, 450, [0.8, 1]],
  [T(12, 4) - 0.1, 2.2, webC[0], webC[1], [1.0, 1]], [T(13) + 0.12, 3.0, 1240, 450, [1.1, 1]], [T(14), 3.4, 1250, 444, [0.9, 1]], [T(15, 2), 3.0, 1240, 450, [0.8, 1]],
  [T(16) - 0.2, 2.0, 1080, 440, [0.9, 1]],
  [T(18, 1) + 0.3, 3.2, 1250, 450, [0.25, 1]], [T(19, 3), 3.5, 1262, 450, [0.8, 1]], [T(20, 3), 3.3, 1262, 450, [0.9, 1]],
  [T(21) + 0.3, 3.4, 1262, 450, [0.7, 1]], [AT.P + 2.7, 3.2, 1262, 450, [0.9, 1]],
  [T(25), 3.3, 1300, 450, [0.25, 1]], [T(27), 3.1, 1270, 450, [0.8, 1]],
];
const camAt = t => ({
  S: track(t, 6.0, CAMK.map(k => [k[0], k[1], k[4]])),
  cx: track(t, 1334, CAMK.map(k => [k[0], k[2], k[5] || k[4]])),
  cy: track(t, 450, CAMK.map(k => [k[0], k[3], k[5] || k[4]])),
});
/** Desk points → screen pixels, for things drawn over the desk in pixels. */
const toScreen = (cam, x, y) => [(x - cam.cx) * cam.S + W / 2, (y - cam.cy) * cam.S + H / 2];

// ───────────────────────────── Which scene is on screen ─────────────────────────────
const SHOT = {
  old: [0, T(6)], desk1: [T(6), T(18)], pills: [T(18), T(18, 3)], desk2: [T(18, 3), T(23)], priv: [T(23), T(26)],
  desk3: [T(26), T(27, 3)], keys: [T(27, 3), T(28)], chat: [T(28), T(29)], end: [T(29), Infinity],
};
const inShot = (t, k) => t >= SHOT[k][0] && t < SHOT[k][1];

// ───────────────────────────── Captions: exactly Emma's words, each on its own onset ─────────────────────────────
const CAPS = [];
/** lines: arrays of [word, onset] (film time); hl: word → [on, off] for the mint box. */
function caption(lines, { x, y, align = 'left', exit, hl = {}, color = '#FFFFFF', size }) {
  const b = el('div', L.cap, { left: x + 'px', top: y + 'px', textAlign: align, color }, '', 'cap');
  if (size) b.style.fontSize = size + 'px';
  const words = [];
  lines.forEach(ln => {
    const row = document.createElement('div'); b.appendChild(row);
    ln.forEach(([w, tw], i) => {
      const s = document.createElement('span'); s.className = 'w'; s.textContent = w; row.appendChild(s);
      if (i < ln.length - 1) row.appendChild(document.createTextNode(' '));
      words.push({ s, tw: tw - 0.05, hl: hl[w] || null, color });
    });
  });
  if (align === 'center') b.style.transform = 'translateX(-50%)';
  const c = { box: b, words, exit }; CAPS.push(c); return c;
}
const at = (k, rel) => AT[k] + rel;
const words = (k, list) => list.map(([w, r]) => [w, at(k, r)]);
const RCAP = { x: 960, y: 880, align: 'center' };     // the old way: under the panels
const LCAP = { x: 140, y: 214 };                      // drops on the bubble: top left, over the file's card
caption([words('n1', [['Need', 0.0], ['a', 0.14], ['smaller', 0.33], ['file?', 0.69]])], { ...RCAP, exit: AT.n2 - 0.1, hl: { 'smaller': [at('n1', 0.33), Infinity] } });
caption([words('n2', [['Find', 0.03], ['a', 0.2], ['website.', 0.45]])], { ...RCAP, exit: AT.n3 - 0.1, hl: { 'website.': [at('n2', 0.45), Infinity] } });
caption([words('n3', [['Upload.', 0.0]])], { ...RCAP, exit: AT.n4 - 0.1 });
caption([words('n4', [['Wait.', 0.0]])], { ...RCAP, exit: AT.n5 - 0.1 });
caption([words('n5', [['Download.', 0.0]])], { ...RCAP, exit: AT.n6 - 0.1 });
caption([words('n6', [['Unzip.', 0.0]])], { ...RCAP, exit: AT.n7 - 0.1 });
caption([words('n7', [['Every', 0.03], ['single', 0.33], ['time.', 0.78]])], { ...RCAP, exit: T(6) - 0.2, hl: { 'Every': [at('n7', 0.03), Infinity] } });
caption([words('n8', [['Or', 0.03], ['just', 0.6], ['drop', 0.87], ['it.', 1.11]])], { ...LCAP, y: 250, exit: T(7) - 0.1, hl: { 'drop': [at('n8', 0.87), Infinity] }, size: 76 });
caption([words(2, [['Meet', 0.01], ['Droptimize.', 0.32]])], { x: 140, y: 482, exit: T(8) - 0.1, hl: { 'Droptimize.': [at(2, 0.32), Infinity] }, size: 92 });
caption([words('A', [['Drag', 0.0], ['from', 0.48], ['anywhere.', 0.79]])], { x: 960, y: 56, align: 'center', exit: AT.A + 1.6, hl: { 'anywhere.': [at('A', 0.79), Infinity] } });
caption([words('A', [['Finder,', 1.73], ['Photos,', 2.42], ['or', 3.23], ['the', 3.31], ['web.', 3.38]])], { x: 960, y: 56, align: 'center', exit: T(10) - 0.1,
  hl: { 'Finder,': [at('A', 1.73), at('A', 2.42)], 'Photos,': [at('A', 2.42), at('A', 3.38)], 'web.': [at('A', 3.38), Infinity] } });
caption([words(3, [['Drop', 0.02], ['any', 0.39], ['photo', 0.73]]), words(3, [['or', 1.05], ['video', 1.2], ['on', 1.55], ['the', 1.7], ['bubble.', 1.85]])], { ...LCAP, exit: DONE_AT - 0.25, hl: { 'bubble.': [at(3, 1.85), Infinity] } });
caption([[['Done.', DONE_AT]]], { ...LCAP, y: 288, exit: T(12, 4) + 0.1, hl: { 'Done.': [DONE_AT, Infinity] } });
caption([words(4, [['Convert', 0.0], ['to', 0.55], ['WebP', 0.84]]), words(4, [['or', 1.41], ['AVIF', 1.6], ['in', 2.28], ['one', 2.45], ['move.', 2.7]])], { ...LCAP, exit: T(15, 2) - 0.1, hl: { 'AVIF': [at(4, 1.6), Infinity] } });
caption([words(5, [['Lift', 0.01], ['the', 0.29], ['background', 0.41], ['right', 1.05], ['out.', 1.3]])], { x: 620, y: 52, align: 'center', exit: T(17, 2) + 0.2, hl: { 'out.': [at(5, 1.3), Infinity] } });
caption([words(6, [['Videos', 0.0], ['too,', 0.5]])], { x: 960, y: 250, align: 'center', exit: T(18, 3) - 0.05, hl: { 'Videos': [at(6, 0.0), Infinity] } });
caption([words(6, [['down', 1.17], ['to', 1.4], ['whatever', 1.55]]), words(6, [['size', 2.0], ['you', 2.3], ['need.', 2.45]])], { ...LCAP, exit: T(19, 4) - 0.1, hl: { 'size': [at(6, 2.0), Infinity] } });
caption([words('P', [['PDFs', 0.04], ['too,', 0.7]]), words('P', [['under', 1.34], ['any', 1.72], ['upload', 2.02], ['limit.', 2.4]])], { ...LCAP, exit: T(23) - 0.3,
  hl: { 'PDFs': [at('P', 0.04), at('P', 2.4)], 'limit.': [at('P', 2.4), Infinity] } });
caption([words(7, [['All', 0.0], ['on', 0.15], ['your', 0.28], ['Mac.', 0.45]]), words(7, [['Nothing', 1.27], ['uploaded.', 1.6]])], { x: 140, y: 380, exit: T(25, 4), hl: { 'Mac.': [at(7, 0.45), Infinity] } });
caption([words('B', [['No', 0.0], ['internet', 0.2], ['needed.', 0.75]])], { x: 140, y: 580, exit: T(25, 4), hl: { 'internet': [at('B', 0.2), Infinity] } });
caption([words(8, [['Batches', 0.0], ['in', 0.58], ['one', 0.75], ['drop.', 1.0]])], { ...LCAP, exit: at(8, 1.35), hl: { 'drop.': [at(8, 1.0), Infinity] } });
caption([words(8, [['Already', 1.47], ['on', 2.0], ['your', 2.15]]), words(8, [['clipboard.', 2.3]])], { ...LCAP, exit: T(28) - 0.15, hl: { 'clipboard.': [at(8, 2.3), Infinity] } });

function captionsAt(t) {
  for (const c of CAPS) {
    const first = c.words[0].tw;
    if (t < first - 0.05 || t > c.exit + 0.6) { show(c.box, false); continue; }
    show(c.box, true);
    const q = step(t - c.exit, [0.3, 1]);
    for (const w of c.words) {
      const p = step(t - w.tw, [0.35, 1]), v = clamp(p - q);
      w.s.style.opacity = v;
      w.s.style.filter = (p < 0.995 || q > 0.005) ? `blur(${(10 * (1 - p) + 12 * q).toFixed(2)}px)` : 'none';
      w.s.style.transform = `translateY(${(10 * (1 - p) - 10 * q).toFixed(2)}px)`;
      const h = w.hl ? clamp(step(t - w.hl[0], [0.25, 1]) - (w.hl[1] < Infinity ? step(t - w.hl[1], [0.25, 1]) : 0)) : 0;
      w.s.style.background = h > 0.005 ? `rgba(61,220,151,${h.toFixed(3)})` : 'transparent';
      w.s.style.color = h > 0.005 ? mix(w.color, C.ink, h) : w.color;
      w.s.style.textShadow = h > 0.3 ? 'none' : '';
    }
  }
}

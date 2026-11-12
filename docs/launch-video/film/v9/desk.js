'use strict';
// Film v9 · the desk: a Mac desktop in points (1440 × 900) under a moving camera. Windows, the bubble with its
// radial menu, what's being dragged, the pointer. The app's own sizes and springs (Bubble/Motion.swift).
const desk = L.desk;

// ───────────────────────────── Windows (generic, no real brand) ─────────────────────────────
const WIN_SHADOW = '0 26px 60px rgba(2,10,48,0.42), 0 4px 10px rgba(2,10,48,0.24), inset 0 0 0 0.5px rgba(255,255,255,0.7)';
function windowEl(r, title) {
  const g = box(desk, r.x, r.y, r.w, r.h);
  const ring = box(g, -3, -3, r.w + 6, r.h + 6, { borderRadius: '13px', boxShadow: `0 0 0 2px ${C.mint}, 0 0 26px rgba(61,220,151,0.45)` });
  const body = box(g, 0, 0, r.w, r.h, { borderRadius: '10px', background: '#FBFCFE', boxShadow: WIN_SHADOW, overflow: 'hidden' });
  box(body, 0, 0, r.w, 28, { background: 'linear-gradient(#F7F8FB, #ECEEF3)', borderBottom: '0.5px solid rgba(0,0,0,0.09)' });
  [0, 1, 2].forEach(i => box(body, 11 + i * 13, 10.5, 7, 7, { borderRadius: '50%', background: '#D3D7E0' }));
  if (title) el('div', body, { width: r.w + 'px', top: '8px', textAlign: 'center', fontSize: '9.5px', fontWeight: 600, color: '#5E6370' }, title, 'nowrap');
  return { g, body, ring, r };
}
const thumb = (parent, key, x, y, w, h, radius = 3, pos) => { const d = box(parent, x, y, w, h, { borderRadius: radius + 'px', overflow: 'hidden', background: '#E3E6EC' }); if (key) photo(d, key, w, h, {}, pos); return d; };

// Finder
const wFinder = windowEl(FINDER, 'Downloads');
box(wFinder.body, 0, 28, 96, FINDER.h - 28, { background: '#F1F3F7', borderRight: '0.5px solid rgba(0,0,0,0.06)' });
['Recents', 'Downloads', 'Desktop', 'Documents', 'Pictures'].forEach((name, i) => {
  if (i === 1) box(wFinder.body, 7, 40 + i * 21 - 3, 82, 19, { borderRadius: '5px', background: 'rgba(11,12,15,0.07)' });
  el('div', wFinder.body, { left: '14px', top: 40 + i * 21 + 'px' }, iconHTML(i === 1 ? 'download' : i === 4 ? 'image' : 'folder', 11, '#7A8090'));
  text(wFinder.body, 30, 40 + i * 21 - 0.5, name, 8.5, i === 1 ? 600 : 500, i === 1 ? C.ink : '#555A66');
});
text(wFinder.body, 108, 34, 'Name', 7.5, 500, '#8A8F9B'); text(wFinder.body, FINDER.w - 46, 34, 'Size', 7.5, 500, '#8A8F9B');
const FROWS = [['pine', 'pineapple.jpg', '9.8 MB'], ['cliffs', 'launch.mov', '840 MB'], ['river', 'DJI_0412.jpg', '9.8 MB'], [null, 'report.pdf', '8.4 MB'], ['dune', 'dune.tiff', '48 MB'], ['blocks', 'facade.png', '7.4 MB']];
const finderRows = FROWS.map(([key, name, size], i) => {
  const row = box(wFinder.body, 100, 50 + i * 35, FINDER.w - 104, 33, { borderRadius: '6px' });
  const sel = box(row, 0, 0, FINDER.w - 104, 33, { borderRadius: '6px', background: 'rgba(61,220,151,0.22)' });
  const th = thumb(row, key, 8, 5.5, 30, 22, 3.5);
  if (!key) { th.style.background = '#FFFFFF'; th.style.boxShadow = 'inset 0 0 0 0.6px rgba(0,0,0,0.18)'; el('div', th, { left: '9.5px', top: '5.5px' }, iconHTML('doc', 11, '#C2453F')); }
  text(row, 46, 10, name, 9, 500, C.ink);
  const sz = text(row, 0, 10.5, size, 8.5, 450, '#6B6F7A', { width: FINDER.w - 116 + 'px', textAlign: 'right' });
  return { row, sel, th, sz };
});

// Photos
const wPhotos = windowEl(PHOTOS, 'Photos');
const GRID = [['dog', '50% 50%'], ['tabby', '50% 30%'], ['dune', '50% 60%'], ['cat', '60% 50%'], ['latte', '70% 50%'], ['door', '50% 40%']];
const cells = GRID.map(([k, pos], i) => { const c = cellPos(i); const d = box(wPhotos.body, c.x, c.y, c.w, c.h, { borderRadius: '6px', overflow: 'hidden', boxShadow: '0 1px 3px rgba(0,0,0,0.18)' }); photo(d, k, c.w, c.h, {}, pos); return d; });

// A web page
const wWeb = windowEl(WEB, '');
box(wWeb.body, 150, 6.5, 260, 15, { borderRadius: '7.5px', background: '#E4E7EE' });
text(wWeb.body, 150, 8.5, 'journal.example', 8, 500, '#666B77', { width: '260px', textAlign: 'center' });
const webImg = box(wWeb.body, 24, 52, 300, 200, { borderRadius: '8px', overflow: 'hidden', boxShadow: '0 2px 8px rgba(0,0,0,0.2)' }); photo(webImg, 'street', 300, 200, {}, '50% 60%');
text(wWeb.body, 346, 54, 'FIELD NOTES', 7, 650, '#12A56C', { letterSpacing: '0.08em' });
el('div', wWeb.body, { left: '346px', top: '68px', width: '200px', fontSize: '19px', fontWeight: 650, letterSpacing: '-0.02em', lineHeight: 1.12, color: C.ink }, 'Night walks,<br>in colour');
text(wWeb.body, 346, 122, 'A year of rain, neon and wet streets.', 8.5, 450, '#6B6F7A');
[0, 1, 2, 3, 4, 5].forEach(i => box(wWeb.body, 346, 148 + i * 13, [188, 176, 190, 150, 182, 96][i], 5, { borderRadius: '3px', background: '#E3E6EC' }));
[0, 1, 2].forEach(i => box(wWeb.body, 24, 270 + i * 13, [500, 470, 300][i], 5, { borderRadius: '3px', background: '#E3E6EC' }));
const WINDOWS = [wFinder, wPhotos, wWeb];

// ───────────────────────────── "Drag from anywhere": a path from each window to the bubble ─────────────────────────────
const SRC = [
  [FINDER.x + 123, FINDER.y + 66.5],                     // the first row's thumbnail
  cell0,
  webC,
];
const arcSvg = svg(desk, 1440, 900, '', { overflow: 'visible' });
const arcCtl = (s) => [(s[0] + B.x) / 2, Math.min(s[1], B.y) - 150];
const arcs = SRC.map((s, i) => {
  const [qx, qy] = arcCtl(s);
  const p = document.createElementNS(NS, 'path');
  p.setAttribute('d', `M${s[0]} ${s[1]} Q${qx} ${qy} ${B.x - 26} ${B.y}`);
  p.setAttribute('fill', 'none'); p.setAttribute('stroke', C.mint); p.setAttribute('stroke-width', '2.2'); p.setAttribute('stroke-linecap', 'round');
  arcSvg.appendChild(p);
  const len = p.getTotalLength(); p.setAttribute('stroke-dasharray', `${len} ${len}`);
  const ghost = thumb(desk, ['pine', 'dog', 'street'][i], 0, 0, 44, 33, 5, ['50% 50%', '50% 50%', '50% 60%'][i]);
  ghost.style.boxShadow = '0 6px 16px rgba(2,10,48,0.4), inset 0 0 0 1px rgba(255,255,255,0.7)';
  return { p, len, ghost, s, q: [qx, qy] };
});
const bez = (a, q, b, u) => [(1 - u) * (1 - u) * a[0] + 2 * (1 - u) * u * q[0] + u * u * b[0], (1 - u) * (1 - u) * a[1] + 2 * (1 - u) * u * q[1] + u * u * b[1]];

// ───────────────────────────── What's dragged: a small copy on the pointer ─────────────────────────────
function pageThumb(parent, w, h) {
  const p = box(parent, 0, 0, w, h, { borderRadius: w * 0.07 + 'px', background: '#FFFFFF', overflow: 'hidden', boxShadow: 'inset 0 0 0 0.6px rgba(0,0,0,0.16)' });
  box(p, w * 0.12, h * 0.1, w * 0.5, h * 0.05, { borderRadius: '1px', background: '#30343C' });
  box(p, w * 0.12, h * 0.2, w * 0.76, h * 0.26, { borderRadius: '1.5px', background: 'linear-gradient(135deg, #7FB3FF, #3DDC97)' });
  [0, 1, 2, 3, 4].forEach(i => box(p, w * 0.12, h * (0.53 + i * 0.075), w * [0.76, 0.7, 0.76, 0.62, 0.4][i], h * 0.03, { borderRadius: '1px', background: '#C9CDD6' }));
  const tag = box(p, w * 0.12, h * 0.865, w * 0.36, h * 0.085, { borderRadius: '1.5px', background: '#E5484D' });
  el('div', tag, { width: '100%', textAlign: 'center', fontSize: h * 0.062 + 'px', fontWeight: 700, color: '#FFFFFF', lineHeight: h * 0.085 + 'px', letterSpacing: '0.04em' }, 'PDF');
  return p;
}
function dragTile(key, w = 76, h = 56) {
  const g = box(desk, 0, 0, w, h);
  if (key === 'pdf') { g.style.width = '46px'; g.style.height = '60px'; g.style.filter = 'drop-shadow(0 8px 14px rgba(2,10,48,0.4))'; pageThumb(g, 46, 60); return { g, w: 46, h: 60 }; }
  const d = box(g, 0, 0, w, h, { borderRadius: '8px', overflow: 'hidden', boxShadow: '0 10px 24px rgba(2,10,48,0.45), 0 0 0 1.2px rgba(255,255,255,0.85)' });
  photo(d, key, w, h);
  return { g, w, h };
}
for (const s of SCENES) s.tile = dragTile(s.photo);
// The batch: a little stack on the pointer
const BATCH_KEYS = ['dog', 'river', 'dune', 'blocks', 'cat', 'door', 'road', 'latte', 'ripples', 'wall'];
const stack = box(desk, 0, 0, 90, 70);
[2, 1, 0].forEach(i => { const d = box(stack, 4 + i * 5, 6 + i * 4, 76, 56, { borderRadius: '8px', overflow: 'hidden', boxShadow: '0 6px 16px rgba(2,10,48,0.4), 0 0 0 1.2px rgba(255,255,255,0.85)', transform: `rotate(${(i - 1) * 5}deg)` }); photo(d, BATCH_KEYS[i], 76, 56); });
const stackBadge = box(stack, 62, -4, 24, 24, { borderRadius: '50%', background: C.mint, boxShadow: '0 2px 6px rgba(0,0,0,0.3)' });
el('div', stackBadge, { width: '24px', textAlign: 'center', fontSize: '11px', fontWeight: 700, lineHeight: '24px', color: C.ink }, '10', 'num');

// ───────────────────────────── The bubble: frosted glass, 44 pt ─────────────────────────────
const GLASS = 'radial-gradient(130% 130% at 32% 20%, #FFFFFF 0%, #F4F8FF 38%, #DCE6F8 76%, #C8D6F0 100%)';
const GLASS_IN = 'inset 0 0 0 0.6px rgba(255,255,255,0.95), inset 0 -3px 6px rgba(38,66,140,0.20), inset 0 1.5px 1.5px rgba(255,255,255,1)';
const bubGlow = box(desk, B.x - 60, B.y - 60, 120, 120, { borderRadius: '50%', background: 'radial-gradient(closest-side, rgba(61,220,151,0.75), rgba(61,220,151,0.22) 55%, rgba(61,220,151,0))' });
const ripple = box(desk, 0, 0, 24, 24, { borderRadius: '50%', border: '1.4px solid rgba(255,255,255,0.9)' });
const segs = [0, 1, 2, 3].map(() => {
  const d = box(desk, 0, 0, SEG_D, SEG_D, { borderRadius: '50%' });
  const icons = {};
  for (const n of ['convert', 'compress', 'half', 'scissors', 'resize', 'mute']) icons[n] = { dark: icon(d, n, 18, C.ink, { left: '11px', top: '11px' }), light: icon(d, n, 18, '#FFFFFF', { left: '11px', top: '11px' }) };
  return { d, icons };
});
const opts = Array.from({ length: 6 }, () => {
  const d = box(desk, 0, 0, OPT_D, OPT_D, { borderRadius: '50%' });
  const txt = el('div', d, { width: OPT_D + 'px', top: '10.5px', textAlign: 'center', fontSize: '10.5px', fontWeight: 600, lineHeight: '13px', letterSpacing: '-0.01em' }, '', 'nowrap num');
  const glyph = {};
  for (const n of ['ellipsis', 'checker', 'eyedropper']) glyph[n] = { dark: icon(d, n, 16, C.ink, { left: '9px', top: '9px' }), light: icon(d, n, 16, '#FFFFFF', { left: '9px', top: '9px' }) };
  const sw = box(d, 9, 9, 16, 16, { borderRadius: '50%' });
  return { d, txt, glyph, sw };
});
const bub = box(desk, B.x - BD / 2, B.y - BD / 2, BD, BD);
box(bub, 0, 0, BD, BD, { borderRadius: '50%', boxShadow: '0 12px 26px rgba(2,10,48,0.45), 0 3px 6px rgba(2,10,48,0.3)' });
const bubBody = box(bub, 0, 0, BD, BD, { borderRadius: '50%', background: GLASS, boxShadow: GLASS_IN });
const bubGloss = box(bub, 6, 2.5, 26, 15, { borderRadius: '50%', background: 'radial-gradient(closest-side, rgba(255,255,255,0.95), rgba(255,255,255,0))' });
const bubLogo = icon(bub, 'logo', 22, '#555B6B', { left: '11px', top: '11px' });
const bubLabel = el('div', bub, { width: BD + 'px', top: '14.5px', textAlign: 'center', fontSize: '10.5px', fontWeight: 650, lineHeight: '15px', letterSpacing: '-0.01em', color: C.ink }, '', 'nowrap num');
const bubCheck = icon(bub, 'check', 26, C.mintD, { left: '9px', top: '9px' });
const ringSvg = svg(desk, 60, 60, `<circle cx="30" cy="30" r="25.5" fill="none" stroke="rgba(255,255,255,0.32)" stroke-width="3"/><circle id="ra" cx="30" cy="30" r="25.5" fill="none" stroke="${C.mint}" stroke-width="3" stroke-linecap="round" stroke-dasharray="160.2" transform="rotate(-90 30 30)"/>`,
  { left: B.x - 30 + 'px', top: B.y - 30 + 'px', overflow: 'visible', filter: 'drop-shadow(0 0 3px rgba(61,220,151,0.75))' });
const ringArc = ringSvg.querySelector('#ra');
const cursor = pointer(desk, 36);

function hoverAmount(sc, i, t) {
  let v = 0;
  for (let k = 0; k < sc.hovers.length; k++) {
    const [th, si] = sc.hovers[k], next = sc.hovers[k + 1] ? sc.hovers[k + 1][0] : sc.release;
    if (si === i) v += step(t - th, HOVER) - step(t - next, HOVER);
  }
  if (i === sc.optSeg && t >= sc.optsAt && t < sc.release) v = Math.max(v, 0.6);
  if (sc.pre && i === sc.pre.optSeg && t >= sc.pre.optsAt && t < sc.pre.until) v = Math.max(v, 0.6);
  return clamp(v);
}
/** How hovered option j of a set is; the last hover holds until `end`. */
function optHover(set, j, t, end) {
  let v = 0;
  for (let k = 0; k < set.optHover.length; k++) {
    const [th, oj] = set.optHover[k], next = set.optHover[k + 1] ? set.optHover[k + 1][0] : end;
    if (oj === j) v += step(t - th, HOVER) - step(t - next, HOVER);
  }
  return clamp(v);
}
function bubbleLabel(t) {
  for (const s of SCENES) {
    if (t >= s.enter && t < s.release) {
      const marks = s.hovers.map(([th, , label]) => [th, label]);
      if (s.pre) for (const [th, j] of s.pre.optHover) marks.push([th, s.pre.opts[j]]);
      for (const [th, j] of s.optHover) marks.push([th, s.labels ? s.labels[j] : s.opts[j]]);
      marks.sort((a, b) => a[0] - b[0]);
      let label = '';
      for (const [th, l] of marks) if (t >= th) label = l;
      return label ? { text: label, o: 1, logo: 0, check: 0 } : { text: '', o: 0, logo: 1, check: 0 };
    }
    if (t >= s.release && t < s.done) return { text: '', o: 0, logo: 0, check: 0 };
    if (t >= s.done && t < s.done + 0.9) return { text: '', o: 0, logo: 0, check: step(t - s.done, SPRING) };
  }
  if (t >= BATCH.enter && t < BATCH.release) return { text: 'Auto', o: 1, logo: 0, check: 0 };
  if (t >= BATCH.release && t < BATCH.done) { const n = clamp(Math.floor((t - BATCH.release) / (BEAT / 4)) + 1, 1, 10); return { text: `${n}/10`, o: 1, logo: 0, check: 0 }; }
  if (t >= BATCH.done && t < BATCH.done + 0.9) return { text: '', o: 0, logo: 0, check: step(t - BATCH.done, SPRING) };
  return { text: '', o: 0, logo: 1, check: 0 };
}
function progressAt(t) {
  for (const s of SCENES) {
    if (t >= s.release && t < s.done + 0.3) {
      const p = s.quarters ? track(t, 0, s.quarters.map((q, i) => [q, (i + 1) / 4]), [0.3, 0.95]) : clamp(inOut((t - s.work[0]) / (s.work[1] - s.work[0])));
      return { p, o: 1 - smooth((t - s.done) / 0.3) };
    }
  }
  if (t >= BATCH.release && t < BATCH.done + 0.3) return { p: clamp((t - BATCH.release) / (BATCH.done - BATCH.release)), o: 1 - smooth((t - BATCH.done) / 0.3) };
  return { p: 0, o: 0 };
}
/** Every moment something lands on the bubble: the light swells there. */
const DROPS = SCENES.map(s => s.release).concat([BATCH.release]);
const DONES = SCENES.map(s => s.done).concat([BATCH.done]);

function chip(e, dark, lit = 0) {
  e.style.background = dark ? C.ink : GLASS;
  e.style.boxShadow = dark ? '0 8px 18px rgba(2,10,48,0.5), inset 0 0 0 0.6px rgba(255,255,255,0.16)' : `0 8px 18px rgba(2,10,48,0.34), 0 2px 4px rgba(2,10,48,0.22), ${GLASS_IN}`;
}

// ───────────────────────────── The desk at time t ─────────────────────────────
function deskScene(t, cam) {
  const S = cam.S;
  const dof = px => px / S;                         // screen-space blur → desk units

  // Windows: in for "Drag from anywhere"; each comes forward on its word; out when the drag starts
  const focusOn = [AT.A + 1.73, AT.A + 2.42, AT.A + 3.38];
  WINDOWS.forEach((w, i) => {
    let o;
    if (i === 2) o = life(t, T(8) + 0.47 + i * 0.235, T(10) + 0.1, [0.45, 1], [0.35, 1]) + life(t, T(12, 4) - 0.1, T(13) + 0.3, [0.5, 1], [0.3, 1]);
    else if (i === 1) o = life(t, T(8) + 0.47 + i * 0.235, T(10, 2) + 0.1, [0.45, 1], [0.35, 1]);
    else o = life(t, T(8) + 0.47, T(10), [0.45, 1], [0.35, 1]);
    o = clamp(o);
    const focused = t < focusOn[0] ? 0.45 : (step(t - focusOn[i], [0.25, 1]) - (focusOn[i + 1] ? step(t - focusOn[i + 1], [0.25, 1]) : 0));
    const focus = (i === 1 && t >= T(10) - 0.2 && t < T(11)) || (i === 2 && t >= T(12, 4) - 0.1) ? 1 : clamp(focused);
    const grabbing = (i === 1 && t >= T(10) - 0.2) || (i === 2 && t >= T(12, 4) - 0.1);
    // Each window leans toward the bubble and floats; it squares up and comes forward when it's the one in focus
    const lean = [9, 5, 7][i] * (grabbing ? 0 : 1 - 0.7 * focus), bob = Math.sin(t * 0.9 + i * 2.1) * 2.2;
    put(w.g, { y: 18 * (1 - o) + bob * (1 - focus), o, blur: dof(lerp(7, 0, focus) + 14 * (1 - o)), s: lerp(0.94, 1, o) * (1 + 0.035 * focus), persp: 1100, ry: lean, rx: -1.5 * (1 - focus) });
    put(w.ring, { o: clamp(focused) * (t >= focusOn[0] && t < T(10) ? 1 : 0) * o });
  });
  const lifted = [t >= focusOn[0] && t < focusOn[1] + 0.3, t >= focusOn[1] && t < T(10), t >= focusOn[2] && t < T(10)];
  finderRows.forEach((r, k) => { put(r.sel, { o: k === 0 && lifted[0] ? step(t - focusOn[0], HOVER) : 0 }); });
  put(cells[0], { y: -5 * (lifted[1] ? step(t - focusOn[1], SPRING) : 0), o: t >= T(10) + 0.05 && t < T(12) ? 0.3 : 1 });
  put(webImg, { y: -5 * (lifted[2] ? step(t - focusOn[2], SPRING) : 0), o: t >= T(13) + 0.1 && t < T(15) ? 0.3 : 1 });

  // The paths to the bubble: each draws on its word and a small copy rides it
  arcs.forEach((a, i) => {
    const t0 = focusOn[i] + 0.08, u = step(t - t0, [0.7, 1]), out = step(t - (T(10) - 0.35), [0.3, 1]);
    const vis = (t >= t0 && t < T(10) + 0.2) ? 1 - out : 0;
    a.p.setAttribute('stroke-dashoffset', (a.len * (1 - u)).toFixed(1));
    a.p.setAttribute('opacity', (0.85 * vis).toFixed(3));
    const g = clamp((t - t0 - 0.05) / 0.75), e = inOut(g);
    const [gx, gy] = bez(a.s, a.q, [B.x - 26, B.y], e);
    put(a.ghost, { x: gx - 22, y: gy - 16.5, s: lerp(1, 0.35, smooth((g - 0.7) / 0.3)), o: g > 0 && g < 1 ? Math.min(1, g * 8) * (1 - smooth((g - 0.86) / 0.14)) : 0, r: -8 + 16 * e });
  });
  show(arcSvg, t >= focusOn[0] && t < T(10) + 0.2);

  // The bubble
  const awake = [];
  for (const s of SCENES) awake.push([s.enter, 1.2], [s.collapse, 1.0]);
  awake.push([BATCH.enter, 1.2], [BATCH.done, 1.0]);
  awake.sort((a, b) => a[0] - b[0]);
  let bs = track(t, 1, awake, SPRING);
  [T(7), T(7, 2), T(7, 3), T(7, 4)].forEach(tb => { bs += 0.035 * pulse(t, tb, 0.12, 0.25); });      // "Meet Droptimize": it breathes on the beat
  arcs.forEach((a, i) => { bs += 0.07 * pulse(t, focusOn[i] + 0.78, 0.1, 0.3); });                    // each copy landing
  put(bub, { s: bs });
  const lab = bubbleLabel(t);
  bubLabel.textContent = lab.text;
  bubLabel.style.fontSize = lab.text.length > 7 ? '8.5px' : lab.text.length > 5 ? '9.5px' : '10.5px';
  put(bubLabel, { o: lab.o });
  put(bubLogo, { o: lab.logo, s: 0.6 + 0.4 * lab.logo, r: 0 });
  put(bubCheck, { o: lab.check, s: 0.6 + 0.4 * lab.check });
  // The light on the glass drifts; it brightens for a moment on each drop
  const sweep = Math.sin(t * 0.7) * 2.5;
  put(bubGloss, { x: 6 + sweep, y: 2.5, o: 0.9 });
  let glow = 0; for (const d of DROPS) glow += pulse(t, d, 0.1, 0.7); for (const d of DONES) glow += 0.7 * pulse(t, d, 0.12, 0.8);
  put(bubGlow, { o: clamp(glow * 0.9), s: 0.8 + 0.5 * clamp(glow) });
  const prog = progressAt(t);
  ringArc.setAttribute('stroke-dashoffset', (160.2 * (1 - prog.p)).toFixed(2));
  put(ringSvg, { o: prog.o, s: bs });
  // Ripple on each drop
  const td = DROPS.find(d => t >= d && t < d + 0.5);
  if (td !== undefined) { const p = (t - td) / 0.5, d = lerp(30, 120, outCubic(p)); ripple.style.width = ripple.style.height = d + 'px'; put(ripple, { x: B.x - d / 2, y: B.y - d / 2, o: 0.7 * (1 - p) }); }
  else put(ripple, { o: 0 });

  // Radial menu
  const sc = SCENES.find(s => t >= s.enter - 0.01 && t < s.collapse + 0.5) || null;
  const segSet = !sc ? [] : sc.kind === 'video' ? ['convert', 'compress', 'resize', 'mute'] : sc.kind === 'pdf' ? ['compress'] : ['convert', 'compress', 'half', 'scissors'];
  segs.forEach((sg, i) => {
    if (!sc || i >= segSet.length) { put(sg.d, { o: 0 }); return; }
    const tin = sc.enter + i * 0.025, tout = sc.collapse + (segSet.length - 1 - i) * 0.025;
    const p = step(t - tin, SPRING) - step(t - tout, [0.25, 1]);
    const hv = hoverAmount(sc, i, t);
    const [sx, sy] = segPos(i, sc.angles), r = lerp(0.5, 1, p);
    chip(sg.d, hv > 0.5);
    for (const n in sg.icons) { show(sg.icons[n].dark, n === segSet[i] && hv <= 0.5); show(sg.icons[n].light, n === segSet[i] && hv > 0.5); }
    put(sg.d, { x: B.x + (sx - B.x) * r - SEG_D / 2, y: B.y + (sy - B.y) * r - SEG_D / 2, s: (0.4 + 0.6 * clamp(p)) * (1 + 0.15 * hv), o: clamp(p) });
  });
  opts.forEach((ob, j) => {
    // A scene can fan one segment's options before another's (the video: Convert's formats, then Compress's sizes)
    const set = sc && sc.pre && t < sc.optsAt ? sc.pre : sc;
    if (!sc || j >= set.opts.length) { put(ob.d, { o: 0 }); return; }
    const main = set === sc;
    const tin = set.optsAt + j * 0.02, tout = main ? sc.collapse : set.until;
    const p = step(t - tin, SPRING) - step(t - tout, [0.25, 1]);
    const [ox, oy] = optPos(set, j), [sx, sy] = segPos(set.optSeg, sc.angles);
    const hv = optHover(set, j, t, main ? sc.release + 0.2 : set.until), dark = hv > 0.5, label = set.opts[j];
    chip(ob.d, dark);
    const isGlyph = label === '…' || label === 'checker' || label === 'eyedropper', isSwatch = label === 'white' || label === 'black';
    ob.txt.textContent = isGlyph || isSwatch ? '' : label;
    ob.txt.style.color = dark ? '#FFFFFF' : C.ink;
    ob.txt.style.fontSize = label.length > 3 ? '9.5px' : '10.5px';
    const gname = label === '…' ? 'ellipsis' : label;
    for (const n in ob.glyph) { show(ob.glyph[n].dark, isGlyph && n === gname && !dark); show(ob.glyph[n].light, isGlyph && n === gname && dark); }
    show(ob.sw, isSwatch);
    if (isSwatch) { ob.sw.style.background = label === 'white' ? '#FFFFFF' : '#111113'; ob.sw.style.boxShadow = `inset 0 0 0 1px ${dark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.2)'}`; }
    put(ob.d, { x: lerp(sx, ox, clamp(p)) - OPT_D / 2, y: lerp(sy, oy, clamp(p)) - OPT_D / 2, s: (0.4 + 0.6 * clamp(p)) * (1 + 0.15 * hv), o: clamp(p) });
  });

  // Dragged copies: they lean into the move
  const c = cursorAt(t), lean = clamp((cursorAt(t + 0.03).x - cursorAt(t - 0.03).x) / 0.06 * 0.035, -12, 12);
  for (const s of SCENES) placeTile(s, t, c, lean);
  // Batch: a stack of ten on the pointer until it lets go
  {
    const held = t >= T(26) - 0.05 && t < BATCH.release + 0.25;
    const gone = step(t - BATCH.release, [0.25, 1]);
    put(stack, { x: c.x - 60, y: c.y - 46, s: (1 - 0.3 * step(t - BATCH.enter, SPRING)) * (1 - 0.6 * gone), o: held ? life(t, T(26) - 0.05, Infinity, [0.2, 1]) * (1 - gone) : 0, r: lean });
  }

  // The pointer
  {
    const vis = (t >= T(6) && t < T(6, 4) + 0.5) || t >= T(9, 3);
    let o = vis ? life(t, T(9, 3), Infinity, [0.25, 1]) : 0;
    if (t >= T(6) && t < T(7)) o = 1 - step(t - (T(6, 4) + 0.2), [0.25, 1]);
    for (const [a, b] of [[T(20, 3) + 0.3, T(21) - 0.3], [AT.P + 3.3, T(26) - 0.05]]) o *= 1 - life(t, a - 0.2, b, [0.25, 1]);
    put(cursor, { x: c.x - 3, y: c.y - 2, s: c.pressed ? 0.9 : 1, o, ox: 0.1, oy: 0.05 });
  }
}

function placeTile(s, t, c, lean) {
  const T0 = s.tile;
  const from = s.id === 'img' ? [PHOTOS.x + cellPos(0).x, PHOTOS.y + cellPos(0).y] : s.id === 'hero' ? [WEB.x + 24, WEB.y + 52] : null;
  const start = s.midDrag ?? s.grab;
  if (t < start - 0.01 || t > s.release + 0.5) { put(T0.g, { o: 0 }); return; }
  let x, y, sc = 1, o = 1;
  const off = [-T0.w * 0.62, -T0.h * 0.55];
  if (t < s.release) {
    if (from && !s.midDrag) { const g = step(t - s.grab, [0.3, 0.9]); x = lerp(from[0], c.x + off[0], g); y = lerp(from[1], c.y + off[1], g); sc = lerp(s.id === 'img' ? 1.6 : 3.4, 1, g); }
    else { x = c.x + off[0]; y = c.y + off[1]; o = step(t - start, [0.2, 1]); }
    sc *= 1 - 0.3 * step(t - s.enter, SPRING);
    o *= lerp(0.96, 0.82, step(t - s.enter, SPRING));
  } else {
    const k = step(t - s.release, [0.3, 1]);
    x = lerp(c.x + off[0], B.x - T0.w / 2, k); y = lerp(c.y + off[1], B.y - T0.h / 2, k); sc = 0.7 * (1 - k) + 0.05 * k; o = 1 - k;
  }
  put(T0.g, { x, y, s: sc, o, ox: 0, oy: 0, r: t < s.release ? lean : 0 });
}

'use strict';
// Film v9 · core: time, maths, DOM helpers, icons, photos, and the light behind every scene.

// ───────────────────────────── Time (the same grid as v8: 128 BPM, 30 bars, then a 3 s still) ─────────────────────────────
const W = 1920, H = 1080;
const BEAT = 60 / 128, BAR = 4 * BEAT;
const T = (bar, beat = 1, sixteenth = 0) => (bar - 1) * BAR + (beat - 1) * BEAT + sixteenth * BEAT / 4;
const PICTURE = T(31), END = PICTURE + 3;
const C = { ink: '#0B0C0F', ink2: '#1A1C22', paper: '#F3F5F8', white: '#FFFFFF', mint: '#3DDC97', mintD: '#12A56C', grey: '#6B6F7A', grey2: '#9499A6', red: '#E5484D', line: 'rgba(8,12,24,0.08)' };

// ───────────────────────────── Maths ─────────────────────────────
const TAU = Math.PI * 2;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, p) => a + (b - a) * p;
/** Closed-form step response of a spring (response, damping), 0 → 1. */
function step(tau, [resp, damp]) {
  if (tau <= 0) return 0;
  const w0 = TAU / resp;
  if (damp >= 1) return 1 - Math.exp(-w0 * tau) * (1 + w0 * tau);
  const wd = w0 * Math.sqrt(1 - damp * damp);
  return 1 - Math.exp(-damp * w0 * tau) * (Math.cos(wd * tau) + (damp * w0 / wd) * Math.sin(wd * tau));
}
/** A value that changes target many times: one spring per change, summed. keys: [time, target, spring?] */
function track(t, v0, keys, spec) {
  let v = v0, prev = v0;
  for (const k of keys) { v += (k[1] - prev) * step(t - k[0], k[2] || spec); prev = k[1]; }
  return v;
}
const inOut = x => { x = clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
const outCubic = x => 1 - Math.pow(1 - clamp(x), 3);
const smooth = x => { x = clamp(x); return x * x * (3 - 2 * x); };
const SPRING = [0.35, 0.75], HOVER = [0.2, 0.8], SOFT = [0.4, 1.0], CAM = [0.8, 1.0], SLOW = [1.2, 1.0];
/** 0 → 1 at a, back to 0 at b. */
const life = (t, a, b = Infinity, spec = SOFT, specOut) => step(t - a, spec) - (b < Infinity ? step(t - b, specOut || spec) : 0);
/** A short bump (0 → 1 → 0) starting at a. */
const pulse = (t, a, up = 0.12, down = 0.5) => step(t - a, [up, 1]) - step(t - a - up, [down, 1]);
function rng(seed) { let s = seed >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }
function hex(c) { const n = parseInt(c.slice(1), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; }
const mix = (c0, c1, p) => { const a = hex(c0), b = hex(c1); return `rgb(${a.map((v, i) => Math.round(lerp(v, b[i], clamp(p)))).join(',')})`; };
const rgba = (c, a) => { const v = hex(c); return `rgba(${v[0]},${v[1]},${v[2]},${a.toFixed(3)})`; };

// ───────────────────────────── DOM ─────────────────────────────
const stage = document.getElementById('stage');
function el(tag, parent, style = {}, html = '', cls = '') {
  const e = document.createElement(tag);
  e.className = 'abs' + (cls ? ' ' + cls : '');
  Object.assign(e.style, style);
  if (html) e.innerHTML = html;
  (parent || stage).appendChild(e);
  return e;
}
const box = (parent, x, y, w, h, style = {}, html = '', cls = '') => el('div', parent, Object.assign({ left: x + 'px', top: y + 'px', width: w + 'px', height: h + 'px' }, style), html, cls);
const text = (parent, x, y, str, size, weight = 500, color = C.ink, style = {}) => el('div', parent, Object.assign({ left: x + 'px', top: y + 'px', fontSize: size + 'px', fontWeight: weight, color, lineHeight: 1.2 }, style), str, 'nowrap num');
const full = (parent, style = {}) => el('div', parent, Object.assign({ width: W + 'px', height: H + 'px' }, style));
const NS = 'http://www.w3.org/2000/svg';
function svg(parent, w, h, inner, style = {}, vb) {
  const s = document.createElementNS(NS, 'svg');
  s.setAttribute('width', w); s.setAttribute('height', h); s.setAttribute('viewBox', vb || `0 0 ${w} ${h}`);
  s.setAttribute('class', 'abs'); Object.assign(s.style, style);
  s.innerHTML = inner; parent.appendChild(s); return s;
}
/** Position, scale, rotate (also in depth), fade and blur one element. `blur` is in the element's own units. */
function put(e, { x = 0, y = 0, s = 1, sx, sy, r = 0, rx = 0, ry = 0, o = 1, blur = 0, ox = 0.5, oy = 0.5, persp = 0 } = {}) {
  if (o <= 0.002) { e.style.display = 'none'; return; }
  e.style.display = '';
  e.style.transformOrigin = `${ox * 100}% ${oy * 100}%`;
  e.style.transform = `translate(${x.toFixed(2)}px, ${y.toFixed(2)}px)${persp ? ` perspective(${persp}px) rotateX(${rx.toFixed(2)}deg) rotateY(${ry.toFixed(2)}deg)` : ''}${r ? ` rotate(${r.toFixed(2)}deg)` : ''} scale(${(sx ?? s).toFixed(4)}, ${(sy ?? s).toFixed(4)})`;
  e.style.opacity = o >= 0.999 ? 1 : o.toFixed(3);
  e.style.filter = blur > 0.08 ? `blur(${blur.toFixed(2)}px)` : 'none';
}
const show = (e, v) => { e.style.display = v ? '' : 'none'; };

// ───────────────────────────── Icons (one stroke weight: 1.75 on a 24 grid) ─────────────────────────────
const S_ = c => `fill="none" stroke="${c}" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"`;
const ICON = {
  logo: c => `<circle cx="12" cy="12" r="9.5" fill="none" stroke="${c}" stroke-width="2"/><circle cx="9.6" cy="14.4" r="5.6" fill="none" stroke="${c}" stroke-width="2"/><circle cx="7.9" cy="16.1" r="2.6" fill="${C.mint}"/>`,
  convert: c => `<g ${S_(c)}><path d="M5 10a7 7 0 0 1 12.5-3.5L19 8"/><path d="M19 4v4h-4"/><path d="M19 14a7 7 0 0 1-12.5 3.5L5 16"/><path d="M5 20v-4h4"/></g>`,
  compress: c => `<g ${S_(c)}><rect x="4" y="9" width="16" height="6" rx="1.5"/><path d="M12 2.5v4M9.5 4.5 12 7l2.5-2.5M12 21.5v-4M9.5 19.5 12 17l2.5 2.5"/></g>`,
  half: c => `<g ${S_(c)}><path d="M20 4l-6 6M14 5.5V10h4.5M4 20l6-6M10 18.5V14H5.5"/></g>`,
  scissors: c => `<g ${S_(c)}><circle cx="6.5" cy="6.5" r="2.5"/><circle cx="6.5" cy="17.5" r="2.5"/><path d="M8.6 8 20 18M8.6 16 20 6"/></g>`,
  resize: c => `<g ${S_(c)}><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M7 12V9h3M17 12v3h-3"/></g>`,
  mute: c => `<g ${S_(c)}><path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path d="M16 9.5l4.5 5M20.5 9.5 16 14.5"/></g>`,
  ellipsis: c => `<g fill="${c}"><circle cx="6" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="18" cy="12" r="1.6"/></g>`,
  checker: c => `<g><rect x="4" y="5" width="16" height="14" rx="2" fill="none" stroke="${c}" stroke-width="1.75"/><path d="M4.9 5.9h3.8v3.4H4.9zM12.4 5.9h3.8v3.4h-3.8zM8.7 9.3h3.7v3.4H8.7zM16.2 9.3h3v3.4h-3zM4.9 12.7h3.8v3.4H4.9zM12.4 12.7h3.8v3.4h-3.8zM8.7 16.1h3.7v2H8.7zM16.2 16.1h3v2h-3z" fill="${c}"/></g>`,
  eyedropper: c => `<g ${S_(c)}><path d="M14.5 6.5l3 3M16 5l3 3-1.5 1.5-3-3zM14.6 8.4 6.5 16.5 5.5 19l2.5-1 8.1-8.1"/></g>`,
  check: c => `<path d="M6 12.5l4 4 8-9" fill="none" stroke="${c}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>`,
  play: c => `<path d="M9 7.2v9.6l8-4.8z" fill="${c}"/>`,
  send: c => `<g fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M6 11l6-6 6 6"/></g>`,
  search: c => `<g ${S_(c)}><circle cx="11" cy="11" r="6"/><path d="M20 20l-4.5-4.5"/></g>`,
  upload: c => `<g ${S_(c)}><path d="M12 16V5M7.5 9.5 12 5l4.5 4.5M5 19h14"/></g>`,
  download: c => `<g ${S_(c)}><path d="M12 5v11M7.5 11.5 12 16l4.5-4.5M5 19h14"/></g>`,
  clock: c => `<g ${S_(c)}><circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3.5 2"/></g>`,
  zip: c => `<g ${S_(c)}><path d="M7 3h8l4 4v14H7z"/><path d="M11 3v2M11 7v2M11 11v2M11 15h2v3h-2z"/></g>`,
  doc: c => `<g ${S_(c)}><path d="M7 3h8l4 4v14H7z"/><path d="M15 3v4h4M10 12h6M10 16h6"/></g>`,
  wifi: c => `<g ${S_(c)}><path d="M3.5 9.5a12 12 0 0 1 17 0M6.5 12.8a7.8 7.8 0 0 1 11 0M9.4 16a3.7 3.7 0 0 1 5.2 0"/><circle cx="12" cy="19" r="0.9" fill="${c}"/></g>`,
  cloud: c => `<g ${S_(c)}><path d="M7 18h10a4 4 0 0 0 .6-7.95A6 6 0 0 0 6 11.5 3.3 3.3 0 0 0 7 18z"/></g>`,
  x: c => `<g ${S_(c)}><path d="M7 7l10 10M17 7 7 17"/></g>`,
  alert: c => `<g ${S_(c)}><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5v5.5"/><circle cx="12" cy="16.3" r="0.6" fill="${c}"/></g>`,
  image: c => `<g ${S_(c)}><rect x="3.5" y="5" width="17" height="14" rx="2.5"/><circle cx="9" cy="10" r="1.6"/><path d="M4 17l5-4.5 3.5 3 3-2.5 4.5 4"/></g>`,
  film: c => `<g ${S_(c)}><rect x="3.5" y="5" width="17" height="14" rx="2.5"/><path d="M10 9.5v5l4.5-2.5z" fill="${c}"/></g>`,
  wand: c => `<g ${S_(c)}><path d="M5 19 15 9M13.5 7.5l3 3"/><path d="M18.5 3.5v3M17 5h3M7 4.5v2M6 5.5h2M19 13v2M18 14h2"/></g>`,
  cmd: c => `<g ${S_(c)}><path d="M9 9h6v6H9z"/><path d="M9 9H7a2 2 0 1 1 2-2zM15 9h2a2 2 0 1 0-2-2zM9 15H7a2 2 0 1 0 2 2zM15 15h2a2 2 0 1 1-2 2z"/></g>`,
  folder: c => `<g ${S_(c)}><path d="M3.5 7.5a2 2 0 0 1 2-2H10l2 2.2h6.5a2 2 0 0 1 2 2v7.8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/></g>`,
  arrow: c => `<g ${S_(c)}><path d="M5 12h14M13.5 6.5 19 12l-5.5 5.5"/></g>`,
};
function icon(parent, name, size, color, style = {}) { return svg(parent, size, size, `<g transform="scale(${size / 24})">${ICON[name](color)}</g>`, style); }
const iconHTML = (name, size, color) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" style="display:block">${ICON[name](color)}</svg>`;
/** The pointer, drawn at `h` px tall with a soft shadow. */
function pointer(parent, h) {
  const w = h * 26 / 36;
  return svg(parent, w, h, `<path d="M3 2 L3 29 L9.4 22.8 L14 33.6 L18.6 31.6 L14 21 L22.6 21 Z" fill="#0B0C0F" stroke="#FFFFFF" stroke-width="1.8" stroke-linejoin="round"/>`,
    { filter: `drop-shadow(0 ${h * 0.05}px ${h * 0.09}px rgba(0,0,0,0.38))`, overflow: 'visible' }, '0 0 26 36');
}

// ───────────────────────────── Photos (images/ is git-ignored: prepare-images-v4.py, then prepare-images-v9.py) ─────────────────────────────
const PHOTO = {
  dog: 'images/photo.webp', street: 'images/hero.webp', pine: 'images/product.webp', cutout: 'images/product-cutout.png', cliffs: 'images/video.webp',
  river: 'images/x-river.webp', dune: 'images/x-dune.webp', ripples: 'images/x-ripples.webp', blocks: 'images/x-blocks.webp', door: 'images/x-door.webp',
  cat: 'images/x-cat.webp', road: 'images/x-road.webp', latte: 'images/x-latte.webp', tabby: 'images/x-tabby.webp', wall: 'images/x-wall.webp',
};
const IMGS = [];
function photo(parent, key, w, h, style = {}, pos = '50% 50%') {
  const i = el('img', parent, Object.assign({ width: w + 'px', height: h + 'px', objectPosition: pos }, style));
  i.src = PHOTO[key]; i.draggable = false; IMGS.push(i); return i;
}

// ───────────────────────────── Light ─────────────────────────────
// One small canvas, scaled up: a base colour and a few large soft lights that drift. Every scene has a mood;
// moods cross-fade, and a drop makes the light near the bubble swell for a moment.
const LW = 480, LH = 270;
const lightCanvas = el('canvas', stage, { width: W + 'px', height: H + 'px' });
lightCanvas.width = LW; lightCanvas.height = LH;
const lctx = lightCanvas.getContext('2d');
// blob: [x, y, radius (all as fractions of the frame's width/height/width), colour, alpha, drift x, drift y, speed, phase]
const MOODS = {
  grey: { base: '#101216', blobs: [[0.2, 0.2, 0.7, '#2A2F3A', 0.9, 0.04, 0.03, 0.11, 0], [0.85, 0.8, 0.6, '#1E222B', 0.9, 0.03, 0.04, 0.09, 2], [0.62, 0.1, 0.42, '#3A404D', 0.55, 0.05, 0.02, 0.13, 4]] },
  vivid: { base: '#0A2478', blobs: [
    [0.16, 0.18, 0.72, '#3E7DFF', 0.95, 0.05, 0.04, 0.10, 0.0], [0.9, 0.12, 0.6, '#2743C9', 0.9, 0.04, 0.05, 0.08, 1.7],
    [0.55, 0.66, 0.56, '#13B5B0', 0.82, 0.07, 0.04, 0.07, 3.1], [0.12, 0.98, 0.62, '#2462E8', 0.9, 0.05, 0.03, 0.09, 4.4],
    [0.9, 0.96, 0.5, '#33D69A', 0.5, 0.05, 0.03, 0.11, 5.2], [0.5, 0.02, 0.4, '#9CC0FF', 0.42, 0.08, 0.02, 0.06, 2.3]] },
  night: { base: '#06070A', blobs: [[0.5, 1.12, 0.62, '#0F6B55', 0.55, 0.05, 0.01, 0.08, 0], [0.12, 0.1, 0.5, '#0D1C4A', 0.6, 0.03, 0.03, 0.07, 2], [0.92, 0.25, 0.45, '#102B3A', 0.5, 0.03, 0.04, 0.09, 4]] },
  paper: { base: '#EEF1F6', blobs: [[0.15, 0.1, 0.6, '#FFFFFF', 0.95, 0.03, 0.03, 0.08, 0], [0.9, 0.95, 0.55, '#CFEFE2', 0.75, 0.04, 0.03, 0.07, 2], [0.85, 0.08, 0.5, '#D6E4FF', 0.7, 0.04, 0.03, 0.09, 4], [0.1, 0.95, 0.5, '#E3E8F4', 0.8, 0.03, 0.02, 0.06, 1]] },
  end: { base: '#07080B', blobs: [[0.5, 0.44, 0.34, '#12805F', 0.5, 0.01, 0.01, 0.12, 0], [0.5, 1.2, 0.6, '#0B2A66', 0.5, 0.04, 0.01, 0.07, 3]] },
};
function paintMood(name, t, alpha, shiftX = 0, shiftY = 0) {
  const m = MOODS[name];
  lctx.globalAlpha = alpha; lctx.fillStyle = m.base; lctx.fillRect(0, 0, LW, LH);
  for (const [x, y, r, col, a, dx, dy, sp, ph] of m.blobs) {
    const cx = (x + dx * Math.sin(TAU * sp * t + ph) + shiftX) * LW, cy = (y + dy * Math.cos(TAU * sp * 0.8 * t + ph * 1.3) + shiftY) * LH, rad = r * LW;
    const g = lctx.createRadialGradient(cx, cy, 0, cx, cy, rad);
    g.addColorStop(0, rgba(col, a)); g.addColorStop(0.5, rgba(col, a * 0.42)); g.addColorStop(1, rgba(col, 0));
    lctx.globalAlpha = alpha; lctx.fillStyle = g; lctx.fillRect(0, 0, LW, LH);
  }
  lctx.globalAlpha = 1;
}
/** moods: [[name, weight]…] painted in order; glows: [[x px, y px, radius px, colour, alpha]…] on top. */
function paintLight(t, moods, glows = [], shiftX = 0, shiftY = 0) {
  lctx.clearRect(0, 0, LW, LH);
  let first = true;
  for (const [name, w] of moods) { if (w <= 0.003) continue; paintMood(name, t, first ? 1 : w, shiftX, shiftY); first = false; }
  for (const [x, y, r, col, a] of glows) {
    if (a <= 0.003) continue;
    const g = lctx.createRadialGradient(x / 4, y / 4, 0, x / 4, y / 4, r / 4);
    g.addColorStop(0, rgba(col, a)); g.addColorStop(0.45, rgba(col, a * 0.35)); g.addColorStop(1, rgba(col, 0));
    lctx.fillStyle = g; lctx.fillRect(0, 0, LW, LH);
  }
}

// ───────────────────────────── Layers, back to front ─────────────────────────────
const L = {};
L.desk = el('div', stage, { width: '1440px', height: '900px', transformOrigin: '0 0' });      // the Mac desktop, in points
L.hud = full(stage);            // the file being worked on, large, at the left (screen pixels)
L.sets = full(stage);           // scenes with a frame of their own: the old way, the laptop, keys, the chat, the end
L.cap = full(stage);            // captions
L.fx = full(stage);             // rings and flashes of the transitions
L.vignette = full(stage, { background: 'radial-gradient(120% 120% at 50% 46%, rgba(0,0,0,0) 55%, rgba(0,0,0,0.34) 100%)', pointerEvents: 'none' });

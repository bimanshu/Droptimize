// Checks that no caption word overlaps a visible UI element, every 0.1 s of film v4.
//   node audit-captions-v4.js            the landscape film (v4.html)
//   REEL=1 node audit-captions-v4.js     the vertical reel (v4-reel.html)
//   FILM=v5.html node audit-captions-v4.js   another cut of the same timeline
// Prints each overlap once per run of consecutive frames: time span, the word, and what it hits.
const { chromium } = require('playwright');
const path = require('path');
const REEL = process.env.REEL === '1';
const file = process.env.FILM || (REEL ? 'v4-reel.html' : 'v4.html');
const view = REEL ? { width: 1080, height: 1920 } : { width: 1920, height: 1080 };

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: view });
  await page.goto('file://' + path.join(__dirname, file));
  await page.evaluate(() => window.ready);
  const END = await page.evaluate(() => window.PICTURE);
  const hits = await page.evaluate(({ END, W, H }) => {
    const opacityOf = e => { let o = 1; for (let n = e; n && n !== document.body; n = n.parentElement) { const cs = getComputedStyle(n); if (cs.display === 'none' || cs.visibility === 'hidden') return 0; o *= +cs.opacity; } return o; };
    const blurOf = e => { let b = 0; for (let n = e; n && n !== document.body; n = n.parentElement) { const m = /blur\(([\d.]+)px\)/.exec(n.style.filter || ''); if (m) b += +m[1]; } return b; };
    const layers = ['desk', 'cold', 'pills', 'priv', 'keys', 'compose', 'endL'];
    const stage = document.getElementById('stage');
    const roots = [...stage.children];
    const capLayer = roots.find(r => r.querySelector && r.querySelector('.cap'));
    const words = [...capLayer.querySelectorAll('.cap .w')];
    // UI elements: leaf-ish boxes (windows, tiles, menu, cards, panels, keys, laptop…), not full-frame backgrounds
    // (the pixel-dissolve squares are a transition wiping the whole frame, not UI: skip them)
    const ui = [...stage.querySelectorAll('.abs, svg, img')].filter(e => !capLayer.contains(e) && e !== capLayer && !(e.parentElement && e.parentElement.children.length > 200));
    const out = [];
    for (let t = 0; t <= END; t += 0.1) {
      window.seek(t);
      const boxes = [];
      for (const e of ui) {
        const r = e.getBoundingClientRect();
        if (r.width < 4 || r.height < 4) continue;
        if (r.width * r.height > 0.5 * W * H) continue;                 // layers and backgrounds
        if (r.right < 0 || r.bottom < 0 || r.left > W || r.top > H) continue;
        if (e.children.length > 0 && e.tagName !== 'svg' && getComputedStyle(e).backgroundColor === 'rgba(0, 0, 0, 0)' && !e.style.boxShadow) continue;   // empty groups
        const o = opacityOf(e); if (o < 0.25) continue;
        if (blurOf(e) > 14) continue;                                   // so defocused it reads as background
        boxes.push({ r, e });
      }
      for (const w of words) {
        if (opacityOf(w) < 0.4) continue;
        const a = w.getBoundingClientRect(); if (a.width < 2) continue;
        for (const { r, e } of boxes) {
          const ix = Math.min(a.right, r.right) - Math.max(a.left, r.left), iy = Math.min(a.bottom, r.bottom) - Math.max(a.top, r.top);
          if (ix > 2 && iy > 2) {
            const what = (e.tagName.toLowerCase() + ' ' + Math.round(r.width) + '×' + Math.round(r.height) + ' at ' + Math.round(r.left) + ',' + Math.round(r.top)).replace(/\s+/g, ' ');
            out.push({ t: +t.toFixed(1), word: w.textContent, what, key: w.textContent + '|' + e.tagName + Math.round(r.width / 20) });
          }
        }
      }
    }
    return out;
  }, { END, W: view.width, H: view.height });
  // merge consecutive frames of the same overlap
  const runs = [];
  for (const h of hits) {
    const last = runs.find(r => r.key === h.key && Math.abs(r.t1 - h.t) < 0.15);
    if (last) last.t1 = h.t; else runs.push({ key: h.key, t0: h.t, t1: h.t, word: h.word, what: h.what });
  }
  runs.sort((a, b) => a.t0 - b.t0);
  console.log(`${file}: ${runs.length} overlap${runs.length === 1 ? '' : 's'}`);
  for (const r of runs) console.log(`  ${r.t0.toFixed(1)}–${r.t1.toFixed(1)} s  "${r.word}"  ×  ${r.what}`);
  await browser.close();
})();

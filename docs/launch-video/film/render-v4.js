// Renders film v4 from v4.html (a pure function of time, window.seek(t)). Spec: ../PROMPT-v4.md.
//   node render-v4.js stills <outDir> [t1 t2 …]     one JPEG per time (default: one per beat)
//   node render-v4.js events <out.json>              the sound cue list for mix-v4.py
//   node render-v4.js frames <dir> [pages] [sub]     numbered subframe JPEGs, several pages at once, resumable
//   then: node render-v4.js encode <dir> <out.mp4> [sub]   blends each frame's subframes (motion blur) → 60 fps
//   FROM=<seconds> renders (frames) or encodes (encode) only from that frame on. Use it to re-render just a changed
//   end into a subframe folder, then run frames again without FROM (it skips what exists) and encode once. Don't join
//   H.264 files by stream copy: tried 2026-11-05, it duplicated frames at the join and broke decoding.
// Uses the system Playwright (require('playwright'); chromium.launch() needs no options here).
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const [mode, out, ...rest] = process.argv.slice(2);
const FPS = 60;

if (mode === 'encode') {             // no browser needed
  const sub = +(rest[1] || 8), mp4 = rest[0], from = Math.round((+process.env.FROM || 0) * FPS) * sub;
  const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-framerate', String(FPS * sub), '-start_number', String(from), '-i', path.join(out, 'f%06d.jpg'),
    '-vf', `tmix=frames=${sub},select='not(mod(n+1\\,${sub}))',setpts=N/${FPS}/TB`, '-r', String(FPS),
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-profile:v', 'high', mp4], { stdio: 'inherit' });
  ff.on('close', c => process.exit(c));
  return;
}
const REEL = process.env.REEL === '1';            // REEL=1: the vertical reel (v4-reel.html, made by make-reel-v4.py)
const page_url = 'file://' + path.join(__dirname, process.env.FILM || (REEL ? 'v4-reel.html' : 'v4.html'));   // FILM=v5.html: the new look
const VIEW = REEL ? { width: 1080, height: 1920 } : { width: 1920, height: 1080 };

(async () => {
  if (mode === 'encode') return;
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: VIEW, deviceScaleFactor: 1 });
  await page.goto(page_url);
  await page.evaluate(() => window.ready);
  const END = await page.evaluate(() => window.END);

  if (mode === 'events') {
    fs.writeFileSync(out, JSON.stringify(await page.evaluate(() => window.EVENTS), null, 0));
  } else if (mode === 'stills') {
    fs.mkdirSync(out, { recursive: true });
    const times = rest.length ? rest.map(Number) : Array.from({ length: Math.ceil(END / 0.5) }, (_, i) => i * 0.5 + 0.25);
    for (const t of times) {
      await page.evaluate(t => window.seek(t), t);
      await page.screenshot({ path: path.join(out, `t${t.toFixed(3).padStart(7, '0')}.jpg`), type: 'jpeg', quality: 88 });
    }
  } else if (mode === 'frames') {
    const pages = +(rest[0] || 3), sub = +(rest[1] || 8), rate = FPS * sub, frames = Math.round(END * rate);
    const from = Math.round((+process.env.FROM || 0) * FPS) * sub;      // a whole frame's subframes, so the blend matches
    fs.mkdirSync(out, { recursive: true });
    const t0 = Date.now(); let done = 0;
    const work = async (k) => {
      const p = k === 0 ? page : await browser.newPage({ viewport: VIEW, deviceScaleFactor: 1 });
      if (k) { await p.goto(page_url); await p.evaluate(() => window.ready); }
      for (let i = from + k; i < frames; i += pages) {
        const f = path.join(out, `f${String(i).padStart(6, '0')}.jpg`);
        if (fs.existsSync(f)) { done++; continue; }
        const t = (i + 0.5) / rate;                  // the subframe's centre
        await p.evaluate(t => window.seek(t), t);
        await p.screenshot({ path: f + '.tmp', type: 'jpeg', quality: 94 });
        fs.renameSync(f + '.tmp', f);
        if (++done % 480 === 0) process.stderr.write(`subframe ${done}/${frames} ${((Date.now() - t0) / 1000).toFixed(0)}s\n`);
      }
    };
    await Promise.all(Array.from({ length: pages }, (_, k) => work(k)));
    process.stderr.write(`done ${frames} subframes in ${((Date.now() - t0) / 1000).toFixed(0)}s\n`);
  } else if (mode === 'full') {
    const SUB = 4, FPS = 60, rate = FPS * SUB;
    const frames = Math.round(END * rate);
    const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-framerate', String(rate), '-c:v', 'mjpeg', '-i', '-',
      '-vf', `tmix=frames=${SUB},select='not(mod(n+1\\,${SUB}))',setpts=N/${FPS}/TB`, '-r', String(FPS),
      '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-profile:v', 'high', out], { stdio: ['pipe', 'inherit', 'inherit'] });
    const t0 = Date.now();
    for (let i = 0; i < frames; i++) {
      // Sample at the subframe's centre so motion blur is symmetric around the frame time.
      const t = (i + 0.5) / rate;
      await page.evaluate(t => window.seek(t), t);
      const buf = await page.screenshot({ type: 'jpeg', quality: 94 });
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (i % 240 === 0) process.stderr.write(`frame ${i}/${frames} ${((Date.now() - t0) / 1000).toFixed(0)}s\n`);
    }
    ff.stdin.end();
    await new Promise(r => ff.on('close', r));
  }
  await browser.close();
})();

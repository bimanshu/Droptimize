// Renders the film from index.html (a pure function of time, window.seek(t)).
//   node render.js stills <outDir> [t1 t2 …]   one JPEG per time (default: one per beat)
//   node render.js events <out.json>            the sound cue list for mix.py
//   node render.js full <out.mp4>               240 fps subframes → ffmpeg tmix → 60 fps, no audio
// Uses the system Playwright (require('playwright'); chromium.launch() needs no options here).
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const [mode, out, ...rest] = process.argv.slice(2);
const page_url = 'file://' + path.join(__dirname, 'index.html');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
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

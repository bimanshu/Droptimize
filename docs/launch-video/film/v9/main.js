'use strict';
// Film v9 · main: the sound cue list, seek(t), and what the renderer needs.
const EVENTS = [];

function seek(t) {
  const cam = camAt(t);
  const deskOn = inShot(t, 'desk1') || inShot(t, 'desk2') || inShot(t, 'desk3');

  // ── Light: each scene's mood, the camera's drift, and a swell on the bubble at each drop
  {
    const [bx, by] = toScreen(cam, B.x, B.y);
    let glow = 0; for (const d of DROPS) glow += pulse(t, d, 0.1, 0.9); for (const d of DONES) glow += 0.5 * pulse(t, d, 0.12, 0.8);
    const shiftX = -(cam.cx - 1100) / 1440 * 0.05 * cam.S, shiftY = -(cam.cy - 450) / 900 * 0.05 * cam.S;
    paintLight(t, [['vivid', 1]], deskOn ? [[bx, by, 520, '#3DDC97', clamp(glow) * 0.55]] : [], shiftX, shiftY);
  }

  // ── The desk
  if (deskOn) {
    show(L.desk, true);
    L.desk.style.transform = `translate(${W / 2}px, ${H / 2}px) scale(${cam.S}) translate(${-cam.cx}px, ${-cam.cy}px)`;
    deskScene(t, cam);
  } else show(L.desk, false);

  hudAt(t, cam);
  setsAt(t, cam);
  captionsAt(t);
}

window.seek = seek;
window.EVENTS = EVENTS;
window.END = END;
window.PICTURE = PICTURE;
window.ready = document.fonts.ready
  .then(() => Promise.all([document.fonts.load('600 64px Geist'), document.fonts.load('450 20px Geist')]))
  .then(() => Promise.all(IMGS.map(i => i.decode())));
seek(0);

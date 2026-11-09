// Droptimize website: the bubble menu in the features card, and the film's sound button.

// ───────────── The bubble menu (geometry from Bubble/Motion.swift and Bubble/BubbleLayout.swift) ─────────────

const M = {
  arcSpan: 160 * Math.PI / 180,
  ringRadius: 80,
  segmentDiameter: 40,
  segmentHoverScale: 1.15,
  segmentGap: 4,
  optionDiameter: 34,
  optionHoverScale: 1.15,
  optionRingDistance: 56,
  optionArcLimit: 85 * Math.PI / 180,
};

const MENUS = {
  image: {
    auto: "<b>Or drop in the middle</b> for a smaller WebP.",
    segments: [
      { id: "convert", icon: "i-convert", title: "Convert", label: "Convert", what: "To WebP, AVIF, JPG, PNG or HEIC. Or a whole drop into one PDF.", options: ["WebP", "AVIF", "JPG", "PNG", "HEIC", "PDF"] },
      { id: "compress", icon: "i-compress", title: "Compress", label: "Compress", what: "Same format, smaller. Or under 100 KB, 250 KB, 500 KB, 1 MB, 2 MB, or any size you type.", options: ["100K", "250K", "500K", "1M", "2M", "…"] },
      { id: "half", icon: "i-half", title: "Half size", label: "Half size", what: "Half the width and height, then compressed.", options: [] },
      { id: "removebg", icon: "i-scissors", title: "Remove BG", label: "Remove BG", what: "Lifts the subject out, onto transparent, white, black or any colour.", options: [{ swatch: "clear" }, { swatch: "#FFFFFF" }, { swatch: "#0E0E0F" }, "…"] },
    ],
  },
  video: {
    auto: "<b>Or drop in the middle</b> for a smaller WebM.",
    segments: [
      { id: "convert", icon: "i-convert", title: "Convert", label: "Convert", what: "To WebM, AV1, MP4, HEVC or a smooth GIF.", options: ["WebM", "AV1", "MP4", "HEVC", "GIF"] },
      { id: "compress", icon: "i-compress", title: "Compress", label: "Compress", what: "Under 10, 25, 50 or 100 MB, or any size. Made for upload limits.", options: ["10M", "25M", "50M", "100M", "…"] },
      { id: "resize", icon: "i-resize", title: "Resize", label: "Resize", what: "1080p, 720p or 480p. Never upscaled.", options: ["1080p", "720p", "480p"] },
      { id: "mute", icon: "i-mute", title: "Mute", label: "Mute", what: "Takes the sound out, for hero videos and loops.", options: [] },
    ],
  },
  pdf: {
    auto: "<b>Or drop in the middle</b> for a smaller PDF.",
    segments: [
      { id: "convert", icon: "i-convert", title: "Convert", label: "Convert", what: "Every page as a PNG or JPG.", options: ["PNG", "JPG"] },
      { id: "compress", icon: "i-compress", title: "Compress", label: "Compress", what: "Under 200 KB, 500 KB, 1 MB, 2 MB, 5 MB, or any size you type. Text and pages stay as they are.", options: ["200K", "500K", "1M", "2M", "5M", "…"] },
    ],
  },
  word: {
    auto: "<b>Or drop in the middle</b> for a PDF.",
    segments: [
      { id: "convert", icon: "i-convert", title: "Convert", label: "Convert", what: "A .docx or .doc to PDF, with Word or Pages if you have them, or our built-in reader if you don't.", options: ["PDF"] },
    ],
  },
};

// Docked right: the arc faces left, index 0 at the top. Offsets in points, y down (for CSS).
function segmentAngle(i, count) {
  if (count < 2) return Math.PI;
  return Math.PI + (-M.arcSpan / 2 + i * (M.arcSpan / (count - 1)));
}
function ringRadius(count) {
  if (count < 2) return M.ringRadius;
  const step = M.arcSpan / (count - 1);
  const spacing = M.segmentDiameter * M.segmentHoverScale + M.segmentGap;
  return Math.max(M.ringRadius, Math.ceil(spacing / (2 * Math.sin(step / 2))));
}
function optionAngles(count, parentAngle, ring) {
  const radius = ring + M.optionRingDistance;
  const spacing = M.optionDiameter * M.optionHoverScale + M.segmentGap;
  const step = 2 * Math.asin(Math.min(1, spacing / (2 * radius)));
  const span = step * Math.max(count - 1, 0);
  const relative = Math.atan2(Math.sin(parentAngle - Math.PI), Math.cos(parentAngle - Math.PI));
  const room = Math.max(0, M.optionArcLimit - span / 2);
  const center = Math.PI + Math.min(Math.max(relative, -room), room);
  return { radius, angles: Array.from({ length: count }, (_, i) => center - span / 2 + i * step) };
}
const at = (r, a) => ({ x: r * Math.cos(a), y: -r * Math.sin(a) });

const stage = document.getElementById("stage");
const bubble = document.getElementById("bubble");
const bubbleLabel = document.getElementById("bubble-label");
const list = document.getElementById("actions");
const autoLine = document.getElementById("auto");
const switchButtons = [...document.querySelectorAll(".switch button")];
const thumb = document.querySelector(".switch .thumb");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");

let kind = "image";
let active = 1;
let segs = [];
let opts = [];

const icon = (id) => `<svg aria-hidden="true"><use href="#${id}"/></svg>`;
const place = (el, p) => { el.style.setProperty("--x", p.x.toFixed(1)); el.style.setProperty("--y", p.y.toFixed(1)); };

function buildList() {
  const menu = MENUS[kind];
  list.innerHTML = menu.segments.map((s, i) => `
    <li><button type="button" data-i="${i}" aria-pressed="${i === active}">
      <span class="glyph">${icon(s.icon)}</span><strong>${s.title}</strong><span class="what">${s.what}</span>
    </button></li>`).join("");
  autoLine.innerHTML = menu.auto;
}

function buildSegments() {
  segs.forEach((s) => s.remove());
  const menu = MENUS[kind];
  const ring = ringRadius(menu.segments.length);
  segs = menu.segments.map((s, i) => {
    const el = document.createElement("div");
    el.className = "seg folded";
    el.dataset.i = i;
    el.style.setProperty("--i", i);
    el.innerHTML = icon(s.icon);
    place(el, { x: 0, y: 0 });
    stage.appendChild(el);
    return el;
  });
  requestAnimationFrame(() => requestAnimationFrame(() => {
    segs.forEach((el, i) => { place(el, at(ring, segmentAngle(i, segs.length))); el.classList.remove("folded"); });
  }));
}

function showOptions() {
  const menu = MENUS[kind];
  const ring = ringRadius(menu.segments.length);
  const parent = segmentAngle(active, menu.segments.length);
  const from = at(ring, parent);
  opts.forEach((el) => { el.classList.add("folded"); setTimeout(() => el.remove(), 220); });
  const options = menu.segments[active].options;
  const { radius, angles } = optionAngles(options.length, parent, ring);
  opts = options.map((o, i) => {
    const el = document.createElement("div");
    el.className = "opt folded";
    el.style.setProperty("--i", i);
    if (typeof o === "object") {
      el.classList.add("swatch");
      if (o.swatch === "clear") el.classList.add("clear"); else el.style.setProperty("--c", o.swatch);
    } else {
      el.textContent = o;
    }
    place(el, from);
    stage.appendChild(el);
    return el;
  });
  requestAnimationFrame(() => requestAnimationFrame(() => {
    opts.forEach((el, i) => { place(el, at(radius, angles[i])); el.classList.remove("folded"); });
  }));
}

function setActive(i, { labelBubble = true } = {}) {
  active = i;
  segs.forEach((el, j) => el.classList.toggle("on", j === i));
  list.querySelectorAll("button").forEach((b, j) => b.setAttribute("aria-pressed", String(j === i)));
  bubbleLabel.textContent = MENUS[kind].segments[i].label;
  bubble.classList.toggle("labelled", labelBubble);
  showOptions();
}

function setKind(next) {
  if (next === kind) return;
  kind = next;
  switchButtons.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.kind === kind)));
  moveThumb();
  const fold = () => {
    opts.forEach((el) => el.remove()); opts = [];
    active = Math.min(1, MENUS[kind].segments.length - 1);
    buildList(); buildSegments(); setActive(active, { labelBubble: false });
  };
  if (reduceMotion.matches) { fold(); return; }
  segs.forEach((el) => { el.classList.add("folded"); place(el, { x: 0, y: 0 }); });
  opts.forEach((el) => { el.classList.add("folded"); });
  setTimeout(fold, 200);
}

function moveThumb() {
  const b = switchButtons.find((x) => x.dataset.kind === kind);
  thumb.style.width = b.offsetWidth + "px";
  thumb.style.transform = `translateX(${b.offsetLeft - 4}px)`;
}

list.addEventListener("pointerover", (e) => {
  const b = e.target.closest("button[data-i]");
  if (b && e.pointerType === "mouse" && Number(b.dataset.i) !== active) setActive(Number(b.dataset.i));
});
list.addEventListener("click", (e) => {
  const b = e.target.closest("button[data-i]");
  if (b) setActive(Number(b.dataset.i));
});
list.addEventListener("focusin", (e) => {
  const b = e.target.closest("button[data-i]");
  if (b && Number(b.dataset.i) !== active) setActive(Number(b.dataset.i));
});
stage.addEventListener("pointerover", (e) => {
  const s = e.target.closest(".seg");
  if (s && Number(s.dataset.i) !== active) setActive(Number(s.dataset.i));
});
stage.addEventListener("pointerleave", () => bubble.classList.remove("labelled"));
switchButtons.forEach((b) => b.addEventListener("click", () => setKind(b.dataset.kind)));
addEventListener("resize", moveThumb);
document.fonts?.ready.then(moveThumb);

buildList();
buildSegments();
setActive(active, { labelBubble: false });
moveThumb();

// ───────────── The film: muted loop, sound on request, paused when out of sight ─────────────

const film = document.getElementById("film");
const sound = document.getElementById("sound");
const soundLabel = sound.querySelector("span");

function syncSound() {
  const on = !film.muted && !film.paused;
  sound.setAttribute("aria-pressed", String(on));
  soundLabel.textContent = on ? "Mute" : film.paused && reduceMotion.matches ? "Play the film" : "Play with sound";
}

if (reduceMotion.matches) { film.removeAttribute("autoplay"); film.pause(); }

sound.addEventListener("click", () => {
  if (film.muted || film.paused) {
    film.currentTime = 0; // from the top, so the voice-over starts with the picture
    film.muted = false;
    film.play().catch(() => {});
  } else {
    film.muted = true;
  }
  syncSound();
});
film.addEventListener("play", syncSound);
film.addEventListener("pause", syncSound);
film.addEventListener("volumechange", syncSound);
syncSound();

new IntersectionObserver(([entry]) => {
  if (entry.isIntersecting) {
    if (!reduceMotion.matches || !film.muted) film.play().catch(() => {});
  } else {
    film.pause();
  }
}, { threshold: 0.15 }).observe(film);

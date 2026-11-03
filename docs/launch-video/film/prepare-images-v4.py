"""Downloads and prepares film v4's photos into images/ (git-ignored). Run from docs/launch-video/film/:

    python3 prepare-images-v4.py

All four are from Pexels (free for commercial use, no credit required; owner: "use any Unsplash or Pexels,
but not the most common images"). The desktop background is the drawn gradient in v4.html (the owner tried a
mountain photo, Pexels 7677713, and went back to the gradient, 2026-11-03). Pages:
  img    7323809   https://www.pexels.com/photo/wet-golden-retriever-dog-walking-along-the-beach-7323809/   (IMG_2041.HEIC)
  hero   30315841  https://www.pexels.com/photo/moody-urban-street-at-night-with-rainfall-30315841/   (hero.png, the web page image)
  video  18166239  https://www.pexels.com/photo/aerial-view-of-cliffs-and-beach-on-the-ocean-coast-18166239/   (launch.mov)
  pine   947879    https://www.pexels.com/photo/pineapple-947879/   (pineapple.jpg, the Remove BG subject)
The pineapple sits on one flat navy backdrop, so its cut-out is keyed here by hue and brightness (no Apple Vision needed).
"""
import os, subprocess
from collections import deque
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get('OUT') or os.path.join(HERE, 'images')
PHOTOS = {'img': 7323809, 'hero': 30315841, 'video': 18166239, 'pine': 947879}


def fetch(key, pid):
    path = os.path.join(OUT, f'src_{key}.jpg')
    url = f'https://images.pexels.com/photos/{pid}/pexels-photo-{pid}.jpeg?auto=compress&cs=tinysrgb&w=2600'
    subprocess.run(['curl', '-fsSL', '--max-time', '60', '-o', path, url], check=True)
    return Image.open(path).convert('RGB')


def crop169(im, cy=0.5, out=(1672, 941)):
    w, h = im.size; tw, th = w, int(w * 9 / 16)
    if th > h: th, tw = h, int(h * 16 / 9)
    x, y = (w - tw) // 2, int((h - th) * cy)
    return im.crop((x, y, x + tw, y + th)).resize(out, Image.LANCZOS)


def flood(mask_open, seeds):
    H, W = mask_open.shape; seen = np.zeros((H, W), bool); q = deque()
    for y, x in seeds:
        if mask_open[y, x] and not seen[y, x]: seen[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= yy < H and 0 <= xx < W and mask_open[yy, xx] and not seen[yy, xx]: seen[yy, xx] = True; q.append((yy, xx))
    return seen


def cutout(pine):
    """Key the navy backdrop (and the pineapple's dark cast shadow) out; keep one solid subject."""
    a = np.asarray(pine).astype(np.float32) / 255; H, W, _ = a.shape
    r, g, b = a[..., 0], a[..., 1], a[..., 2]; mx, mn = a.max(-1), a.min(-1); v = mx
    s = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0); d = mx - mn + 1e-6
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    dh = np.abs(((h - np.median(h[:20])) + 180) % 360 - 180)
    backdrop = np.clip(1 - (dh - 14) / 16, 0, 1) * np.clip((s - 0.18) / 0.12, 0, 1) * np.clip(1 - (v - 0.60) / 0.10, 0, 1)
    shadow = np.clip(1 - (v - 0.26) / 0.08, 0, 1) * np.maximum(np.clip(1 - (dh - 60) / 30, 0, 1), np.clip(1 - (s - 0.30) / 0.15, 0, 1))
    al = 1 - np.maximum(backdrop, shadow)
    al = np.asarray(Image.fromarray((al * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32) / 255
    # the largest connected blob is the pineapple; everything reachable from the edges is backdrop
    solid = al > 0.5
    seeds = [(y, x) for y in range(0, H, 3) for x in range(0, W, 3) if solid[y, x]]
    best, taken = None, np.zeros((H, W), bool)
    for y, x in seeds:
        if taken[y, x]: continue
        blob = flood(solid, [(y, x)]); taken |= blob
        if best is None or blob.sum() > best.sum(): best = blob
    edges = [(0, x) for x in range(W)] + [(H - 1, x) for x in range(W)] + [(y, 0) for y in range(H)] + [(y, W - 1) for y in range(H)]
    filled = ~flood(~best, edges)
    m = lambda arr, f: np.asarray(Image.fromarray((arr * 255).astype(np.uint8)).filter(f)).astype(bool)
    al = np.where(m(filled, ImageFilter.MinFilter(11)), 1.0, al) * m(filled, ImageFilter.MaxFilter(3))
    al = np.asarray(Image.fromarray((al * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255
    bg = np.median(a[:20].reshape(-1, 3), 0); rgb = a.copy(); w = (al > 0.02) & (al < 0.98)
    rgb[w] = np.clip((a[w] - (1 - al[w, None]) * bg) / np.maximum(al[w, None], 0.08), 0, 1)   # no navy fringe
    Image.fromarray((np.dstack([rgb, al]) * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'product-cutout.png'))


def main():
    os.makedirs(OUT, exist_ok=True)
    src = {k: fetch(k, pid) for k, pid in PHOTOS.items()}
    crop169(src['img']).save(os.path.join(OUT, 'photo.webp'), quality=92)
    crop169(src['hero'], 0.62).save(os.path.join(OUT, 'hero.webp'), quality=92)
    crop169(src['video']).save(os.path.join(OUT, 'video.webp'), quality=92)
    pine = crop169(src['pine']); pine.save(os.path.join(OUT, 'product.webp'), quality=94)
    cutout(pine)
    for k in PHOTOS: os.remove(os.path.join(OUT, f'src_{k}.jpg'))
    print('wrote', sorted(os.listdir(OUT)))


if __name__ == '__main__':
    main()

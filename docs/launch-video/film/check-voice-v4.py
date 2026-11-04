"""Checks Emma's voice in film v4 before any render: no word clipped at a cut, no two lines overlapping.
Run from docs/launch-video/film/ after changing mix-v4.py's LINES:

    python3 check-voice-v4.py

For every line it measures the source audio just before the cut-in and just after the cut-out (and the loudest
moment in the 0.4 s after it): speech there means a word is clipped. The owner caught one: "Every single time"
had its final "m" cut off (2026-11-04), which is why the routine is now placed as one uncut piece.
"""
import os, subprocess, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
spec = importlib.util.spec_from_file_location('mix_v4', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mix-v4.py'))
mix = importlib.util.module_from_spec(spec); spec.loader.exec_module(mix)

SR, MARGIN = 16000, 0.03
cache = {}


def load(path):
    if path not in cache:
        out = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True, check=True).stdout
        cache[path] = np.frombuffer(out, np.float32)
    return cache[path]


def level(x):
    return 20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-9) if len(x) else -120.0


def main():
    bad = 0
    lines = sorted(mix.LINES, key=lambda l: l[3])
    for path, s0, s1, at in lines:
        a = load(path); name = f'{os.path.basename(path)} {s0:.2f}–{s1:.2f}'
        before = level(a[max(0, int((s0 - MARGIN - 0.06) * SR)):max(0, int((s0 - MARGIN) * SR))]) if s0 - MARGIN > 0.06 else -120.0
        after = level(a[int((s1 + MARGIN) * SR):int((s1 + MARGIN + 0.06) * SR)])
        tail = a[int((s1 + MARGIN) * SR):int((s1 + MARGIN + 0.4) * SR)]
        loudest = max([level(tail[i:i + 160]) for i in range(0, max(1, len(tail) - 160), 160)] or [-120.0])
        ok = before < -42 and after < -42 and loudest < -38
        bad += not ok
        print(f"{'ok  ' if ok else 'CLIP'}  film {at:6.2f}–{at + s1 - s0:6.2f}  {name:34}  before {before:6.1f} dB · after {after:6.1f} dB · next 0.4 s peak {loudest:6.1f} dB")
    for (p1, a0, a1, t1), (p2, b0, b1, t2) in zip(lines, lines[1:]):
        if t1 + (a1 - a0) > t2 - 0.1:
            bad += 1
            print(f'OVERLAP  the line at {t1:.2f} s runs into the one at {t2:.2f} s')
    print('voice: all clean' if not bad else f'voice: {bad} problem(s)')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()

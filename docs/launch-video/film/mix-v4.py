"""Soundtrack for film v4 (48 kHz stereo WAV). Spec: ../PROMPT-v4.md. Reuses mix.py's tools (UI sounds,
cross-fades, ducking maths, mastering) with the v4 music, edit points and voice placements.

    node render-v4.js events events-v4.json
    python3 mix-v4.py --music 160.mp3 --events events-v4.json --out mix-v4.wav

Music: Mixkit 160 "Minimal Emotion" (128.00 BPM, first beat 0.431 s): film t = 0 is its bar 15 downbeat,
so the track's break (its bar 16) is film bar 2 and its drop (bar 17) lands on film 3.1, the reveal.
"""
import argparse, json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mix import SR, decode, db, ramp, crossfade, synth, master, loudness   # noqa: E402

BEAT = 60 / 128
BAR = 4 * BEAT
T = lambda bar, beat=1: (bar - 1) * BAR + (beat - 1) * BEAT
PICTURE, END = T(25), T(25) + 3          # 45 s of picture, then 3 s of silence on the end card
MUSIC_START = 0.431 + 14 * BAR           # the track's bar 15 downbeat
HERE = os.path.dirname(os.path.abspath(__file__))
FULL = os.path.join(HERE, '..', 'audio', 'emma-vo-full.mp3')
EXTRA = os.path.join(HERE, '..', 'audio', 'emma-vo-extra.mp3')
# Emma's lines: (source file, start, end in the source, film time). Starts match v4.html's AT table.
LINES = [
    (FULL, 0.08, 1.85, T(1, 2)),     # Your files are too heavy.
    (FULL, 3.65, 4.80, T(3, 2)),     # Meet Droptimize.
    (EXTRA, 0.03, 3.83, T(4)),       # Drag from anywhere. Finder, Photos, or the web.
    (FULL, 6.21, 9.43, T(6, 3)),     # Drop any photo or video on the bubble. Done.
    (FULL, 10.63, 13.78, T(9, 2)),   # Convert to WebP or AVIF in one move.
    (FULL, 14.88, 16.47, T(12, 2)),  # Lift the background right out.
    (FULL, 17.62, 20.45, T(14, 2)),  # Videos too, down to whatever size you need.
    (FULL, 21.48, 23.70, T(17, 2)),  # All on your Mac. Nothing uploaded.
    (EXTRA, 5.84, 7.12, T(18, 4)),   # No internet needed.
    (FULL, 24.75, 27.77, T(20, 2)),  # Batches in one drop. Already on your clipboard.
    (FULL, 28.85, 31.22, T(23)),     # Droptimize. Drop it. Done.
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--music', required=True); ap.add_argument('--events', required=True); ap.add_argument('--out', required=True)
    a = ap.parse_args()
    N = int(END * SR)

    # ── Music: no stretch (it's already 128.00 BPM); cut so bar 15 starts the film
    start = int(MUSIC_START * SR)
    def cut(x):
        y = np.zeros((N, 2), np.float32); seg = x[start:start + int(PICTURE * SR)]
        y[:len(seg)] = seg; return y
    music = cut(decode(a.music))
    hp = cut(decode(a.music, 'highpass=f=250:p=2,highpass=f=250:p=2'))
    lp800 = cut(decode(a.music, 'lowpass=f=800:p=2'))
    lp300 = cut(decode(a.music, 'lowpass=f=300:p=2,lowpass=f=300:p=2'))
    music = crossfade(music, hp, T(2), T(3), 0.03)                  # the break: lift it out, so the drop hits on the reveal
    music = crossfade(music, lp800, T(19, 4), T(20), 0.03)          # a breath before the batch
    tail = crossfade(lp800, lp300, T(23) + 0.8, PICTURE, 0.5)       # ending: low-pass sweep after the final hit
    music = crossfade(music, tail, T(23), PICTURE, 0.08)
    fade = np.ones(N); a0, a1 = int(T(23) * SR), int((PICTURE - 0.25) * SR)
    fade[a0:a1] = np.linspace(1, 0, a1 - a0) ** 1.6; fade[a1:] = 0
    music *= fade[:, None]
    music *= db(-20) / (np.sqrt((music[int(4 * SR):int(40 * SR)] ** 2).mean()) + 1e-9)

    # ── Voice
    src = {p: decode(p, 'highpass=f=90:p=2', ch=1)[:, 0] for p in (FULL, EXTRA)}
    vo = np.zeros(N, np.float32); m = int(0.03 * SR); f = int(0.01 * SR)
    for path, s0, s1, at in LINES:
        seg = src[path][max(0, int(s0 * SR) - m):int(s1 * SR) + m].copy()
        seg[:f] *= ramp(f); seg[-f:] *= ramp(f)[::-1]
        p = int(at * SR) - m
        vo[p:p + len(seg)] += seg[:N - p]
    vo *= db(-16) / (np.sqrt((vo[np.abs(vo) > 1e-3] ** 2).mean()) + 1e-9)

    # Duck the music 8 dB under her (80 ms attack, 250 ms release)
    env = np.sqrt(np.convolve(vo ** 2, np.ones(960) / 960, 'same'))
    target = np.where(env > db(-40), db(-8), 1.0)
    g = np.empty(N); cur = 1.0
    att, rel = np.exp(-1 / (0.08 * SR)), np.exp(-1 / (0.25 * SR))
    for i in range(0, N, 48):
        k = att if target[i] < cur else rel
        cur = target[i] + (cur - target[i]) * k ** 48
        g[i:i + 48] = cur
    music *= g[:, None]

    # ── UI sounds
    rng = np.random.default_rng(7)
    ui = np.zeros(N, np.float32)
    for t, kind in json.load(open(a.events)):
        snd = synth(kind, rng); p = int(t * SR)
        if p >= N: continue
        ui[p:p + len(snd)] += snd[:N - p]

    mix = music + vo[:, None] + ui[:, None] * np.array([[1.0, 0.94]])
    mix[int(PICTURE * SR):] = 0
    mix, gain = master(mix)
    mix[int(PICTURE * SR):] = 0
    level, peak = loudness(mix)
    pcm = (np.clip(mix, -1, 1) * 32767).astype('<i2')
    import subprocess
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-', a.out], input=pcm.tobytes(), check=True)
    print(f'music from {MUSIC_START:.3f}s of the track; mastered {gain:+.1f} dB, {level:.1f} LUFS, true peak {peak:.1f} dBTP; wrote {a.out}')


if __name__ == '__main__':
    main()

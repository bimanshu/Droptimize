"""Soundtrack for film v4 (48 kHz stereo WAV). Spec: ../PROMPT-v4.md. Reuses mix.py's tools (UI sounds,
cross-fades, ducking maths, mastering) with the v4 music, edit points and voice placements.

    node render-v4.js events events-v4.json
    python3 mix-v4.py --music 175.mp3 --events events-v4.json --out mix-v4.wav
    python3 mix-v4.py --music 160.mp3 --bpm 128 --start 26.681 ...   # any other track: its tempo and the source time of film 0

Music (owner's pick, 2026-11-03): Mixkit 175 "Digital Clouds" by Alejandro Magaña (A. M.), measured 129.00 BPM,
stretched to 128; film t = 0 is its bar 15 downbeat (26.134 s), so its bass lift (bar 17) lands on film 3.1, the
reveal, and its quieter bars 33-36 fall in the dark "Never leaves your Mac" scene. Earlier: Mixkit 160
"Minimal Emotion" (128.00 BPM, --start 26.681).
"""
import argparse, json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mix import SR, decode, db, ramp, crossfade, synth, master, loudness   # noqa: E402

BEAT = 60 / 128
BAR = 4 * BEAT
T = lambda bar, beat=1: (bar - 1) * BAR + (beat - 1) * BEAT
PICTURE, END = T(29), T(29) + 3          # 52.5 s of picture, then 3 s of silence on the end card
MUSIC_BPM, MUSIC_START = 129.0, 20.553  # Digital Clouds: its bar 12 downbeat (source time), so its bar 17 lift lands on the drop, film bar 6
HERE = os.path.dirname(os.path.abspath(__file__))
FULL = os.path.join(HERE, '..', 'audio', 'emma-vo-full.mp3')
EXTRA = os.path.join(HERE, '..', 'audio', 'emma-vo-extra.mp3')
ROUTINE = os.path.join(HERE, '..', 'audio', 'emma-vo-routine.mp3')   # the old-way opening (2026-11-04), one take
SRC_GAIN = {ROUTINE: 10 ** (2.4 / 20)}     # that take is 2.4 dB quieter than the others (−23.7 vs −21.3 LUFS)
# Emma's lines: (source file, start, end in the source, film time). Starts match v4.html's AT table.
LINES = [
    (ROUTINE, 0.09, 8.74, 0.10),     # Need a smaller file? Find a website. Upload. Wait. Download. Unzip. Every single time.
                                     #   one piece, exactly as she read it (cutting it into phrases clipped the m of "time")
    (ROUTINE, 9.40, 10.74, T(6) + 0.12),   # Or just drop it. ("drop" with the release on the bubble)
    (FULL, 3.65, 4.80, T(7, 2)),     # Meet Droptimize.
    (EXTRA, 0.03, 3.83, T(8)),       # Drag from anywhere. Finder, Photos, or the web.
    (FULL, 6.21, 9.43, T(10, 3)),     # Drop any photo or video on the bubble. Done.
    (FULL, 10.63, 13.78, T(13, 2)),  # Convert to WebP or AVIF in one move.
    (FULL, 14.88, 16.47, T(16, 2)),  # Lift the background right out.
    (FULL, 17.62, 20.45, T(18, 2)),  # Videos too, down to whatever size you need.
    (FULL, 21.48, 23.70, T(21, 2)),  # All on your Mac. Nothing uploaded.
    (EXTRA, 5.84, 7.12, T(22, 4)),   # No internet needed.
    (FULL, 24.75, 27.77, T(24, 2)),  # Batches in one drop. Already on your clipboard.
    (FULL, 28.85, 31.22, T(27)),     # Droptimize. Drop it. Done.
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--music', required=True); ap.add_argument('--events', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--bpm', type=float, default=MUSIC_BPM, help="the track's measured tempo; it's time-stretched to 128")
    ap.add_argument('--start', type=float, default=MUSIC_START, help='source time (s) of the downbeat that starts the film')
    a = ap.parse_args()
    N = int(END * SR)

    # ── Music: stretched to 128 BPM if needed (Minimal Emotion already is); cut so the chosen downbeat starts the film
    rate = 128.0 / a.bpm
    tempo = f'atempo={rate:.6f},' if abs(rate - 1) > 1e-4 else ''
    start = int(a.start / rate * SR)
    def cut(x):
        y = np.zeros((N, 2), np.float32); seg = x[start:start + int(PICTURE * SR)]
        y[:len(seg)] = seg; return y
    music = cut(decode(a.music, tempo.rstrip(',') or None))
    lp800 = cut(decode(a.music, tempo + 'lowpass=f=800:p=2'))
    lp300 = cut(decode(a.music, tempo + 'lowpass=f=300:p=2,lowpass=f=300:p=2'))
    music = crossfade(music, lp800, 0, T(6), 0.06)                 # the old way, muffled; it opens up on the drop
    music = crossfade(music, lp800, T(23, 4), T(24), 0.03)          # a breath before the batch
    tail = crossfade(lp800, lp300, T(27) + 0.8, PICTURE, 0.5)       # ending: low-pass sweep after the final hit
    music = crossfade(music, tail, T(27), PICTURE, 0.08)
    fade = np.ones(N); a0, a1 = int(T(27) * SR), int((PICTURE - 0.25) * SR)
    fade[a0:a1] = np.linspace(1, 0, a1 - a0) ** 1.6; fade[a1:] = 0
    music *= fade[:, None]
    music *= db(-20) / (np.sqrt((music[int(8 * SR):int(46 * SR)] ** 2).mean()) + 1e-9)

    # ── Voice
    src = {p: decode(p, 'highpass=f=90:p=2', ch=1)[:, 0] * SRC_GAIN.get(p, 1.0) for p in (FULL, EXTRA, ROUTINE)}
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
    print(f'music from {a.start:.3f}s of the track at {a.bpm} BPM; mastered {gain:+.1f} dB, {level:.1f} LUFS, true peak {peak:.1f} dBTP; wrote {a.out}')


if __name__ == '__main__':
    main()

"""Builds the film's soundtrack (48 kHz stereo WAV) from the music, Emma's voice-over and the
cue list exported by render.js (`node render.js events events.json`). Spec: ../HANDOFF-VIDEO.md.

    python3 mix.py --music 132.mp3 --vo ../audio/emma-vo-full.mp3 --events events.json --out mix.wav

numpy + ffmpeg only (no scipy). Filters run in ffmpeg on whole stems; numpy does the edits,
cross-fades, ducking and the synthesised UI sounds.
"""
import argparse, json, subprocess, numpy as np

SR = 48000
PICTURE, END = 28.5, 31.5          # music and voice stop by 28.5 s; silence to the end
DROP = 2.0                          # film time of the music's first full downbeat (track bar 9)
STRETCH = 120 / 120.90              # Hazy After Hours measures 120.90 BPM; play it at 120

def decode(path, filt=None, ch=2):
    cmd = ['ffmpeg', '-v', 'error', '-i', path]
    if filt: cmd += ['-af', filt]
    cmd += ['-ac', str(ch), '-ar', str(SR), '-f', 'f32le', '-']
    a = np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32)
    return a.reshape(-1, ch).copy()

def db(x): return 10 ** (x / 20)
def ramp(n): return 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))

def find_downbeat(music, guess):
    """The sub-bass onset nearest `guess` seconds (the track's bar 9)."""
    mono = music.mean(1)
    lo = np.convolve(mono, np.ones(400) / 400, 'same')               # crude low-pass (~120 Hz)
    env = np.sqrt(np.convolve(lo ** 2, np.ones(480) / 480, 'same'))  # 10 ms RMS
    a, b = int((guess - 0.25) * SR), int((guess + 0.25) * SR)
    d = np.diff(env[a:b])
    return (a + int(np.argmax(d))) / SR

def crossfade(base, other, t0, t1, fade=0.04):
    """Use `other` between t0 and t1 seconds (with short cross-fades)."""
    out = base.copy(); n = int(fade * SR)
    a, b = int(t0 * SR), int(t1 * SR)
    w = np.zeros(len(base)); w[a:b] = 1
    if a > 0: w[max(0, a - n):a] = ramp(min(n, a))
    w[b:b + n] = ramp(n)[::-1][:len(w[b:b + n])]
    return out * (1 - w)[:, None] + other * w[:, None]

def synth(kind, rng):
    """Dry, soft UI sounds (≈18 dB under the music)."""
    def add(*parts):
        out = np.zeros(max(len(x) for x in parts))
        for x in parts: out[:len(x)] += x
        return out
    def env(n, attack, decay):
        t = np.arange(n) / SR
        return np.minimum(1, t / max(attack, 1e-4)) * np.exp(-t / decay)
    def tone(f0, f1, dur, attack, decay, gain):
        n = int(dur * SR); t = np.arange(n) / SR
        f = np.linspace(f0, f1, n); ph = 2 * np.pi * np.cumsum(f) / SR
        return gain * np.sin(ph) * env(n, attack, decay)
    def noise(dur, attack, decay, gain, smooth=8):
        n = int(dur * SR); x = rng.standard_normal(n)
        x = np.convolve(x, np.ones(smooth) / smooth, 'same')        # soften the top
        return gain * x * env(n, attack, decay)
    if kind in ('tick', 'progress'):  return add(tone(2600, 2400, .03, .0005, .006, db(-30)), noise(.02, .0003, .003, db(-40), 3))
    if kind == 'fan':                 return tone(1800, 1700, .03, .0005, .007, db(-34))
    if kind == 'fanSmall':            return tone(2300, 2200, .025, .0005, .005, db(-38))
    if kind == 'count':               return tone(2800, 2700, .025, .0005, .005, db(-34))
    if kind == 'grab':                return add(tone(420, 380, .05, .001, .012, db(-30)), noise(.03, .0005, .005, db(-40)))
    if kind == 'wake':                return tone(240, 340, .12, .004, .04, db(-32))
    if kind == 'drop':                return add(tone(150, 70, .25, .002, .07, db(-22)), noise(.06, .001, .015, db(-36), 30))
    if kind in ('swish', 'fill'):     return noise(.32, .12, .08, db(-38), 20)
    if kind == 'whoosh':              return noise(.5, .25, .12, db(-34), 30)
    if kind == 'done':                return tone(640, 620, .12, .002, .035, db(-32))
    if kind == 'cut':                 return add(noise(.05, .0005, .008, db(-32), 6), tone(90, 60, .12, .002, .04, db(-30)))
    if kind == 'click':               return add(tone(2000, 1900, .02, .0003, .004, db(-28)), noise(.015, .0002, .002, db(-36), 2))
    if kind == 'key':                 return add(noise(.04, .0005, .006, db(-28), 10), tone(300, 220, .06, .001, .018, db(-28)))
    if kind == 'paste':               return tone(520, 560, .08, .002, .025, db(-30))
    if kind == 'hit':                 # the final deep hit on the logo
        n = int(2.2 * SR); t = np.arange(n) / SR
        f = 38 + 17 * np.exp(-t / 0.08); ph = 2 * np.pi * np.cumsum(f) / SR
        body = np.sin(ph) * np.minimum(1, t / 0.004) * np.exp(-t / 0.55)
        click = noise(.05, .0005, .01, 1, 40)
        out = db(-5) * body
        out[:len(click)] += db(-26) * click
        return out
    return np.zeros(1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--music', required=True); ap.add_argument('--vo', required=True)
    ap.add_argument('--events', required=True); ap.add_argument('--out', required=True)
    a = ap.parse_args()
    N = int(END * SR)

    # ── Music: stretch to 120 BPM, put bar 9's downbeat at DROP
    stretch = f'atempo={STRETCH:.6f}'
    full = decode(a.music, stretch)
    # Bar 9's downbeat from the beat grid (first beat 0.476 s at 120.90 BPM; folding the onsets over
    # the grid puts it 5 ms late). Onset-picking near the drop latches onto a bass swell instead.
    bar9 = 0.476 / STRETCH + 32 * 0.5 + 0.005
    start = int((bar9 - DROP) * SR)
    def cut(x):
        y = np.zeros((N, 2), np.float32); seg = x[start:start + int(PICTURE * SR)]
        y[:len(seg)] = seg; return y
    music = cut(full)
    hp = cut(decode(a.music, stretch + ',highpass=f=250:p=2,highpass=f=250:p=2'))
    lp800 = cut(decode(a.music, stretch + ',lowpass=f=800:p=2'))
    lp300 = cut(decode(a.music, stretch + ',lowpass=f=300:p=2,lowpass=f=300:p=2'))
    music = crossfade(music, hp, 0, DROP, 0.03)                    # no bass until the drop
    music = crossfade(music, lp800, 11.5, 12.0, 0.03)              # a breath before Remove BG
    music = crossfade(music, lp800, 25.5, 26.0, 0.03)              # and before the logo
    # Ending: low-pass sweep and fade after the final hit
    tail = crossfade(lp800, lp300, 26.8, PICTURE, 0.5)
    music = crossfade(music, tail, 26.0, PICTURE, 0.08)
    fade = np.ones(N); a0, a1 = int(26.0 * SR), int(28.3 * SR)
    fade[a0:a1] = np.linspace(1, 0, a1 - a0) ** 1.6; fade[a1:] = 0
    music *= fade[:, None]
    music *= db(-20) / (np.sqrt((music[int(3 * SR):int(25 * SR)] ** 2).mean()) + 1e-9)   # groove at ≈ −20 dBFS RMS

    # ── Voice-over: Emma's single take, cut into lines and placed on the beat
    vo_src = decode(a.vo, 'highpass=f=90:p=2', ch=1)[:, 0]
    LINES = [(0.08, 1.85, 0.25), (3.65, 4.80, 2.50), (6.21, 9.43, 4.00), (10.63, 13.78, 8.00), (14.88, 16.47, 12.00),
             (17.62, 20.45, 16.00), (21.48, 23.70, 20.00), (24.75, 27.77, 22.50), (28.85, 31.22, 26.00)]
    vo = np.zeros(N, np.float32); m = int(0.03 * SR); f = int(0.01 * SR)
    for s0, s1, at in LINES:
        seg = vo_src[max(0, int(s0 * SR) - m):int(s1 * SR) + m].copy()
        seg[:f] *= ramp(f); seg[-f:] *= ramp(f)[::-1]
        p = int(at * SR) - m
        vo[p:p + len(seg)] += seg[:N - p]
    vo *= db(-16) / (np.sqrt((vo[np.abs(vo) > 1e-3] ** 2).mean()) + 1e-9)

    # Duck the music 8 dB under the voice (80 ms attack, 250 ms release)
    env = np.sqrt(np.convolve(vo ** 2, np.ones(960) / 960, 'same'))
    target = np.where(env > db(-40), db(-8), 1.0)
    g = np.empty(N); cur = 1.0
    att, rel = np.exp(-1 / (0.08 * SR)), np.exp(-1 / (0.25 * SR))
    for i in range(0, N, 48):                                       # 1 ms control rate
        k = att if target[i] < cur else rel
        cur = target[i] + (cur - target[i]) * k ** 48
        g[i:i + 48] = cur
    music *= g[:, None]

    # ── UI sounds from the cue list
    rng = np.random.default_rng(7)
    ui = np.zeros(N, np.float32)
    for t, kind in json.load(open(a.events)):
        snd = synth(kind, rng); p = int(t * SR)
        if p >= N: continue
        ui[p:p + len(snd)] += snd[:N - p]

    mix = music + vo[:, None] + ui[:, None] * np.array([[1.0, 0.94]])
    mix[int(PICTURE * SR):] = 0
    peak = np.abs(mix).max()
    mix *= db(-1) / peak if peak > db(-1) else 1
    mix = np.tanh(mix * 1.05) / np.tanh(1.05)                       # gentle safety limiter
    pcm = (np.clip(mix, -1, 1) * 32767).astype('<i2')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-', a.out], input=pcm.tobytes(), check=True)
    print(f'bar 9 at {bar9:.3f}s in the stretched track; music starts at {start / SR:.3f}s; wrote {a.out}')

main()

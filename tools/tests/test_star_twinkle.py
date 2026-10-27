"""Reference test for star twinkling (lib/sky/stars.glsl, starTwinkle / twinkleSigma).

Mirrors the GLSL (constants read from the source) and checks, for every strength and speed:
1. the time-averaged brightness of a star is unchanged (twinkling only redistributes it);
2. stars overhead are steady and stars near the horizon twinkle more, up to the cap;
3. no star ever drops out (minimum brightness) or flashes (maximum);
4. different stars twinkle independently;
5. brightness changes smoothly from frame to frame, at any frame rate;
6. nothing jumps when frameTimeCounter wraps at 3600 s.

    python -P tools/tests/test_star_twinkle.py
"""

import math
import os
import re

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = open(os.path.join(ROOT, "shaders", "lib", "sky", "stars.glsl"), encoding="utf-8").read()
STRENGTH = {int(k): (float(z), float(m)) for k, z, m in re.findall(
    r"STAR_TWINKLE_STRENGTH == (\d)\nconst float TWINKLE_ZENITH = ([\d.]+); const float TWINKLE_MAX = ([\d.]+);", SRC)}
STRENGTH[2] = tuple(float(x) for x in re.search(
    r"#else\nconst float TWINKLE_ZENITH = ([\d.]+); const float TWINKLE_MAX = ([\d.]+);", SRC).groups())
RATES = (0.5, 1.0)
assert "const float TWINKLE_RATE = 0.5;" in SRC and "const float TWINKLE_RATE = 1.0;" in SRC
TAU = 2 * math.pi
M32 = 0xffffffff


def star_hash(x):
    x &= M32
    x ^= x >> 16; x = (x * 0x7feb352d) & M32
    x ^= x >> 15; x = (x * 0x846ca68b) & M32
    x ^= x >> 16
    return x


def sigma(cos_zenith, zenith, cap):
    airmass = 1.0 / max(cos_zenith, 0.08)
    return min(zenith * airmass * math.sqrt(airmass), cap)


def twinkle(star_id, s, rate, t, flux=1e-5, horizon=0.0):
    """Luminance factor (the hue term has zero mean over the channels) for times t (array)."""
    lg = math.log10(max(flux, 1e-12))
    e = min(max((lg + 7.68) / 1.2, 0.0), 1.0)
    s = s * (0.35 + 0.65 * e * e * (3 - 2 * e))
    cycle = 1.0 / 3600.0
    n = np.zeros_like(t)
    h = star_hash((star_id * 0x9e3779b9 + 0x632be5ab) & M32)
    for _ in range(3):
        h = star_hash(h)
        f = round((0.6 + 1.4 * (h & 0xffff) / 65535.0) * rate / cycle) * cycle
        ph = (h >> 16) / 65535.0 * TAU
        n += np.sin(TAU * f * t + ph)
    n *= 0.8165
    return np.exp(s * n - 0.5 * s * s)


IDS = [star_hash(i * 7919 + 13) for i in range(200)]
T = np.arange(0.0, 600.0, 1.0 / 60.0)


def test_mean_and_range():
    for k, (z, cap) in sorted(STRENGTH.items()):
        for rate in RATES:
            for cz, label in ((1.0, "zenith"), (0.17, "10 deg")):
                s = sigma(cz, z, cap)
                g = np.stack([twinkle(i, s, rate, T) for i in IDS[:40]])
                mean = g.mean(axis=1)
                assert np.abs(mean - 1.0).max() < 0.03, (k, rate, label, mean.min(), mean.max())
                assert g.min() > 0.3 and g.max() < 3.0, (k, rate, label, g.min(), g.max())
    print("brightness: time average within 3 % of the star's own for every setting; never below 0.3x or above 3x")


def test_elevation():
    z, cap = STRENGTH[1]
    rows = []
    for deg in (90, 45, 20, 10, 3):
        s = sigma(math.sin(math.radians(deg)), z, cap)
        g = np.stack([twinkle(i, s, 1.0, T) for i in IDS[:40]])
        rows.append((deg, float((g.std(axis=1) / g.mean(axis=1)).mean()), float(g.min()), float(g.max())))
    stds = [r[1] for r in rows]
    assert all(a <= b + 1e-9 for a, b in zip(stds, stds[1:])) and stds[0] < 0.05 and stds[-1] < 0.25
    print("Normal strength, relative brightness spread by elevation: "
          + ", ".join(f"{d} deg {100 * s:.0f} % ({lo:.2f}-{hi:.2f}x)" for d, s, lo, hi in rows))


def test_independent():
    s = sigma(0.3, *STRENGTH[1])
    g = np.stack([np.log(twinkle(i, s, 1.0, T)) for i in IDS])
    c = np.corrcoef(g)
    off = np.abs(c[~np.eye(len(IDS), dtype=bool)])
    assert np.median(off) < 0.05 and off.max() < 0.75, (np.median(off), off.max())
    print(f"independence: median |correlation| between two stars {np.median(off):.3f} (max {off.max():.2f} over {len(IDS)} stars)")


def test_smooth_frames():
    z, cap = STRENGTH[2]
    for fps in (30, 60, 144):
        t = np.arange(0.0, 120.0, 1.0 / fps)
        worst = 0.0
        for deg in (90, 10):
            s = sigma(math.sin(math.radians(deg)), z, cap)
            g = np.stack([twinkle(i, s, 1.0, t) for i in IDS[:40]])
            step = np.abs(np.diff(g, axis=1) / g[:, :-1])
            worst = max(worst, float(np.percentile(step, 99)))
        assert worst < (0.25 if fps == 30 else 0.13), (fps, worst)
        print(f"frames: High strength, 99th percentile change between frames at {fps} FPS: {100 * worst:.1f} %")


def test_hour_wrap():
    s = sigma(0.2, *STRENGTH[2])
    for rate in RATES:
        for i in IDS[:50]:
            a = twinkle(i, s, rate, np.array([3600.0]))[0]
            b = twinkle(i, s, rate, np.array([0.0]))[0]
            assert abs(a - b) < 1e-6, (rate, i, a, b)
    print("wrap: brightness at 3600 s equals that at 0 s for every star (whole cycles per hour)")


if __name__ == "__main__":
    test_mean_and_range()
    test_elevation()
    test_independent()
    test_smooth_frames()
    test_hour_wrap()
    print("OK")

"""Reference test for the footprint prefilter of the water waves (lib/water/waves.glsl).

Ports the wave trains (open ocean, default options) and checks:
1. retained + lost slope variance = the unfiltered total, for any footprint;
2. near water (1 cm footprint) is unchanged; long swells survive a 1-block footprint while the
   0.55-block trains are removed;
3. aliasing: the filtered gradient sampled once per pixel is much closer to the true
   pixel-averaged (supersampled) gradient than the unfiltered one.

    python -P tools/tests/test_wave_filter.py
"""

import numpy as np

TRAINS = 16
G = 9.81
LATTICE = 2 * np.pi / 1536


def trains(swell=1.0, chop=0.6, calm=0.0, storm=0.0, wind=(1.0, 0.0)):
    """waveVector() / waveAmplitude() of lib/water/waves.glsl: fixed lattice vectors, amplitude
    from the steepness budget and the directional spreading function."""
    out = []
    wind = np.array(wind)
    for i in range(TRAINS):
        fi = float(i)
        lam = 46.0 * (0.55 / 46.0) ** (fi / (TRAINS - 1))
        ang = fi * 2.399963 + 0.5
        kv = np.round(np.array([np.cos(ang), np.sin(ang)]) * (2 * np.pi / lam) / LATTICE) * LATTICE
        k = np.linalg.norm(kv)
        longness = 1 - fi / (TRAINS - 1)
        energy = chop + (swell - chop) * longness ** 2
        energy *= 1.0 + (0.25 - 1.0) * calm * longness
        energy *= 1.0 + 0.9 * storm
        along = kv.dot(wind) / k
        spread = 0.1 + 0.9 * np.clip(0.5 + 0.5 * along, 0, 1) ** 2
        a = 0.1 * energy * spread / k
        out.append((kv / k, k, a, fi * 2.399963))
    return out


def wfilter(k, f):
    return np.exp(-(k * f) ** 2 / 24.0)


def grad(xs, f, tr):
    """x-gradient along a line in the wind direction (sinusoid part; sharpening omitted)."""
    g = np.zeros_like(xs)
    for d, k, a, ph in tr:
        g += wfilter(k, f) * a * k * np.cos(k * d[0] * xs + ph) * d[0]
    return g


def test_variance_budget():
    tr = trains()
    total = sum(0.5 * (a * k) ** 2 for _, k, a, _ in tr)
    for f in (0.0, 0.05, 0.3, 1.0, 4.0):
        kept = sum(0.5 * (a * k * wfilter(k, f)) ** 2 for _, k, a, _ in tr)
        lost = sum(0.5 * (a * k) ** 2 * (1 - wfilter(k, f) ** 2) for _, k, a, _ in tr)
        assert abs(kept + lost - total) < 1e-12
    print(f"variance budget: kept + lost = total slope variance ({total:.4f}) for all footprints")


def test_band():
    tr = trains()
    k_short, k_long = tr[-1][1], tr[0][1]
    assert wfilter(k_short, 0.01) > 0.995 and wfilter(k_long, 0.01) > 0.9999
    assert wfilter(k_short, 1.0) < 0.01 and wfilter(k_long, 1.0) > 0.99
    print(f"band: 1 cm footprint keeps everything; 1 block keeps the 46-block swell "
          f"({wfilter(k_long, 1.0):.3f}) and removes the 0.55-block train ({wfilter(k_short, 1.0):.1e})")


def test_aliasing():
    tr = trains()
    rng = np.random.default_rng(5)
    for f in (0.1, 0.3, 0.8, 2.0):
        px = np.arange(400) * f + rng.uniform(0, f)
        # Truth: the gradient averaged over each pixel (64 sub-samples across its width).
        sub = (np.arange(64) + 0.5) / 64 - 0.5
        truth = np.mean([grad(px + s * f, 0.0, tr) for s in sub], axis=0)
        raw = grad(px, 0.0, tr)
        filt = grad(px, f, tr)
        e_raw = np.sqrt(np.mean((raw - truth) ** 2))
        e_filt = np.sqrt(np.mean((filt - truth) ** 2))
        print(f"footprint {f:.1f} block: rms error vs pixel average  unfiltered {e_raw:.4f}  filtered {e_filt:.4f}")
        assert e_filt <= e_raw * 1.01                  # never worse, also up close
        if f >= 0.8:
            assert e_filt < 0.3 * e_raw                 # strongly better where aliasing starts


if __name__ == "__main__":
    test_variance_budget()
    test_band()
    test_aliasing()
    print("OK")

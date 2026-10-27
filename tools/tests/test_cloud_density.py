"""Reference test for the cloud density model (lib/clouds/clouds_common.glsl, cloudDensity).

Evaluates the 3D density on the pack's noise textures (via tools/cloud_preview.py) and checks:
1. the shape noise is equalised: its values are spread evenly over 0..1, so a coverage threshold
   carves that fraction of the volume into cloud (the old shape value was 0.69 +- 0.14, so any
   coverage above ~0.3 filled whole groups);
2. the sky cover seen from below (vertical optical depth > 1) follows CLOUD_COVERAGE;
3. clouds are separate: a partly cloudy sky breaks into several times as many distinct clouds as
   the old model, which joined each group into a few solid masses (seen from above at 40-65 %
   cover, thin edges still link many cumulus into lace, so the largest connected area is
   reported, not required to shrink);
4. thunderstorms grow cumulonimbus towers with anvils above 7 km; fair weather has neither.

    python -P tools/tests/test_cloud_density.py          (about 1 minute)
"""

import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import cloud_preview as cp  # noqa: E402

COMMON = open(os.path.join(ROOT, "shaders", "lib", "clouds", "clouds_common.glsl"), encoding="utf-8").read()
SITES = [(0.0, 0.0), (-40000.0, 30000.0), (60000.0, -20000.0), (90000.0, 70000.0), (20000.0, 50000.0), (-70000.0, -60000.0)]


def area(origin, extent=30000.0, res=200):
    g = (np.arange(res) + 0.5) / res * extent
    X, Z = np.meshgrid(g + origin[0], g + origin[1])
    return np.stack([X.ravel(), Z.ravel()], -1), res


def label(mask):
    """Connected components (4-neighbour) by iterative minimum-label propagation."""
    lab = np.where(mask, np.arange(mask.size).reshape(mask.shape), mask.size)
    while True:
        n = lab.copy()
        n[1:] = np.minimum(n[1:], lab[:-1]); n[:-1] = np.minimum(n[:-1], lab[1:])
        n[:, 1:] = np.minimum(n[:, 1:], lab[:, :-1]); n[:, :-1] = np.minimum(n[:, :-1], lab[:, 1:])
        n = np.where(mask, n, mask.size)
        if np.array_equal(n, lab):
            return lab
        lab = n


def old_column_od(xz, cov):
    """The previous model (027c7a8) at the same columns, for comparison."""
    E = cp.Env(cov)
    a, b = cp.wn(xz, 1.0), cp.wn(xz + 7919.0, 3.0)
    systems = cp.systems_from(a, b)
    warp = (np.stack([a[..., 1], b[..., 1]], -1) - 0.5) * 2600.0
    c, d = cp.wn(xz + warp, 11.0), cp.wn(xz + warp * 0.5 + 3313.0, 5.0)
    cluster = cp.ss(0.328, 0.748, d[..., 1] * 0.55 + c[..., 1] * 0.30 + c[..., 3] * 0.15)
    conv = cp.ss(0.226, 0.854, d[..., 2])
    swing = min(1.125, 2.25 * min(cov, 1 - cov))
    target = cp.sat(cov + (systems - 0.5) * swing)
    covr = cp.ss(1 - target - 0.18, 1 - target + 0.18, cluster) * cp.mix(0.4, 0.85, target)
    t = cp.mix(0.34, 0.62, 1 - cp.ss(0.35, 0.8, systems))
    t = np.clip(t + (conv - 0.5) * 0.35, 0.2, 0.8)
    t = cp.mix(t, 0.1, cp.ss(0.85, 1, systems) * cp.ss(0.6, 0.9, target) * cp.ss(0.55, 0.8, 1 - conv))
    base = cp.mix(cp.CLOUD_BASE + (conv - 0.5) * 400, cp.STRATUS_BASE, 1 - cp.ss(0.1, 0.3, t))
    thick = cp.mix(cp.mix(450.0, 800.0, cp.ss(0.08, 0.35, t)), 900 + 1500 * conv, cp.ss(0.35, 0.62, t))
    top = np.minimum(base + thick, cp.TOP_LOW)
    od = np.zeros(len(xz))
    for i in range(28):
        h = base + (i + 0.5) / 28 * (top - base)
        h01 = (i + 0.5) / 28
        prof = cp.ss(0, cp.mix(0.22, 0.07, t), h01) * (1 - cp.ss(cp.mix(0.45, 0.62, t), 1, h01)) * cp.mix(1, 1 - h01 * 0.4, cp.sat(t * 1.6))
        p = np.stack([xz[:, 0], h + 62, xz[:, 1]], -1)
        p[:, [0, 2]] -= E.wind * ((h - base) * (0.06 + 0.12 * E.windS))[:, None]
        s = cp.tex3(cp.SHAPE, p / (cp.WRAP / 32) * np.array([1, 1.6, 1]))
        f = cp.tex3(cp.SHAPE, (p + np.array([1733.0, 911.0, -2437.0])) / cp.SHAPE_TILE_2 * np.array([1, 1.3, 1]))
        wy = f[..., 1] * 0.625 + f[..., 2] * 0.25 + f[..., 3] * 0.125
        shape = (s[..., 0] - (wy - 1)) / (2 - wy)
        shape = cp.mix(shape, wy, 0.4 * cp.sat(1 - abs(t - 0.35) / 0.2))
        shape = cp.mix(shape, 0.55 + 0.45 * wy, 1 - cp.ss(0.08, 0.28, t))
        dd = cp.sat((shape * prof - (1 - covr)) / np.maximum(covr, 1e-4)) * covr
        od += dd * cp.mix(0.028, 0.045, t) * (top - base) / 28
    return od


def test_constants_match_shader():
    for s in ("const vec3 SHAPE_STRETCH = vec3(1.0, 0.65, 1.0);", "float u = equalise(pw - (1.0 - worley) * 0.3, 0.362, 0.15);", "const float CELL_SHARE = 0.65;",
              "float d = saturate((u - (1.0 - covH)) * 5.0);", "const float SHAPE_TILE_S = CLOUD_WRAP / 64.0;",
              "return density * 0.04 * CLOUD_DENSITY;", "float ero = df * 0.6 + (1.0 - ff) * 0.4;",
              "d = remap(d, ero * mix(0.45, 0.25, st), 1.0);", "const float ANVIL_BASE = 7000.0;",
              "1.0 - smoothstep(8.0, 30.0, footprint)"):
        assert s in COMMON, s
    print("constants: tools/cloud_preview.py matches lib/clouds/clouds_common.glsl")


def test_equalised_shape():
    rng = np.random.default_rng(3)
    p = rng.random((200000, 3)) * np.array([60000.0, 3000.0, 60000.0]) + np.array([0.0, 1400.0, 0.0])
    sl = cp.tex3(cp.SHAPE, p / cp.SHAPE_TILE * cp.STRETCH)
    s = cp.mix(sl[..., 0], sl[..., 1], cp.CELL)
    f = cp.tex3(cp.SHAPE, p / cp.SHAPE_TILE_2 * np.array([1.0, 0.8, 1.0]))
    worley = f[..., 1] * 0.625 + f[..., 2] * 0.25 + f[..., 3] * 0.125
    u = cp.equalise(s - (1 - worley) * 0.3, 0.362, 0.15)
    old = (sl[..., 0] - (worley - 1)) / (2 - worley)
    for c in (0.2, 0.5, 0.8):
        frac = float(np.mean(u > 1 - c))
        assert abs(frac - c) < 0.07, (c, frac)
    print("shape noise: fraction above the threshold 1 - c for c = 0.2 / 0.5 / 0.8: "
          + " / ".join(f"{np.mean(u > 1 - c):.2f}" for c in (0.2, 0.5, 0.8))
          + f" (old shape value {old.mean():.2f} +- {old.std():.2f}: {100 * np.mean(old > 0.3):.0f} % above a 0.7 coverage threshold)")


def test_sky_cover():
    rows = []
    for cov in (0.2, 0.45, 0.7):
        covers = []
        for o in SITES:
            xz, res = area(o, res=120)
            od, _ = cp.column_optical_depth(xz, cp.Env(cov), nh=20)
            covers.append(np.mean(od > 1.0))
        rows.append((cov, float(np.mean(covers)), min(covers), max(covers)))
    for cov, m, lo, hi in rows:
        assert abs(m - cov) < 0.08, (cov, m)
    print("sky cover from below (vertical optical depth > 1) for Coverage 0.2 / 0.45 / 0.7: "
          + " / ".join(f"{m:.2f} ({lo:.2f}-{hi:.2f} across 30 km areas)" for _, m, lo, hi in rows))


def test_separate_clouds():
    new_big, old_big, new_n, old_n = [], [], [], []
    for o in SITES:
        xz, res = area(o, extent=15000.0, res=200)          # 75 m columns
        od, _ = cp.column_optical_depth(xz, cp.Env(0.45), nh=20)
        mask = od.reshape(res, res) > 1.0
        oldm = old_column_od(xz, 0.45).reshape(res, res) > 1.0
        for m, big, num in ((mask, new_big, new_n), (oldm, old_big, old_n)):
            if m.mean() < 0.1 or m.mean() > 0.8:
                continue                                       # skip clear and overcast skies
            lab = label(m)
            _, counts = np.unique(lab[m], return_counts=True)
            big.append(counts.max() / m.sum())
            num.append(len(counts))
    assert np.median(new_n) > 3.0 * np.median(old_n), (new_n, old_n)
    print(f"separate clouds (Coverage 0.45, partly cloudy 15 km skies): largest connected cloud holds "
          f"{100 * np.median(new_big):.0f} % of the cloud (old {100 * np.median(old_big):.0f} %), "
          f"{np.median(new_n):.0f} distinct clouds (old {np.median(old_n):.0f})")


def test_storms():
    rng = np.random.default_rng(5)
    xz = rng.random((40000, 2)) * 120000.0
    fair = cp.weather(xz, cp.Env(0.45))
    storm = cp.weather(xz, cp.Env(0.45, rain=1.0, thunder=1.0))
    assert (fair["type"] > 0.9).mean() == 0 and fair["anvil"].max() == 0
    tall = (storm["top"] > 7000).mean()
    hs = np.full(len(xz), 8000.0)
    anvil = cp.density(np.stack([xz[:, 0], hs + 62, xz[:, 1]], -1), storm, 1, cp.Env(0.45, 1.0, 1.0)) > 0
    assert 0.03 < tall < 0.5 and anvil.mean() > tall * 0.5, (tall, anvil.mean())
    print(f"storms: cumulonimbus towers above 7 km over {100 * tall:.0f} % of the area, cloud at 8 km "
          f"(towers and anvils) over {100 * anvil.mean():.0f} %; fair weather: none")


if __name__ == "__main__":
    test_constants_match_shader()
    test_equalised_shape()
    test_sky_cover()
    test_separate_clouds()
    test_storms()
    print("OK")

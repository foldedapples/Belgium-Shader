#!/usr/bin/env python3
"""Generates the pack's procedural noise textures (all original data, no third-party input).

  shaders/textures/bluenoise.png   128x128 RGBA, four independent blue-noise channels made with
                                   the void-and-cluster method (Ulichney 1993).
  shaders/textures/cloud_shape.bin 128^3 RGBA8 tileable: R Perlin-Worley, G/B/A Worley fBm at
                                   increasing frequency (cloud base shape).
  shaders/textures/cloud_detail.bin 32^3 RGBA8 tileable: R/G/B Worley fBm (edge erosion), A curl-ish
                                   value noise used for wisps.
  shaders/textures/noise2d.png     256x256 RGBA tileable value-noise fBm octaves (weather maps,
                                   wave modulation, stars).

Usage: python tools/gen_noise.py [--only bluenoise|clouds|noise2d]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "shaders" / "textures"


# ----------------------------------------------------------------------------- blue noise
def void_and_cluster(n: int, seed: int, sigma: float = 1.5) -> np.ndarray:
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n]
    dx = np.minimum(xx, n - xx)
    dy = np.minimum(yy, n - yy)
    kernel = np.exp(-(dx * dx + dy * dy) / (2.0 * sigma * sigma))
    kf = np.fft.rfft2(kernel)

    def energy(mask):
        return np.fft.irfft2(np.fft.rfft2(mask) * kf, s=(n, n))

    def shifted(i):
        y, x = divmod(i, n)
        return np.roll(np.roll(kernel, y, axis=0), x, axis=1)

    total = n * n
    # 1. initial binary pattern: ~10% random points, relaxed until stable
    mask = (rng.random((n, n)) < 0.1).astype(np.float64)
    e = energy(mask)
    for _ in range(total):
        tight = np.argmax(np.where(mask > 0, e, -np.inf))
        mask.flat[tight] = 0
        e -= shifted(tight)
        void = np.argmin(np.where(mask > 0, np.inf, e))
        if void == tight:
            mask.flat[tight] = 1
            e += shifted(tight)
            break
        mask.flat[void] = 1
        e += shifted(void)
    ones = int(mask.sum())
    rank = np.zeros(total, dtype=np.int64)

    # 2. remove ones from tightest clusters -> ranks ones-1 .. 0
    m = mask.copy(); en = e.copy()
    for r in range(ones - 1, -1, -1):
        tight = np.argmax(np.where(m > 0, en, -np.inf))
        m.flat[tight] = 0
        en -= shifted(tight)
        rank[tight] = r
    # 3. fill voids -> ranks ones .. total-1
    m = mask.copy(); en = e.copy()
    for r in range(ones, total):
        void = np.argmin(np.where(m > 0, np.inf, en))
        m.flat[void] = 1
        en += shifted(void)
        rank[void] = r
    return (rank.reshape(n, n).astype(np.float64) + 0.5) / total


def gen_bluenoise():
    n = 128
    chans = [void_and_cluster(n, seed) for seed in (11, 23, 37, 51)]
    img = np.stack(chans, axis=-1)
    Image.fromarray(np.clip(img * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(OUT / "bluenoise.png")
    (OUT / "bluenoise.png.mcmeta").write_text('{"texture": {"blur": false, "clamp": false}}\n')
    print("bluenoise.png written")


# ----------------------------------------------------------------------------- 3-D noise
def worley3(n: int, cells: int, rng) -> np.ndarray:
    """Tileable inverted Worley (F1) noise on an n^3 grid with `cells`^3 feature points."""
    pts = rng.random((cells, cells, cells, 3))
    coords = (np.arange(n) + 0.5) / n * cells
    gx, gy, gz = np.meshgrid(coords, coords, coords, indexing="ij")
    best = np.full((n, n, n), 1e9)
    ix, iy, iz = np.floor(gx).astype(int), np.floor(gy).astype(int), np.floor(gz).astype(int)
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            for oz in (-1, 0, 1):
                cx, cy, cz = ix + ox, iy + oy, iz + oz
                p = pts[cx % cells, cy % cells, cz % cells]
                d = (cx + p[..., 0] - gx) ** 2 + (cy + p[..., 1] - gy) ** 2 + (cz + p[..., 2] - gz) ** 2
                best = np.minimum(best, d)
    return 1.0 - np.clip(np.sqrt(best), 0.0, 1.0)


def perlin3(n: int, period: int, rng) -> np.ndarray:
    """Tileable gradient noise in [0,1]."""
    g = rng.normal(size=(period, period, period, 3))
    g /= np.linalg.norm(g, axis=-1, keepdims=True)
    coords = (np.arange(n) + 0.5) / n * period
    gx, gy, gz = np.meshgrid(coords, coords, coords, indexing="ij")
    ix, iy, iz = np.floor(gx).astype(int), np.floor(gy).astype(int), np.floor(gz).astype(int)
    fx, fy, fz = gx - ix, gy - iy, gz - iz
    fade = lambda t: t * t * t * (t * (t * 6 - 15) + 10)
    u, v, w = fade(fx), fade(fy), fade(fz)
    out = 0.0
    for ox in (0, 1):
        for oy in (0, 1):
            for oz in (0, 1):
                grad = g[(ix + ox) % period, (iy + oy) % period, (iz + oz) % period]
                dot = grad[..., 0] * (fx - ox) + grad[..., 1] * (fy - oy) + grad[..., 2] * (fz - oz)
                wx = u if ox else 1 - u
                wy = v if oy else 1 - v
                wz = w if oz else 1 - w
                out = out + dot * wx * wy * wz
    return np.clip(out * 0.9 + 0.5, 0.0, 1.0)


def fbm(fn, n, base, octaves, rng, gain=0.5):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + fn(n, base * (2 ** o), rng) * amp
        norm += amp
        amp *= gain
    return total / norm


def remap(x, a, b, c, d):
    return c + (x - a) * (d - c) / (b - a)


def gen_clouds():
    rng = np.random.default_rng(7)
    n = 128
    perlin = fbm(perlin3, n, 4, 4, rng, 0.55)
    w_low = fbm(worley3, n, 4, 3, rng, 0.6)
    # Perlin-Worley: Perlin dilated by Worley so blobs are billowy but connected
    pw = np.clip(remap(perlin, w_low - 1.0, 1.0, 0.0, 1.0), 0.0, 1.0)
    g = fbm(worley3, n, 8, 3, rng, 0.6)
    b = fbm(worley3, n, 16, 3, rng, 0.6)
    a = fbm(worley3, n, 32, 2, rng, 0.6)
    vol = np.stack([pw, g, b, a], axis=-1)
    # File order expected by Iris raw textures: x fastest, then y, then z.
    data = np.clip(vol * 255.0 + 0.5, 0, 255).astype(np.uint8).transpose(2, 1, 0, 3)
    (OUT / "cloud_shape.bin").write_bytes(data.tobytes())
    print("cloud_shape.bin written", data.shape)

    n = 32
    r = fbm(worley3, n, 2, 3, rng, 0.6)
    gg = fbm(worley3, n, 4, 3, rng, 0.6)
    bb = fbm(worley3, n, 8, 2, rng, 0.6)
    aa = fbm(perlin3, n, 4, 3, rng, 0.5)
    vol = np.stack([r, gg, bb, aa], axis=-1)
    data = np.clip(vol * 255.0 + 0.5, 0, 255).astype(np.uint8).transpose(2, 1, 0, 3)
    (OUT / "cloud_detail.bin").write_bytes(data.tobytes())
    print("cloud_detail.bin written", data.shape)
    # Iris defaults raw textures to clamp-to-edge; the cloud volumes must tile.
    for name in ("cloud_shape.bin", "cloud_detail.bin"):
        (OUT / (name + ".mcmeta")).write_text('{"texture": {"blur": true, "clamp": false}}\n')


# ----------------------------------------------------------------------------- 2-D noise
def value2(n, period, rng):
    lat = rng.random((period, period))
    coords = (np.arange(n) + 0.5) / n * period
    gx, gy = np.meshgrid(coords, coords, indexing="ij")
    ix, iy = np.floor(gx).astype(int), np.floor(gy).astype(int)
    fx, fy = gx - ix, gy - iy
    fade = lambda t: t * t * t * (t * (t * 6 - 15) + 10)
    u, v = fade(fx), fade(fy)
    a = lat[ix % period, iy % period]
    b = lat[(ix + 1) % period, iy % period]
    c = lat[ix % period, (iy + 1) % period]
    d = lat[(ix + 1) % period, (iy + 1) % period]
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v


def gen_noise2d():
    rng = np.random.default_rng(3)
    n = 256
    chans = []
    for base in (4, 8, 16, 32):
        total, amp, norm = 0.0, 1.0, 0.0
        for o in range(4):
            total = total + value2(n, base * 2 ** o, rng) * amp
            norm += amp
            amp *= 0.5
        x = total / norm
        x = (x - x.min()) / (x.max() - x.min())
        chans.append(x)
    img = np.stack(chans, axis=-1).transpose(1, 0, 2)
    Image.fromarray(np.clip(img * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(OUT / "noise2d.png")
    (OUT / "noise2d.png.mcmeta").write_text('{"texture": {"blur": true, "clamp": false}}\n')
    print("noise2d.png written")


def perlin2(n: int, period: int, rng) -> np.ndarray:
    """Tileable 2-D gradient (Perlin) noise, zero mean, roughly unit-range."""
    ang = rng.random((period, period)) * 2 * np.pi
    g = np.stack([np.cos(ang), np.sin(ang)], axis=-1)
    coords = (np.arange(n) + 0.5) / n * period
    gx, gy = np.meshgrid(coords, coords, indexing="ij")
    ix, iy = np.floor(gx).astype(int), np.floor(gy).astype(int)
    fx, fy = gx - ix, gy - iy
    fade = lambda t: t * t * t * (t * (t * 6 - 15) + 10)
    u, v = fade(fx), fade(fy)
    out = 0.0
    for ox in (0, 1):
        for oy in (0, 1):
            grad = g[(ix + ox) % period, (iy + oy) % period]
            dot = grad[..., 0] * (fx - ox) + grad[..., 1] * (fy - oy)
            out = out + dot * (u if ox else 1 - u) * (v if oy else 1 - v)
    return out


def gen_perlin2d():
    """perlin2d.png: the tileable Perlin texture the Halcyon sky/cloud modules sample as
    perlinNoiseTex. Our own noise, matched to the statistics those modules were tuned with:
    mean 0.5, standard deviation 0.053 per channel, energy spread over 4-128 cycles per tile
    (12.5 / 31 / 25 / 19 / 11 % in the bands 4-8 ... 64-128; a Perlin octave of lattice
    period P puts its energy just below P, hence periods 8 ... 128). Three independent
    channels in RGB, alpha 1."""
    rng = np.random.default_rng(11)
    n = 256
    periods = (8, 16, 32, 64, 128)
    energy = np.array([0.125, 0.31, 0.25, 0.19, 0.11])
    chans = []
    for _ in range(3):
        octs = [perlin2(n, p, rng) for p in periods]
        octs = [o / o.std() for o in octs]
        x = sum(np.sqrt(e) * o for e, o in zip(energy, octs))
        x = 0.5 + (x - x.mean()) / x.std() * 0.053
        chans.append(np.clip(x, 0.0, 1.0))
    chans.append(np.ones((n, n)))
    img = np.stack(chans, axis=-1).transpose(1, 0, 2)
    Image.fromarray(np.clip(img * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(OUT / "perlin2d.png")
    (OUT / "perlin2d.png.mcmeta").write_text('{"texture": {"blur": true, "clamp": false}}\n')
    print("perlin2d.png written")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["bluenoise", "clouds", "noise2d", "perlin2d"])
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.only in (None, "bluenoise"):
        gen_bluenoise()
    if args.only in (None, "noise2d"):
        gen_noise2d()
    if args.only in (None, "clouds"):
        gen_clouds()
    if args.only in (None, "perlin2d"):
        gen_perlin2d()


if __name__ == "__main__":
    main()

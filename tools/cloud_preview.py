"""Offline preview of the volumetric clouds (lib/clouds/clouds_common.glsl, program/deferred/clouds.csh).

A numpy mirror of the weather map and density model, evaluated on the pack's own noise textures,
with a simplified renderer: a fixed-step march (the shader's two-rate march finds the same clouds),
a sun light march with the same multiple-scattering octaves, sky ambient with the same occlusion,
constant sky colours instead of the atmosphere LUTs and a simple exposure curve. It is for judging
cloud distribution and shape and for calibrating the sky cover, not for exact colours.

    python -P tools/cloud_preview.py fisheye out.png [--coverage 0.45] [--rain 0] [--thunder 0] [--day 0]
    python -P tools/cloud_preview.py view out.png --at X,Z [--yaw 0] [--pitch 14] [--sun 28,200]
    python -P tools/cloud_preview.py map out.png [--at X,Z]          # top-down optical depth, 30 km
"""

import math
import os
import struct
import sys
import time
import zlib

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "tests"))
from test_cloud_weather import TEX as NOISE2D  # noqa: E402  (PNG decoder lives there)

WRAP = 131072.0
PLANET_R = 6360e3
SHAPE = np.fromfile(os.path.join(ROOT, "shaders/textures/clouds/cloud_shape.bin"), np.uint8).reshape(128, 128, 128, 4).astype(np.float32) / 255
DETAIL = np.fromfile(os.path.join(ROOT, "shaders/textures/clouds/cloud_detail.bin"), np.uint8).reshape(32, 32, 32, 4).astype(np.float32) / 255
NOISE2D = NOISE2D.astype(np.float32)

CLOUD_BASE = 1400.0
STRATUS_BASE = max(CLOUD_BASE * 0.55, 450.0)
SHELL_BASE = min(STRATUS_BASE, CLOUD_BASE - 250.0)
TOP_LOW = CLOUD_BASE + 2600.0
TOP_STORM = 9000.0
ANVIL_BASE = 7000.0
SHAPE_TILE, SHAPE_TILE_S, SHAPE_TILE_2 = WRAP / 32, WRAP / 64, WRAP / 23
FINE_TILE, DETAIL_TILE = WRAP / 128, WRAP / 256
STRETCH = np.array([1.0, 0.65, 1.0])
CELL = 0.65                     # share of the cellular (inverted Worley) channel in the shape


class Env:
    """Settings and weather uniforms (defaults: CLOUD_COVERAGE 0.45, clear)."""
    def __init__(self, coverage=0.45, rain=0.0, thunder=0.0, day=0.0, wind=(1.0, 0.0), wind_strength=0.3):
        self.cov, self.rain, self.thunder, self.day = coverage, rain, thunder, day
        self.wind, self.windS = np.array(wind), wind_strength


# ---------------------------------------------------------------- texture sampling (GL_REPEAT, linear)
def tex3(T, uvw):
    n = T.shape[0]
    p = uvw * n - 0.5
    i = np.floor(p).astype(np.int64)
    f = (p - i).astype(np.float32)
    x0, y0, z0 = i[..., 0] % n, i[..., 1] % n, i[..., 2] % n
    x1, y1, z1 = (x0 + 1) % n, (y0 + 1) % n, (z0 + 1) % n
    fx, fy, fz = f[..., 0:1], f[..., 1:2], f[..., 2:3]
    c00 = T[z0, y0, x0] * (1 - fx) + T[z0, y0, x1] * fx
    c10 = T[z0, y1, x0] * (1 - fx) + T[z0, y1, x1] * fx
    c01 = T[z1, y0, x0] * (1 - fx) + T[z1, y0, x1] * fx
    c11 = T[z1, y1, x0] * (1 - fx) + T[z1, y1, x1] * fx
    return (c00 * (1 - fy) + c10 * fy) * (1 - fz) + (c01 * (1 - fy) + c11 * fy) * fz


def tex2(uv):
    n = NOISE2D.shape[0]
    p = uv * n - 0.5
    i = np.floor(p).astype(np.int64)
    f = (p - i).astype(np.float32)
    x0, y0 = i[..., 0] % n, i[..., 1] % n
    x1, y1 = (x0 + 1) % n, (y0 + 1) % n
    fx, fy = f[..., 0:1], f[..., 1:2]
    T = NOISE2D
    return (T[y0, x0] * (1 - fx) + T[y0, x1] * fx) * (1 - fy) + (T[y1, x0] * (1 - fx) + T[y1, x1] * fx) * fy


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def sat(x):
    return np.clip(x, 0.0, 1.0)


def mix(a, b, t):
    return a + (b - a) * t


def wn(p, tiles):
    return tex2(p * (tiles / WRAP))


# ---------------------------------------------------------------- weather map (cloudWeatherAt)
def systems_from(a, b):
    return ss(0.1, 0.9, ss(0.236, 0.799, a[..., 0] * 0.8 + b[..., 2] * 0.2))


def weather(xz, E):
    """Mirror of cloudWeatherAt (weatherOffset 0). Returns a dict of per-column arrays."""
    p = xz
    a, b = wn(p, 1.0), wn(p + 7919.0, 3.0)
    systems = systems_from(a, b)
    warp = (np.stack([a[..., 1], b[..., 1]], -1) - 0.5) * 2600.0
    c = wn(p + warp, 11.0)
    d = wn(p + warp * 0.5 + 3313.0, 5.0)
    cluster = ss(0.328, 0.748, d[..., 1] * 0.55 + c[..., 1] * 0.30 + c[..., 3] * 0.15)
    conv = ss(0.226, 0.854, d[..., 2])
    swing = min(0.9, 2.0 * min(E.cov, 1 - E.cov))
    target = sat(E.cov + (systems - 0.5) * swing + E.day + E.rain * 0.5 + E.thunder * 0.2)
    t = mix(0.34, 0.62, 1 - ss(0.35, 0.8, systems))
    t = np.clip(t + (conv - 0.5) * 0.35, 0.2, 0.8)
    t = mix(t, 0.1, ss(0.8, 0.95, target) * ss(0.85, 1, systems) * ss(0.55, 0.8, 1 - conv))
    t = mix(t, 0.08, E.rain * (1 - E.thunder) * 0.8)
    t = mix(t, 1.0, E.thunder * ss(0.55, 0.8, conv))
    stratus = 1 - ss(0.1, 0.3, t)
    cu = ss(0.35, 0.62, t)
    cb = ss(0.82, 1.0, t)
    size = sat(0.65 * conv + 0.35 * ss(0.3, 0.7, c[..., 0]))
    base = mix(CLOUD_BASE + (conv - 0.5) * 400, STRATUS_BASE, stratus)
    thick = mix(450.0, 800.0, ss(0.08, 0.35, t))
    thick = mix(thick, 350 + 2200 * size * np.sqrt(size), cu)
    thick = mix(thick, TOP_STORM - base, cb)
    top = np.minimum(base + thick, mix(TOP_LOW, TOP_STORM, E.thunder))
    in_group = 0.2 + 0.75 * target
    share = np.minimum(target / in_group, 1.0)
    group = ss(1 - share - 0.12, 1 - share + 0.12, cluster)
    n = mix(1.3, 1.0 + 1.25e-3 * (top - base), cu)
    cov = (1 - (1 - np.minimum(in_group, 0.995)) ** (1 / n)) * group
    cov = np.maximum(cov, E.rain * (0.85 + 0.15 * ss(0.2, 0.7, c[..., 2])))
    dens = mix(0.75, 1.15, conv) * mix(0.85, 1.15, c[..., 2])
    dens = mix(dens, 0.6, stratus) * (1 + 0.5 * E.rain) * mix(1.0, 1.6, cb)
    anvil = np.zeros_like(cov)
    if E.thunder > 0:
        up = wn(p + warp * 0.5 + 3313.0 - E.wind * 3000.0, 5.0)[..., 2]
        anvil = E.thunder * ss(0.35, 0.65, ss(0.226, 0.854, np.maximum(up, d[..., 2])))
    return dict(coverage=cov, type=t, base=base, top=top, density=dens, size=size, anvil=anvil,
                target=target, sky_cover=in_group * group, systems=systems)


# ---------------------------------------------------------------- density (cloudDensity)
def coverage_profile(h01, t):
    cu = ss(0.35, 0.62, t); st = 1 - ss(0.1, 0.3, t); cb = ss(0.82, 1.0, t)
    bottom = ss(0.0, mix(mix(0.15, 0.06, cu), 0.25, st), h01)
    t0 = mix(mix(mix(0.55, 0.2, cu), 0.6, st), 0.8, cb)
    top = 1 - ss(t0, 1.0, h01)
    return bottom * top ** mix(1.0, 0.7, cu)


def equalise(x, mean, sd):
    return ss(mean - 2 * sd, mean + 2 * sd, x)


def density(wp, w, lod, E, footprint=None):
    alt = wp[..., 1] - 62.0
    t = w["type"]
    p = wp.copy()
    p[..., [0, 2]] -= E.wind * ((alt - w["base"]) * (0.06 + 0.12 * E.windS))[..., None]
    anvil = np.zeros(alt.shape)
    am = (w["anvil"] > 0.01) & (alt > ANVIL_BASE) & (alt < TOP_STORM)
    if am.any():
        a01 = (alt - ANVIL_BASE) / (TOP_STORM - ANVIL_BASE)
        prof = ss(0.0, 0.35, a01) * (1 - ss(0.6, 1.0, a01))
        nn = tex3(SHAPE, p / SHAPE_TILE_2 * np.array([1.0, 2.5, 1.0]))[..., 1]
        anvil = np.where(am, sat((nn * prof - (1 - w["anvil"] * 0.85)) / (w["anvil"] * 0.85 + 1e-9)) * 0.6, 0.0)
    h01 = (alt - w["base"]) / (w["top"] - w["base"])
    covH = w["coverage"] * coverage_profile(np.clip(h01, 0, 1), t)
    inside = (h01 > 0) & (h01 < 1) & (w["coverage"] > 0.01) & (covH > 0.005)
    sL = tex3(SHAPE, p / SHAPE_TILE * STRETCH)
    pw = mix(sL[..., 0], sL[..., 1], CELL)
    worley = 0.5
    if lod > 0:
        sS = tex3(SHAPE, (p + np.array([517.0, 0.0, 1291.0])) / SHAPE_TILE_S * STRETCH)
        size = w["size"]
        pw = (mix(mix(sS[..., 0], sS[..., 1], CELL), pw, size) - 0.514) / np.sqrt(size ** 2 + (1 - size) ** 2) + 0.514
        f = tex3(SHAPE, (p + np.array([1733.0, 911.0, -2437.0])) / SHAPE_TILE_2 * np.array([1.0, 0.8, 1.0]))
        worley = f[..., 1] * 0.625 + f[..., 2] * 0.25 + f[..., 3] * 0.125
    u = equalise(pw - (1 - worley) * 0.3, 0.362, 0.15)
    sc = sat(1 - abs(t - 0.35) / 0.2)
    st = 1 - ss(0.1, 0.3, t)
    u = mix(u, equalise(worley, 0.5, 0.14), 0.5 * sc)
    u = mix(u, 0.7 + 0.3 * u, st)
    d = np.where(inside, sat((u - (1 - covH)) * 5.0), 0.0)
    if lod >= 2:
        dn = tex3(DETAIL, p / DETAIL_TILE)
        df = dn[..., 0] * 0.625 + dn[..., 1] * 0.25 + dn[..., 2] * 0.125
        fs = tex3(SHAPE, p / FINE_TILE)
        fine = 1 - ss(8.0, 30.0, footprint) if footprint is not None else 1.0
        ff = mix(0.5, fs[..., 2] * 0.5 + fs[..., 3] * 0.5, fine)
        ero = df * 0.6 + (1 - ff) * 0.4
        ero = mix(ero, 1 - ero, sat(h01 * 3 - 1.2) * (1 - st))
        lo = ero * mix(0.45, 0.25, st)
        d = np.where(d > 0, sat((d - lo) / (1 - lo)), 0.0)
    d = d * w["density"] * mix(1.0, mix(0.6, 1.0, sat(h01 * 2)), ss(0.35, 0.62, t))
    return np.maximum(d, anvil)


def extinction(d):
    return d * 0.04


def column_optical_depth(xz, E, lod=1, nh=28):
    """Vertical optical depth through each column (what the cloud shadow map integrates)."""
    w = weather(xz, E)
    od = np.zeros(len(xz))
    for i in range(nh):
        h = w["base"] + (i + 0.5) / nh * (w["top"] - w["base"])
        od += extinction(density(np.stack([xz[:, 0], h + 62, xz[:, 1]], -1), w, lod, E)) * (w["top"] - w["base"]) / nh
    if E.thunder > 0:
        for i in range(6):
            h = ANVIL_BASE + (i + 0.5) / 6 * (TOP_STORM - ANVIL_BASE)
            hv = np.full(len(xz), h)
            dd = density(np.stack([xz[:, 0], hv + 62, xz[:, 1]], -1), w, lod, E)
            od += np.where(hv >= w["top"], extinction(dd) * (TOP_STORM - ANVIL_BASE) / 6, 0.0)
    return od, w


# ---------------------------------------------------------------- renderer
def phase_hg(c, g):
    return (1 - g * g) / (4 * math.pi * np.power(1 + g * g - 2 * g * c, 1.5))


def octaves(od, c):
    s = np.zeros_like(od)
    a = b = cc = 1.0
    build = 1 - 0.6 * np.exp(-od * 1.5)
    for i in range(4):
        ph = mix(phase_hg(c, -0.2 * cc), phase_hg(c, 0.82 * cc), 0.62)
        s = s + a * ph * np.exp(-b * od) * (1.0 if i == 0 else build)
        a *= 0.6; b *= 0.32; cc *= 0.55
    return s * 2.0


def ray_sphere(ro, d, r):
    b = (ro * d).sum(-1)
    disc = b * b - ((ro * ro).sum(-1) - r * r)
    s = np.sqrt(np.maximum(disc, 0))
    return np.where(disc < 0, -1.0, -b - s), np.where(disc < 0, -1.0, -b + s)


def sky_colour(d):
    y = np.clip(d[..., 1], 0, 1)[..., None]
    hor = np.array([0.62, 0.72, 0.85]) * 0.085
    zen = np.array([0.16, 0.30, 0.68]) * 0.07
    return hor + (zen - hor) * (1 - (1 - y) ** 4)


def render(E, cam=(0.0, 70.0, 0.0), yaw=0.0, pitch=14.0, fov=75.0, W=320, H=180, sun=(30.0, 35.0),
           steps=160, light_steps=5, fisheye=False, seed=1):
    """Returns (rgb image in 0..1, cloud opacity per pixel)."""
    if fisheye:
        u = (np.arange(W) + 0.5) / W * 2 - 1
        U, V = np.meshgrid(u, -((np.arange(H) + 0.5) / H * 2 - 1))
        r = np.sqrt(U * U + V * V); th = r * math.pi / 2; ph = np.arctan2(V, U)
        d = np.stack([np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)], -1)
        valid = r <= 1
        pix = math.pi / W
    else:
        a = math.tan(math.radians(fov) / 2)
        U, V = np.meshgrid(((np.arange(W) + 0.5) / W * 2 - 1) * a, -((np.arange(H) + 0.5) / H * 2 - 1) * a * H / W)
        cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        fwd = np.array([sy * cp, sp, cy * cp]); right = np.array([cy, 0, -sy]); up = np.cross(fwd, right)
        up = -up if up[1] < 0 else up
        d = fwd + U[..., None] * right + V[..., None] * up
        d /= np.linalg.norm(d, axis=-1, keepdims=True)
        valid = np.ones((H, W), bool)
        pix = math.radians(fov) / W
    d = d.reshape(-1, 3); valid = valid.ravel()
    el, az = math.radians(sun[0]), math.radians(sun[1])
    L = np.array([math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az)])
    warm = ss(-0.02, 0.25, math.sin(el))
    eSun = np.array([1.0, 0.95, 0.86]) * mix(np.array([1.0, 0.45, 0.15]), np.ones(3), warm) * mix(0.25, 1.0, warm)
    ambTop = np.array([0.13, 0.18, 0.28]) * mix(0.3, 1.0, warm) * (1 - 0.6 * E.rain)
    ambBottom = ambTop * 0.15 + 0.03 * eSun * max(math.sin(el), 0)
    ro = np.array([0.0, PLANET_R + cam[1] - 62, 0.0])
    top_shell = mix(TOP_LOW, TOP_STORM, E.thunder)
    _, tb1 = ray_sphere(ro, d, PLANET_R + SHELL_BASE)
    _, tt1 = ray_sphere(ro, d, PLANET_R + top_shell)
    tp0, _ = ray_sphere(ro, d, PLANET_R)
    ok = valid & (tb1 > 0) & ~(tp0 > 0)
    t0 = np.where(ok, tb1, 0.0)
    t1 = np.where(ok, np.minimum(tt1, t0 + 30000.0), 0.0)
    jit = np.random.default_rng(seed).random(len(d))
    T = np.ones((len(d), 3)); S = np.zeros((len(d), 3)); dsum = np.zeros(len(d)); dw = np.zeros(len(d))
    cosS = d @ L
    dt = (t1 - t0) / steps
    for i in range(steps):
        idx = np.nonzero(ok & (T[:, 1] > 0.01))[0]
        if len(idx) == 0:
            break
        t = t0[idx] + (i + jit[idx]) * dt[idx]
        dd = d[idx]
        h = np.linalg.norm(ro + dd * t[:, None], axis=-1) - PLANET_R
        wp = np.stack([cam[0] + dd[:, 0] * t, h + 62, cam[2] + dd[:, 2] * t], -1)
        w = weather(wp[:, [0, 2]], E)
        den = density(wp, w, 2, E, t * pix)
        m = den > 0
        if not m.any():
            continue
        j = idx[m]; wpm = wp[m]; wm = {k: v[m] for k, v in w.items()}; hm = h[m]; tm = t[m]
        sig = extinction(den[m])
        od = np.zeros(len(j)); q = wpm.copy(); st = 60.0; wq = wm
        for k in range(light_steps):
            q = q + L * st
            if k >= 3:
                wq = weather(q[:, [0, 2]], E)
            od += extinction(density(q, wq, 1, E)) * st
            st *= 1.6
        light = eSun * octaves(od, cosS[j])[:, None]
        h01 = sat((hm - wm["base"]) / (wm["top"] - wm["base"]))
        ao = np.maximum(np.exp(-2.55e-4 * (wm["top"] - hm) * np.sqrt(wm["coverage"]) * wm["density"]), 0.1)
        amb = (ambTop * mix(ao, 1.0, h01 * h01)[:, None] + ambBottom * mix(1.0, 0.3, h01)[:, None]) / (2 * math.pi)
        stepT = np.exp(-sig * dt[j])
        S[j] += T[j] * (light + amb) * (1 - stepT)[:, None]      # integral of S exp(-sigma s) over the step
        ab = T[j, 1] * (1 - stepT)
        dsum[j] += tm * ab; dw[j] += ab
        T[j] *= stepT[:, None]
    dist = np.where(dw > 1e-4, dsum / np.maximum(dw, 1e-9), 1e6)
    airT = np.exp(-dist / 42000.0)[:, None]
    haze = sky_colour(np.stack([d[:, 0], np.maximum(d[:, 1], 0.03), d[:, 2]], -1))
    haze = mix(haze, haze.mean(-1, keepdims=True) * 0.7, E.rain * 0.9)
    col = sky_colour(d) * mix(1.0, 0.45, E.rain) * T + S * airT + haze * (1 - T) * (1 - airT)
    col[(d[:, 1] < 0) & valid] = [0.03, 0.05, 0.02]
    col[~valid] = 0
    img = (1 - np.exp(-col * 6.0)) ** (1 / 2.2)
    return img.reshape(H, W, 3), (1 - T[:, 1]).reshape(H, W) * valid.reshape(H, W)


def write_png(path, img):
    a = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
    if a.ndim == 2:
        a = np.stack([a] * 3, -1)
    h, w, _ = a.shape
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))
    def chunk(k, data):
        return struct.pack(">I", len(data)) + k + data + struct.pack(">I", zlib.crc32(k + data) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


FISHEYE_SITES = [(5000, 3000), (-21000, 40000), (47000, -12000), (90000, 70000),
                 (15000, -60000), (-50000, -30000), (30000, 25000), (-8000, -90000)]


def main(argv):
    def opt(name, default):
        return argv[argv.index(name) + 1] if name in argv else default
    mode, out = argv[0], argv[1]
    E = Env(float(opt("--coverage", 0.45)), float(opt("--rain", 0)), float(opt("--thunder", 0)), float(opt("--day", 0)))
    sun = tuple(float(x) for x in opt("--sun", "28,200").split(","))
    t0 = time.time()
    if mode == "fisheye":
        ims = [render(E, cam=(x, 70.0, z), fisheye=True, W=140, H=140, steps=110, light_steps=4, sun=sun)[0] for x, z in FISHEYE_SITES]
        write_png(out, np.concatenate([np.concatenate(ims[:4], 1), np.concatenate(ims[4:], 1)], 0))
    elif mode == "view":
        x, z = (float(v) for v in opt("--at", "5000,3000").split(","))
        img, _ = render(E, cam=(x, 70.0, z), yaw=float(opt("--yaw", 0)), pitch=float(opt("--pitch", 14)),
                        W=480, H=270, steps=220, sun=sun)
        write_png(out, img)
    elif mode == "map":
        x, z = (float(v) for v in opt("--at", "0,0").split(","))
        res, ext = 300, 30000.0
        g = (np.arange(res) + 0.5) / res * ext
        X, Z = np.meshgrid(g + x, g + z)
        od, _ = column_optical_depth(np.stack([X.ravel(), Z.ravel()], -1), E)
        T = np.exp(-od.reshape(res, res))[..., None]
        write_png(out, (1 - T) * 0.95 + T * np.array([0.25, 0.42, 0.75]))
        print(f"sky cover (vertical optical depth > 1): {np.mean(od > 1.0):.2f}")
    print(f"{out} written in {time.time() - t0:.0f} s")


if __name__ == "__main__":
    main(sys.argv[1:])

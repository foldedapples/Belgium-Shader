"""Reference test for the cloud weather map (lib/clouds/clouds_common.glsl, cloudWeatherAt).

Evaluates the old and new weather maps on the real noise texture (textures/noise2d.png) over a
262 x 262 km area and checks that
1. the average coverage follows CLOUD_COVERAGE;
2. the sky varies: seen from different places (15 km wide views) it ranges from almost clear to
   overcast, where the old map gave nearly the same partly cloudy sky everywhere;
3. the pattern does not repeat at the texture tiles (the old map repeated every 32.8 km);
4. it is seamless where the wind offsets wrap (131072 m);
5. cloud types and heights vary across the sky.

    python -P tools/tests/test_cloud_weather.py [--png out_dir]   # optionally writes coverage maps
"""

import os
import re
import struct
import sys
import zlib

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WRAP = 131072.0


def read_png_rgba8(path):
    data = open(path, "rb").read()
    pos, w, h, idat = 8, 0, 0, b""
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, depth, colour = struct.unpack(">IIBB", chunk[:10])
            assert depth == 8 and colour == 6
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + n
    raw = np.frombuffer(zlib.decompress(idat), np.uint8).reshape(h, 1 + 4 * w)
    out = np.zeros((h, 4 * w), np.int32)
    for y in range(h):
        f, line = raw[y, 0], raw[y, 1:].astype(np.int32)
        prev = out[y - 1] if y else np.zeros(4 * w, np.int32)
        if f == 0:
            out[y] = line
        elif f == 2:
            out[y] = (line + prev) & 255
        else:
            cur = np.zeros(4 * w, np.int32)
            for x in range(4 * w):
                a = cur[x - 4] if x >= 4 else 0
                b = prev[x]
                c = prev[x - 4] if x >= 4 else 0
                if f == 1:
                    p = a
                elif f == 3:
                    p = (a + b) // 2
                else:
                    pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                    p = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                cur[x] = (line[x] + p) & 255
            out[y] = cur
    return out.reshape(h, w, 4).astype(np.float64) / 255.0


TEX = read_png_rgba8(os.path.join(ROOT, "shaders", "textures", "noise2d.png"))
N = TEX.shape[0]
SETTINGS = open(os.path.join(ROOT, "shaders", "lib", "settings.glsl"), encoding="utf-8").read()
COMMON = open(os.path.join(ROOT, "shaders", "lib", "clouds", "clouds_common.glsl"), encoding="utf-8").read()
CLOUD_BASE = float(re.search(r"#define CLOUD_ALTITUDE (\d+)", SETTINGS).group(1))


def tex(uv):
    """Bilinear, repeating texture(noise2dTex, uv) for uv of shape (..., 2)."""
    p = uv * N - 0.5
    i = np.floor(p).astype(np.int64)
    f = p - i
    x0, y0 = i[..., 0] % N, i[..., 1] % N
    x1, y1 = (x0 + 1) % N, (y0 + 1) % N
    fx, fy = f[..., 0:1], f[..., 1:2]
    a, b, c, d = TEX[y0, x0], TEX[y0, x1], TEX[y1, x0], TEX[y1, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def wn(p, tiles):
    return tex(p * (tiles / WRAP))


def old_coverage(p, cov):
    n = tex(p / 32768.0)
    n2 = tex(p / 32768.0 * 4.0 + 0.37)
    base = n[..., 0] * 0.65 + n2[..., 0] * 0.35
    return np.clip((base - (1.0 - cov - 0.25)) / 0.6, 0.0, 1.0)


def new_weather(p, cov, weather_systems=True, thunder=0.0):
    """Mirror of cloudWeatherAt (rain 0) -> coverage, type, base, share of the area in cloud groups."""
    a, b = wn(p, 1.0), wn(p + 7919.0, 3.0)
    systems = smoothstep(0.1, 0.9, smoothstep(0.236, 0.799, a[..., 0] * 0.8 + b[..., 2] * 0.2)) if weather_systems else 0.5
    warp = (np.stack([a[..., 1], b[..., 1]], -1) - 0.5) * 2600.0
    c = wn(p + warp, 11.0)
    d = wn(p + warp * 0.5 + 3313.0, 5.0)
    cluster = smoothstep(0.328, 0.748, d[..., 1] * 0.55 + c[..., 1] * 0.30 + c[..., 3] * 0.15)
    convective = smoothstep(0.226, 0.854, d[..., 2])
    swing = min(1.125, 2.25 * min(cov, 1.0 - cov))
    target = np.clip(cov + (systems - 0.5) * swing + thunder * 0.2, 0.0, 1.0)
    share = smoothstep(1.0 - target - 0.18, 1.0 - target + 0.18, cluster)    # inside a cloud group
    covr = share * (0.4 + 0.45 * target)
    t = 0.34 + (0.62 - 0.34) * (1.0 - smoothstep(0.35, 0.8, systems))
    t = np.clip(t + (convective - 0.5) * 0.35, 0.2, 0.8)
    t = t + (0.1 - t) * smoothstep(0.85, 1.0, systems) * smoothstep(0.6, 0.9, target) * smoothstep(0.55, 0.8, 1.0 - convective)
    t = t + (1.0 - t) * thunder * smoothstep(0.55, 0.8, convective)
    stratus = 1.0 - smoothstep(0.1, 0.3, t)
    base = (CLOUD_BASE + (convective - 0.5) * 400.0) * (1 - stratus) + max(CLOUD_BASE * 0.55, 450.0) * stratus
    return covr, t, base, share


def grid(extent, step, origin=(0.0, 0.0)):
    x = np.arange(0.0, extent, step) + origin[0]
    y = np.arange(0.0, extent, step) + origin[1]
    X, Y = np.meshgrid(x, y)
    return np.stack([X, Y], -1)


def views(cov_map, step, view=15000.0):
    """Mean coverage over non-overlapping square views of `view` metres (what one sky shows)."""
    k = int(view / step)
    h = (cov_map.shape[0] // k) * k
    m = cov_map[:h, :h].reshape(h // k, k, h // k, k).mean(axis=(1, 3))
    return m.ravel()


def test_constants_match_shader():
    for s in ("weatherNoise(p + 7919.0, 3.0)", "weatherNoise(p + warp, 11.0)",
              "weatherNoise(p + warp * 0.5 + 3313.0, 5.0)", "smoothstep(0.328, 0.748, d.g * 0.55 + c.g * 0.30 + c.a * 0.15)",
              "(systems - 0.5) * SWING", "min(1.125, 2.25 * min(CLOUD_COVERAGE, 1.0 - CLOUD_COVERAGE))",
              "smoothstep(0.1, 0.9, smoothstep(0.236, 0.799, a.r * 0.8 + b.b * 0.2))", "weatherNoise(p, 1.0)", "smoothstep(1.0 - target - 0.18, 1.0 - target + 0.18, cluster)", "mix(0.4, 0.85, target)"):
        assert s in COMMON, s
    print("constants: the model matches lib/clouds/clouds_common.glsl")


P = grid(393216.0, 384.0)            # three wraps: the systems tile is the whole wrap


def test_coverage_and_variety():
    rows = []
    for cov in (0.2, 0.45, 0.7):
        new = new_weather(P, cov)[3]
        old = old_coverage(P, cov)
        vn, vo = views(new, 384.0), views(old, 384.0)
        rows.append((cov, new.mean(), vn, vo))
    cov, mean45, vn, vo = rows[1]
    clear_new, over_new = (vn < 0.1).mean(), (vn > 0.75).mean()
    clear_old, over_old = (vo < 0.1).mean(), (vo > 0.75).mean()
    assert all(abs(m - c) < 0.08 for c, m, _, _ in rows), [(c, m) for c, m, _, _ in rows]
    assert vn.std() > 2.0 * vo.std(), (vn.std(), vo.std())
    assert clear_new > 0.08 and over_new > 0.1, (clear_new, over_new)
    print("coverage: mean share of sky inside cloud groups for Coverage 0.2 / 0.45 / 0.7: "
          + " / ".join(f"{m:.2f}" for _, m, _, _ in rows))
    print(f"variety (Coverage 0.45, 15 km views): spread {vn.std():.2f} (old {vo.std():.2f}); "
          f"almost clear {100 * clear_new:.0f} % (old {100 * clear_old:.0f} %), "
          f"overcast {100 * over_new:.0f} % (old {100 * over_old:.0f} %)")


def autocorr(field, lag_px):
    a = field - field.mean()
    return float((a * np.roll(a, lag_px, axis=1)).mean() / (a * a).mean())


def repetition_peak(field, step, tile):
    """Correlation of the map with itself shifted by one texture tile, minus that at nearby
    shifts: ~0 when nothing repeats at the tile, ~1 for a pattern that visibly repeats."""
    at = autocorr(field, int(round(tile / step)))
    near = 0.5 * (autocorr(field, int(round(0.85 * tile / step))) + autocorr(field, int(round(1.15 * tile / step))))
    return at - near


def test_no_tile_repetition():
    step = 384.0
    new = new_weather(P, 0.45)[0]
    old = old_coverage(P, 0.45)
    pn = max(repetition_peak(new, step, WRAP / k) for k in (3.0, 5.0, 11.0))
    po = max(repetition_peak(old, step, t) for t in (32768.0, 8192.0))
    assert po > 0.5 and pn < 0.15, (po, pn)
    print(f"repetition: correlation peak at the texture tile periods: new {pn:.2f}, old {po:.2f} "
          "(the old map repeated every 32.8 km)")


def test_seamless_at_wrap():
    p = grid(20000.0, 97.0, (-10000.0, -10000.0))
    for shift in ((WRAP, 0.0), (0.0, WRAP), (WRAP, -WRAP)):
        a = new_weather(p, 0.45)
        b = new_weather(p + np.array(shift), 0.45)
        err = max(float(np.abs(x - y).max()) for x, y in zip(a, b))
        assert err < 2e-6, (shift, err)
    print("wrap: identical after shifting by the 131072 m offset wrap (no jump when the offsets wrap)")


def test_types_and_heights():
    covr, t, base, _ = new_weather(P, 0.45)
    cloudy = covr > 0.2
    tc, bc = t[cloudy], base[cloudy]
    stratus, sc, cu = (tc < 0.2).mean(), ((tc >= 0.2) & (tc < 0.48)).mean(), (tc >= 0.48).mean()
    assert 0.03 < stratus < 0.3 and sc > 0.3 and cu > 0.2, (stratus, sc, cu)
    assert bc.max() - bc.min() > 300.0
    tt = new_weather(P, 0.45, thunder=1.0)[1]
    cb = (tt > 0.9).mean()
    assert 0.03 < cb < 0.5, cb
    print(f"types in fair weather: stratus {100 * stratus:.0f} %, stratocumulus {100 * sc:.0f} %, cumulus "
          f"{100 * cu:.0f} %; bases {bc.min():.0f}-{bc.max():.0f} m; thunderstorm: cumulonimbus cells over "
          f"{100 * cb:.0f} % of the area")


def write_maps(out):
    import zlib as z

    def png(path, img):
        h, w = img.shape
        rows = b"".join(b"\x00" + bytes(np.clip(r * 255, 0, 255).astype(np.uint8)) for r in img)
        def chunk(k, d):
            return struct.pack(">I", len(d)) + k + d + struct.pack(">I", z.crc32(k + d) & 0xffffffff)
        open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
                               + chunk(b"IDAT", z.compress(rows)) + chunk(b"IEND", b""))
    p = grid(98304.0, 128.0)
    png(os.path.join(out, "weather_old.png"), old_coverage(p, 0.45))
    png(os.path.join(out, "weather_new.png"), new_weather(p, 0.45)[0])
    print("maps (98 km wide, Coverage 0.45) written to", out)


if __name__ == "__main__":
    test_constants_match_shader()
    test_coverage_and_variety()
    test_no_tile_repetition()
    test_seamless_at_wrap()
    test_types_and_heights()
    if "--png" in sys.argv:
        write_maps(sys.argv[sys.argv.index("--png") + 1])
    print("OK")

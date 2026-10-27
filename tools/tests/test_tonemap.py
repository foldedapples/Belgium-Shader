"""Reference test for the display transform and colour grading (lib/post/tonemap.glsl, oklab.glsl,
grading.glsl), the new default (Belgium filmic) against the previous one (Meridian filmic).

Mirrors the GLSL (curve constants read from the source) and checks, on a chart of Minecraft block
colours lit by sun and sky at a typical daylight exposure:
1. middle grey stays at ~0.18, the curve rises monotonically and reaches white at ~16x middle grey;
2. mid-tone contrast is film-like (log-log slope ~1.28; the old curve had 1.0, which is why the
   image looked flat and grey) and shadows are not lifted (1/8 grey 0.0104 instead of 0.0174);
3. hues stay put (Oklab hue shift from scene to display);
4. colours are richer but grass stays natural (Oklab chroma well below neon);
5. bright coloured light (lava, fire) keeps its colour until far beyond white;
6. black, huge and single-channel inputs give finite values in range.

    python -P tools/tests/test_tonemap.py
"""

import math
import os
import re

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TONEMAP = open(os.path.join(ROOT, "shaders", "lib", "post", "tonemap.glsl"), encoding="utf-8").read()
GRADING = open(os.path.join(ROOT, "shaders", "lib", "post", "grading.glsl"), encoding="utf-8").read()
FC, FS, FQ, FCHROMA = (float(re.search(rf"const float FILMIC_{k} = ([\d.]+);", TONEMAP).group(1)) for k in ("C", "S", "Q", "CHROMA"))
LUMA = np.array([0.2126, 0.7152, 0.0722])


def ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def lum(c):
    return c @ LUMA


# ---- Oklab
M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
M2I = np.array([[1.0, 0.3963377774, 0.2158037573], [1.0, -0.1055613458, -0.0638541728], [1.0, -0.0894841775, -1.2914855480]])
M1I = np.array([[4.0767416621, -3.3077115913, 0.2309699292], [-1.2684380046, 2.6097574011, -0.3413193965], [-0.0041960863, -0.7034186147, 1.7076147010]])


def to_oklab(c):
    return np.cbrt(c @ M1.T) @ M2.T


def from_oklab(lab):
    return ((lab @ M2I.T) ** 3) @ M1I.T


def oklab_to_display(lab):
    L, ab = lab[..., :1], lab[..., 1:]
    lo, hi = np.zeros(L.shape), np.ones(L.shape)
    for _ in range(10):
        mid = 0.5 * (lo + hi)
        c = from_oklab(np.concatenate([L, ab * mid], -1))
        ok = np.all((c >= -1e-4) & (c <= 1.0001), -1, keepdims=True)
        lo, hi = np.where(ok, mid, lo), np.where(ok, hi, mid)
    r = 1.0 / np.maximum(lo, 1e-4)
    rc = np.where(r < 0.8, r, 0.8 + 0.2 * np.tanh((r - 0.8) / 0.2))
    return np.clip(from_oklab(np.concatenate([L, ab * (rc / r)], -1)), 0, 1)


# ---- Belgium filmic (new default)
SC, WC = FS ** FC, 2.88 ** FC
N = 0.985 / (WC / (WC + SC)) ** FQ


def filmic_curve(x):
    xc = np.maximum(x, 0) ** FC
    return np.minimum(N * (xc / (xc + SC)) ** FQ, 1.0)


def belgium(x):
    x = np.maximum(x, 0)
    n = np.maximum(x.max(-1, keepdims=True), 1e-10)
    y = filmic_curve(n)
    c = x * (y / n)
    w = ss(0.0, 2.5, np.log2(n / 1.44))
    c = c + (y - c) * w
    lab = to_oklab(c)
    e = np.log2(n / 0.18) + 0.5
    lab[..., 1:] *= 1 + FCHROMA * np.exp(-e * e / 9.0) * (1 - w)
    return np.where(x.max(-1, keepdims=True) <= 1e-10, 0.0, oklab_to_display(lab))


# ---- Meridian filmic (previous default) and the previous Realistic grading
def meridian_curve(x):
    xc = np.maximum(x, 0) ** 1.25
    return (xc / (xc + 0.49983)) / (32.0 / 32.49983)


def meridian(x):
    x = np.maximum(x, 0)
    n = np.maximum(x.max(-1, keepdims=True), 1e-8)
    y = np.minimum(meridian_curve(n), 1.0)
    c = x * (y / n)
    s = ss(0.6, 1.0, y)
    return np.clip(c + (y - c) * (s * s * 0.9), 0, 1)


def contrast(c, k):
    p = np.sqrt(np.clip(c, 0, 1))
    p = p + (k - 1) * (p - 0.45) * (4 * p * (1 - p))
    return p * p


def old_realistic(x):
    l = lum(x)[..., None]
    c = meridian(np.maximum(l + (x - l) * 0.98, 0))
    c = contrast(c, 1.04)
    mx, mn = c.max(-1, keepdims=True), c.min(-1, keepdims=True)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
    l = lum(c)[..., None]
    c = l + (c - l) * (1 + 0.08 * (1 - sat) ** 2)
    return np.clip(c + np.array([-0.004, 0, 0.006]) * (1 - ss(0, 0.4, l)), 0, 1)


PROFILES = {"Vibrant": (1.03, 0.15, 1.03), "Realistic": (1.0, 0.06, 1.0)}


def graded(x, profile):
    sat, vib, con = PROFILES[profile]
    l = lum(x)[..., None]
    c = belgium(np.maximum(l + (x - l) * sat, 0))
    c = contrast(c, con)
    lab = to_oklab(c)
    chroma = np.hypot(lab[..., 1], lab[..., 2])[..., None]
    hue = np.degrees(np.arctan2(lab[..., 2], lab[..., 1]))[..., None]
    foliage = np.exp(-((hue - 135.0) / 22.0) ** 2)
    boost = vib * (1 - ss(0.0, 0.18, chroma)) * (1 - 0.5 * foliage) * (1 - ss(0.85, 1.0, lab[..., :1]))
    lab[..., 1:] *= 1 + boost
    c = oklab_to_display(lab)
    if profile == "Realistic":
        c = c * (1 + 5.0 * np.array([-0.004, 0, 0.006]) * (1 - ss(0, 0.4, lum(c)[..., None])))
    return np.clip(c, 0, 1)


# ---- chart: block colours (sRGB textures) lit by sun and sky
def srgb_to_linear(s):
    s = np.asarray(s, float)
    return np.where(s <= 0.04045, s / 12.92, ((s + 0.055) / 1.055) ** 2.4)


SUN, SKY = np.array([1.0, 0.95, 0.87]) * 2.6, np.array([0.55, 0.72, 1.0]) * 0.55
BLOCKS = {"grass": [0.36, 0.60, 0.22], "leaves": [0.25, 0.45, 0.14], "sand": [0.86, 0.80, 0.60], "dirt": [0.55, 0.40, 0.27],
          "stone": [0.50, 0.50, 0.50], "red wool": [0.63, 0.16, 0.15], "blue wool": [0.21, 0.24, 0.62],
          "orange": [0.92, 0.46, 0.08], "skin": [0.80, 0.60, 0.48], "water": [0.25, 0.40, 0.75], "snow": [0.95, 0.97, 1.0]}
ALBEDO = srgb_to_linear(np.array(list(BLOCKS.values())))
EXPOSURE = 0.23 / lum(srgb_to_linear([0.46] * 3) * (SUN + SKY) / math.pi)    # sunlit 18 % grey -> 0.23
SUNLIT = ALBEDO * (SUN + SKY) / math.pi * EXPOSURE
SHADE = ALBEDO * SKY / math.pi * EXPOSURE


def chroma_hue(c):
    lab = to_oklab(np.maximum(c, 0))
    return np.hypot(lab[..., 1], lab[..., 2]), np.degrees(np.arctan2(lab[..., 2], lab[..., 1]))


def test_constants_match_shader():
    for s in ("const float FILMIC_C = 2.0;", "float toWhite = smoothstep(0.0, 2.5, log2(n / 1.44));",
              "lab.yz *= 1.0 + FILMIC_CHROMA * exp(-e * e / 9.0) * (1.0 - toWhite);", "const float KNEE = 0.8;",
              "return belgiumFilmic(c);"):
        assert s in TONEMAP or s in open(os.path.join(ROOT, "shaders", "lib", "post", "oklab.glsl"), encoding="utf-8").read(), s
    for s in ("g.saturation = 1.03; g.vibrance = 0.15; g.contrast = 1.03;", "g.saturation = 1.0; g.vibrance = 0.06; g.contrast = 1.0;",
              "float foliage = exp(-pow((hue - 135.0) / 22.0, 2.0));",
              "c *= 1.0 + 5.0 * (g.shadowTint * (1.0 - smoothstep(0.0, 0.4, l)) + g.highlightTint * smoothstep(0.35, 1.0, l));"):
        assert s in GRADING, s
    print("constants: the model matches lib/post/tonemap.glsl, oklab.glsl and grading.glsl")


def slope(f, x, e=1e-3):
    return float((np.log(f(x * (1 + e))) - np.log(f(x))) / np.log(1 + e))


def test_curve():
    grey = lambda v: belgium(np.array([[v, v, v]]))[0, 1]
    old = lambda v: meridian(np.array([[v, v, v]]))[0, 1]
    xs = 0.18 * 2.0 ** np.linspace(-12, 8, 400)
    ys = belgium(np.stack([xs] * 3, -1))[:, 1]
    assert np.all(np.diff(ys) >= -1e-6), "not monotonic"
    assert abs(grey(0.18) - 0.18) < 0.01 and grey(0.18 * 16) > 0.97
    s_new, s_old = slope(grey, 0.18), slope(old, 0.18)
    assert 1.2 < s_new < 1.4 and s_old < 1.05, (s_new, s_old)
    assert grey(0.18 / 8) < 0.7 * old(0.18 / 8)
    print(f"curve: middle grey -> {grey(0.18):.3f}, 16x -> {grey(2.88):.3f}; mid-tone contrast {s_new:.2f} (old {s_old:.2f}); "
          f"1/8 grey -> {grey(0.0225):.4f} (old {old(0.0225):.4f}); 4x grey -> {grey(0.72):.3f} (old {old(0.72):.3f})")


def test_hue_and_chroma():
    names = list(BLOCKS)
    worst_tm, worst = 0.0, 0.0
    for scene in (SUNLIT, SHADE):
        c_in, h_in = chroma_hue(scene)
        chromatic = c_in > 0.05
        h_tm = chroma_hue(belgium(scene))[1]
        worst_tm = max(worst_tm, float(np.abs((h_tm - h_in + 180) % 360 - 180)[c_in > 0.015].max()))
        for prof in PROFILES:
            h_out = chroma_hue(graded(scene, prof))[1]
            worst = max(worst, float(np.abs((h_out - h_in + 180) % 360 - 180)[chromatic].max()))
    assert worst_tm < 1.0 and worst < 6.0, (worst_tm, worst)
    old_c = chroma_hue(old_realistic(SUNLIT))[0]
    rows = {p: chroma_hue(graded(SUNLIT, p))[0] for p in PROFILES}
    tex_c = chroma_hue(ALBEDO)[0]
    g = names.index("grass")
    assert rows["Vibrant"][g] < 0.2 and rows["Realistic"][g] > old_c[g], (rows["Vibrant"][g], old_c[g])
    print(f"hue: largest shift scene -> display {worst_tm:.2f} degrees for the tone mapper, {worst:.1f} with grading "
          "(Realistic's cool shadow tint; sunlit and shaded chart)")
    print("chroma (Oklab) of sunlit blocks, texture / old Realistic / new Realistic / new Vibrant:")
    for n in ("grass", "leaves", "dirt", "red wool", "orange", "water"):
        i = names.index(n)
        print(f"  {n:9s} {tex_c[i]:.3f} / {old_c[i]:.3f} / {rows['Realistic'][i]:.3f} / {rows['Vibrant'][i]:.3f}")


def test_emitters():
    lava = np.array([[1.0, 0.25, 0.02]]) * 0.18 * 2.0 ** np.arange(0, 7)[:, None]
    c, _ = chroma_hue(belgium(lava))
    co, _ = chroma_hue(meridian(lava))
    # display value of the brightest channel reaches ~0.9 at +2 EV; colour must survive to +3 EV
    assert c[3] > 0.6 * c[1] and c[6] < 0.5 * c[1], c
    print("bright orange light, chroma from +0 to +6 EV over middle grey: new "
          + " ".join(f"{v:.2f}" for v in c) + " / old " + " ".join(f"{v:.2f}" for v in co))


def test_robust():
    x = np.array([[0, 0, 0], [1e-9, 0, 0], [1e5, 1e5, 1e5], [1e5, 0, 0], [0, 0, 50.0], [3, 2, 1e-7]], float)
    y = belgium(x)
    assert np.all(np.isfinite(y)) and y.min() >= 0 and y.max() <= 1, y
    assert np.all(y[0] == 0) and y[2].min() > 0.97
    print("robust: black, tiny, huge and single-channel inputs stay finite and in range")


if __name__ == "__main__":
    test_constants_match_shader()
    test_curve()
    test_hue_and_chroma()
    test_emitters()
    test_robust()
    print("OK")

"""Offline preview of the End nebula (shaders/lib/end/black_hole.glsl endNebula), a NumPy port of
the same noise, hash and shaping, rendered for a 90 degree view at the End's reference exposure
with the pack's filmic-like curve approximated by x/(1+x). Stars and galaxies are omitted.

python -P tools/tests/render_end_nebula.py <out.png> [yaw_deg pitch_deg]
Prints coverage statistics; asserts the nebula is neither empty nor covering most of the sky.
"""
import math
import sys

import numpy as np
from PIL import Image

M = np.uint32


def hashu(x):
    x = x.astype(np.uint32)
    x ^= x >> M(16); x *= M(0x7feb352d)
    x ^= x >> M(15); x *= M(0x846ca68b)
    x ^= x >> M(16)
    return x


def hashu3(x, y, z):
    return hashu(x ^ hashu(y ^ hashu(z + M(0x632be5ab))))


def hash13(c):
    c = c.astype(np.int64).astype(np.uint32)
    return (hashu3(c[..., 0], c[..., 1], c[..., 2]) >> M(8)).astype(np.float64) / 16777216.0


def value_noise(p):
    i = np.floor(p); f = p - i
    u = f * f * f * (f * (f * 6 - 15) + 10)
    c = i.astype(np.int64)
    def n(dx, dy, dz):
        return hash13(c + np.array([dx, dy, dz]))
    x00 = n(0, 0, 0) * (1 - u[..., 0]) + n(1, 0, 0) * u[..., 0]
    x10 = n(0, 1, 0) * (1 - u[..., 0]) + n(1, 1, 0) * u[..., 0]
    x01 = n(0, 0, 1) * (1 - u[..., 0]) + n(1, 0, 1) * u[..., 0]
    x11 = n(0, 1, 1) * (1 - u[..., 0]) + n(1, 1, 1) * u[..., 0]
    y0 = x00 * (1 - u[..., 1]) + x10 * u[..., 1]
    y1 = x01 * (1 - u[..., 1]) + x11 * u[..., 1]
    return y0 * (1 - u[..., 2]) + y1 * u[..., 2]


def fbm(p, octaves):
    s = 0.0; a = 0.5; norm = 0.0
    for _ in range(octaves):
        s = s + a * value_noise(p); norm += a
        p = p * 2.03 + np.array([1.7, 9.2, 3.4]); a *= 0.5
    return s / norm


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def nebula(d):
    p = d * 2.0
    warp = np.stack([fbm(p + 11.0, 2), fbm(p + 23.0, 2), fbm(p + 37.0, 2)], -1) - 0.5
    q = p + warp * 0.9
    dd = fbm(q * 1.6, 5)
    ridge = 1 - np.abs(2 * value_noise(q * 5.1) - 1)
    fil = ridge ** 4
    cloud = smooth(0.52, 0.85, dd)
    neb = cloud * (0.3 + 0.7 * fil * smooth(0.45, 0.7, dd))
    dust = smooth(0.52, 0.74, fbm(q * 3.3 + 5.0, 3)) * smooth(0.35, 0.6, dd)
    neb = neb * (1 - 0.85 * dust)
    hue = value_noise(q * 0.9 + 4.0)
    violet = np.array([0.55, 0.35, 0.85]); teal = np.array([0.25, 0.7, 0.75]); ha = np.array([0.95, 0.28, 0.35])
    c = violet + (teal - violet) * smooth(0.3, 0.7, hue)[..., None]
    c = c + (ha - c) * (smooth(0.62, 0.9, dd) * 0.5)[..., None]
    return c * neb[..., None] * 0.02, neb


def main():
    out = sys.argv[1]
    yaw = math.radians(float(sys.argv[2])) if len(sys.argv) > 2 else 0.3
    pitch = math.radians(float(sys.argv[3])) if len(sys.argv) > 3 else 0.35
    W, H = 640, 360
    fx = math.tan(math.radians(45))
    xs = np.linspace(-fx, fx, W); ys = np.linspace(fx * H / W, -fx * H / W, H)
    X, Y = np.meshgrid(xs, ys)
    fwd = np.array([math.cos(pitch) * math.sin(yaw), math.sin(pitch), -math.cos(pitch) * math.cos(yaw)])
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    d = fwd + X[..., None] * right + Y[..., None] * up
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    rad, neb = nebula(d)
    # End reference exposure (composite_exposure.glsl): refLum = 0.3 * lum(0.6 E + A) / pi.
    E = 0.55; A = 0.045 * 0.29
    ref = 0.3 * (0.6 * E + A) / math.pi
    exposure = 0.18 / ref
    x = rad * exposure
    srgb = np.clip(x / (1 + x), 0, 1) ** (1 / 2.2)
    Image.fromarray((srgb * 255).astype(np.uint8)).save(out)
    cov = (neb > 0.05).mean()
    peak = srgb.max()
    print(f"exposure x{exposure:.1f}; nebula covers {cov:.0%} of the view; brightest pixel {peak:.2f} (sRGB)")
    assert 0.03 < cov < 0.6, "nebula coverage out of range"
    print("PASS")


if __name__ == "__main__":
    main()

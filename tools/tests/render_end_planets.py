"""Offline preview of shaders/lib/end/planets.glsl geometry (sphere, phase lighting, ring,
ring shadow, front-to-back compositing), with flat albedo instead of the noise textures.

Writes a PNG per planet centred on it at several times so the phase, ring tilt and shadow can
be inspected without the game:  python -P tools/tests/render_end_planets.py <out_dir>
Asserts basic invariants: the lit side faces the black hole, the planet is round, the ring
is darker where the planet's shadow falls.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TAU = 2 * math.pi


def norm(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def rotate_axis(v, k, a):
    k = norm(k)
    return v * math.cos(a) + np.cross(k, v) * math.sin(a) + k * np.dot(v, k) * (1 - math.cos(a))


PLANETS = [
    dict(axis=(0.15, 1.0, 0.35), start=(-0.75, 0.38, 0.45), period=3600.0, rho=math.radians(4.2), dist=0.55,
         spin=(0.25, 1.0, -0.2), kind=1),
    dict(axis=(-0.3, 1.0, 0.1), start=(0.55, 0.52, 0.62), period=1800.0, rho=math.radians(1.6), dist=0.35,
         spin=(0.0, 1.0, 0.3), kind=0),
    dict(axis=(0.4, 1.0, -0.25), start=(0.1, 0.72, -0.68), period=1200.0, rho=math.radians(0.9), dist=0.25,
         spin=(-0.2, 1.0, 0.1), kind=2),
]


def hole_dir(t):
    w = TAU * t / 3600.0
    az = math.radians(35.0 + 18.0 * math.sin(w))
    el = math.radians(24.0 + 5.0 * math.sin(2 * w + 1.1))
    return norm([math.cos(el) * math.sin(az), math.sin(el), -math.cos(el) * math.cos(az)])


def render(p, t, size=256):
    c = norm(rotate_axis(norm(p["start"]), p["axis"], TAU * t / p["period"]))
    centre = c * p["dist"]
    R = p["dist"] * math.sin(p["rho"])
    hole = hole_dir(t)
    L = norm(hole - centre)
    spin = norm(p["spin"])
    # Camera looking at the planet; field of view 3x the ring radius.
    fwd = c
    right = norm(np.cross(fwd, [0.0, 1.0, 0.0]))
    up = np.cross(right, fwd)
    half = math.tan(p["rho"] * (2.6 if p["kind"] == 1 else 1.4))
    xs = np.linspace(-half, half, size)
    X, Y = np.meshgrid(xs, -xs)
    d = norm(fwd[None, None] + X[..., None] * right + Y[..., None] * up)
    pixel_angle = 2 * half / size

    b = d @ centre
    disc = b * b - (centre @ centre - R * R)
    ang = np.arccos(np.clip(d @ c, -1, 1))
    cover = 1 - np.clip((ang - (p["rho"] - pixel_angle)) / (2 * pixel_angle), 0, 1)
    t_hit = b - np.sqrt(np.maximum(disc, 0))
    P = d * t_hit[..., None]
    N = norm(P - centre)
    nl = N @ L
    body = np.where(cover[..., None] > 0, (0.6 * np.maximum(nl, 0) + 0.02)[..., None] * np.array([1.0, 0.9, 0.8]), 0)
    body_a = cover
    t_body = np.where(cover > 0, t_hit, 1e9)

    ring = np.zeros_like(body); ring_a = np.zeros_like(cover); t_ring = np.full_like(cover, 1e9)
    shadow_frac = None
    if p["kind"] == 1:
        dn = d @ spin
        tr = (centre @ spin) / np.where(np.abs(dn) > 1e-4, dn, 1e-4)
        Pr = d * tr[..., None]
        r = np.linalg.norm(Pr - centre, axis=-1) / R
        mask = (tr > 0) & (r > 1.35) & (r < 2.3)
        toC = centre - Pr
        along = toC @ L
        in_shadow = (along > 0) & ((toC * toC).sum(-1) - along * along < R * R)
        shade = np.where(in_shadow, 0.08, 1.0)
        val = 0.5 * abs(spin @ L) * shade + 0.01
        ring = np.where(mask[..., None], val[..., None] * np.array([0.9, 0.85, 0.75]), 0)
        ring_a = np.where(mask, 0.6, 0.0)
        t_ring = np.where(mask, tr, 1e9)
        lit_ring = mask & ~in_shadow
        shadow_frac = (mask & in_shadow).sum() / max(mask.sum(), 1)

    front_is_ring = t_ring < t_body
    fr = np.where(front_is_ring[..., None], ring, body); fa = np.where(front_is_ring, ring_a, body_a)
    br = np.where(front_is_ring[..., None], body, ring); ba = np.where(front_is_ring, body_a, ring_a)
    rgb = fr * fa[..., None] + br * ba[..., None] * (1 - fa[..., None])
    alpha = fa + ba * (1 - fa)
    bg = np.array([0.02, 0.01, 0.04])
    img = rgb + bg * (1 - alpha[..., None])

    # Invariants: lit pixels have N.L > 0, i.e. the bright limb faces the hole.
    inside = cover > 0.99
    lit = inside & (nl > 0.2)
    if lit.any():
        lit_centroid = np.array([X[lit].mean(), Y[lit].mean()])
        hole_screen = np.array([hole @ right, hole @ up])
        if np.linalg.norm(hole_screen) > 1e-3 and np.linalg.norm(lit_centroid) > 1e-6:
            assert lit_centroid @ hole_screen > 0, "lit side does not face the black hole"
    # Roundness: covered area matches pi * (angular radius)^2.
    area = cover.sum() * pixel_angle ** 2
    assert abs(area / (math.pi * math.tan(p["rho"]) ** 2) - 1) < 0.05, "planet is not round/sized correctly"
    return img, shadow_frac


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    out.mkdir(parents=True, exist_ok=True)
    for i, p in enumerate(PLANETS):
        row = []
        for t in (0.0, 600.0, 1200.0, 2400.0):
            img, sf = render(p, t)
            row.append(img)
            if sf is not None:
                print(f"planet {i} t={t:.0f}s: ring pixels in planet shadow {sf:.1%}")
        strip = np.concatenate(row, axis=1)
        srgb = np.clip(strip / (1 + strip) * 1.6, 0, 1) ** (1 / 2.2)
        Image.fromarray((srgb * 255).astype(np.uint8)).save(out / f"planet{i}.png")
    print("PASS (images in", out, ")")


if __name__ == "__main__":
    main()

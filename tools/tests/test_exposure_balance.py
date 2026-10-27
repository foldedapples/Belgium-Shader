"""Reference test for dimension exposure balance (program/composite/exposure.csh,
program/deferred/lighting.fsh, lib/lighting/blocklight.glsl).

Synthetic scenes metered with the old and new rules:
  End: 40 % black sky, terrain lit by the active portal (block light 15..8) and the black hole's
       disk. Old: sky at 30 % weight with a 1e-6 floor, block light 4.0, disk light switched off by
       the sky-light gate (the End has no sky light). New: sky excluded, floor 1e-4, block light
       1.6, disk light on.
  Nether: lava lake filling most of the view. Old: lava emission 8 x albedo, exposure >= 0.8.
       New: exposure >= 0.12 and emission adapted to the exposure.
Display values are exposed scene values before tone mapping; above ~1.5 the tone curve clips to
white and texture detail is lost.

    python -P tools/tests/test_exposure_balance.py
"""

import math

END_STONE = 0.62            # linear albedo (luminance) of End stone
LAVA = (0.80, 0.20, 0.01)    # linear albedo of the lava texture's bright texels
DISK = 3.2                   # End light illuminance (lib/space/end_sky.glsl)


def falloff(level):
    l = level / 15.0
    return l ** 2.6 * (1.0 if l >= 0.5 else (l / 0.5) ** 2 * (3 - 2 * l / 0.5))


def meter(pixels, sky_weight, floor, key_dim=0.065, key_bright=0.18):
    num = den = 0.0
    for lum, sky, w in pixels:
        w = w * (sky_weight if sky else 1.0)
        num += math.log2(max(lum, floor)) * w
        den += w
    avg = 2 ** (num / den)
    key = key_dim + (key_bright - key_dim) * min(max((math.log10(avg) + 4.0) / 3.7, 0.0), 1.0)
    return key / avg


def end_scene(old):
    block_scale = 4.0 if old else 1.6
    disk = 0.0 if old else DISK * 0.45 / math.pi * 0.98     # NoL 0.45; gate kills it in the old code
    pixels = [(1e-5, True, 0.4), (END_STONE * (disk + 0.02), False, 0.45)]
    for level in (15, 12, 9):
        lum = END_STONE * (block_scale * falloff(level) + disk + 0.02)
        pixels.append((lum, False, 0.05))
    ref = 0.18 / (0.35 * DISK / math.pi + 0.01)
    lo, hi = (0.35, 2.5) if old else (0.6, 1.8)
    target = min(max(meter(pixels, 0.3 if old else 0.002, 1e-6 if old else 1e-4), ref * lo), ref * hi)
    near = END_STONE * (block_scale * falloff(15) + disk + 0.02) * target
    far = END_STONE * (disk + 0.02) * target
    return near, far


def lava_scene(old):
    strength = 8.0
    pixels = [(0.2126 * LAVA[0] * strength + 0.7152 * LAVA[1] * strength, False, 0.7), (0.05, False, 0.3)]
    target = min(max(meter(pixels, 0.3, 1e-6 if old else 1e-4), 0.8 if old else 0.12), 24.0)
    eff = strength if old else strength / (1.0 + strength * target / 2.5)
    return max(c * eff for c in LAVA) * target


if __name__ == "__main__":
    for old in (True, False):
        near, far = end_scene(old)
        lava = lava_scene(old)
        tag = "old" if old else "new"
        print(f"{tag}: End stone by the portal {near:5.2f}, End stone lit by the disk only {far:5.2f}, "
              f"lava peak channel {lava:5.2f} (display, before tone mapping)")
    near_o, far_o = end_scene(True)
    near_n, far_n = end_scene(False)
    assert near_o > 1.5 and far_o < 0.05, "old: white by the portal, black elsewhere"
    assert near_n < 1.5 and far_n > 0.1, "new: textured by the portal, disk-lit elsewhere"
    assert lava_scene(True) > 3.0 and lava_scene(False) < 2.6
    print("OK")

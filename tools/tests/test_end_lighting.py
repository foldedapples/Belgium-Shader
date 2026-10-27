"""Reference test for End lighting stability (lib/space/end_sky.glsl endAmbient,
program/begin/frame_setup.csh shadow anchor, shaders.properties endFlashSmooth).

1. The End flash (vanilla 1.21.9+, one every ~30 s). Iris updates endFlashIntensity once per game
   tick (PER_TICK, IrisExclusiveUniforms). Old: the raw value was added to every End surface's
   ambient at 0.4 x (0.55, 0.35, 1.0), so the island brightened several-fold in 20 Hz steps.
   New: eased per frame by Iris's smooth() (half-lives 0.4 s up, 1.2 s down) and 0.012 x on the
   terrain. Measured on End stone lit only by ambient (in shadow) and by the disk as well, with a
   flash modelled as a 4 s swell sampled per tick; the exact vanilla curve is not public, the
   conclusion does not depend on it (the old peak is set by the 0.4 factor, the steps by the tick).
2. The shadow-map anchor. With the End's fixed light, re-anchoring the texel grid near the player
   every SHADOW_ANCHOR_RANGE blocks moved every shadow edge by a fraction of a texel; anchored at
   the world origin the grid never moves.

    python -P tools/tests/test_end_lighting.py
"""

import math
import os
import re

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
END_SKY = open(os.path.join(ROOT, "shaders", "lib", "space", "end_sky.glsl"), encoding="utf-8").read()
PROPS = open(os.path.join(ROOT, "shaders", "shaders.properties"), encoding="utf-8").read()
SETUP = open(os.path.join(ROOT, "shaders", "program", "begin", "frame_setup.csh"), encoding="utf-8").read()
LUMA = np.array([0.2126, 0.7152, 0.0722])
END_LIGHT_DIR = np.array([0.4472136, 0.4472136, -0.7745967])


def srgb_to_linear(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def blackbody(k):
    t = k / 100.0
    r = 1.0 if t <= 66 else 1.29293618 * (t - 60) ** -0.1332047592
    g = 0.39008157 * math.log(t) - 0.63184144 if t <= 66 else 1.12989086 * (t - 60) ** -0.0755148492
    b = 1.0 if t >= 66 else (0.0 if t <= 19 else 0.54320678 * math.log(t - 10) - 1.19625408)
    c = srgb_to_linear(np.array([r, g, b]))
    return c / c.max()


DISK = blackbody(5200.0)
FLASH_COLOUR = np.array([0.55, 0.35, 1.0])
UP = np.array([0.0, 1.0, 0.0])


def ambient(flash, new):
    space = np.array([0.010, 0.010, 0.016])
    disk = DISK * 0.06 * min(max(UP @ END_LIGHT_DIR * 0.5 + 0.5, 0), 1)
    f = FLASH_COLOUR * flash * (0.012 * 1.0 if new else 0.4)
    return float((space + disk + f) @ LUMA)


def direct():
    return float(DISK * 3.2 / math.pi * max(UP @ END_LIGHT_DIR, 0) @ LUMA)


def flash_curve(t):
    """A 4 s swell starting at 1 s (shape assumed; see the module docstring)."""
    x = np.clip((t - 1.0) / 4.0, 0, 1)
    return np.sin(math.pi * x) ** 2


def iris_smooth(values, dt, up, down):
    out, v = [], values[0]
    for x in values:
        hl = up if x > v else down
        v += (x - v) * (1 - 0.5 ** (dt / hl))
        out.append(v)
    return np.array(out)


def test_constants_match_shader():
    assert "vec3 flash = vec3(0.55, 0.35, 1.0) * endFlashSmooth * 0.012 * saturate(n.y * 0.5 + 0.5);" in END_SKY
    assert "uniform.float.endFlashSmooth = smooth(endFlashIntensity, 0.4, 1.2)" in PROPS
    assert "endFlashIntensity * 0.4" not in END_SKY
    assert "anchor = ivec4(0, 0, 0, 1);" in SETUP
    print("constants: the model matches end_sky.glsl, shaders.properties and frame_setup.csh")


def test_flash():
    fps = 60.0
    t = np.arange(0.0, 8.0, 1.0 / fps)
    per_tick = flash_curve(np.floor(t * 20.0) / 20.0)          # what Iris hands the shader
    smooth = iris_smooth(per_tick, 1.0 / fps, 0.4, 1.2)
    rows = []
    for name, lit in (("End stone in shadow", 0.0), ("End stone lit by the disk", direct())):
        old = np.array([ambient(f, False) for f in per_tick]) + lit
        new = np.array([ambient(f, True) for f in smooth]) + lit
        peak_old, peak_new = old.max() / old[0], new.max() / new[0]
        step_old = np.abs(np.diff(old) / old[:-1]).max()
        step_new = np.abs(np.diff(new) / new[:-1]).max()
        rows.append((name, peak_old, peak_new, step_old, step_new))
    shade = rows[0]
    assert shade[1] > 3.0 and shade[2] < 1.2, shade
    assert shade[4] < 0.01 and shade[3] > 0.05, shade
    for name, po, pn, so, sn in rows:
        print(f"flash, {name}: peak brightening {po:.2f}x -> {pn:.2f}x; largest change between frames at 60 FPS "
              f"{100 * so:.1f} % -> {100 * sn:.2f} %")


def test_anchor():
    # Texel phase of a fixed world point along the light-space x axis, for cascade texels of
    # 0.04-0.6 blocks, before and after a 32-block re-anchor with the End's fixed light.
    z = END_LIGHT_DIR
    x = np.cross([0.0, math.sin(math.radians(-25.0)), math.cos(math.radians(-25.0))], z)
    x /= np.linalg.norm(x)
    worst = 0.0
    for texel in (0.04, 0.1, 0.25, 0.6):
        for d in ((32, 0, 0), (0, 0, 32), (32, 0, 32), (-32, 0, 17)):
            jump = (np.dot(x, d) / texel) % 1.0
            worst = max(worst, min(jump, 1 - jump))
    assert worst > 0.2
    print(f"shadow anchor: old re-anchoring every 32 blocks moved shadow edges by up to {worst:.2f} texel; "
          "anchored at the world origin in the End: 0")


if __name__ == "__main__":
    test_constants_match_shader()
    test_flash()
    test_anchor()
    print("OK")

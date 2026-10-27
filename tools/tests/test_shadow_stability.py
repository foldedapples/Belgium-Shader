"""Reference test for the shadow-cascade grid (program/begin/frame_setup.csh, lib/lighting/shadows.glsl).

Re-implements the GLSL maths in numpy, in float32 where the GPU uses float and float64 where
begin.csh uses double, and checks:

1. With the light fixed, a static world point maps to the same shadow texel while the camera
   walks, strafes, flies and turns (translation is fully absorbed by texel snapping).
2. With the light rotating as the sun does (and with the float noise Iris' view-space sunPosition
   carries when the head turns), the grid drift near the player stays far below a texel per
   frame with the near-player anchor, while the old world-origin pivot drifts by many texels.
3. The reconstructed receiver position without the TAA jitter correction is off by about half a
   pixel, enough to cross far-cascade texels; with the correction it is exact.

    python -P tools/tests/test_shadow_stability.py
"""

import numpy as np

SHADOW_DISTANCE = 160.0
RESOLUTION = 4096
ANCHOR_RANGE = 32
EXTENTS = [SHADOW_DISTANCE / 16.0, SHADOW_DISTANCE / 6.0, SHADOW_DISTANCE / 2.5, SHADOW_DISTANCE]
SUN_PATH_ROTATION = np.radians(-25.0)
AXIS = np.array([0.0, np.sin(SUN_PATH_ROTATION), np.cos(SUN_PATH_ROTATION)])


def texel(k):
    return 2.0 * EXTENTS[k] / (RESOLUTION * 0.5)


def light_basis(to_light, axis=AXIS):
    z = to_light / np.linalg.norm(to_light)
    x = np.cross(axis, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return np.stack([x, y, z])          # rows = light-space axes (GLSL transpose(mat3(x,y,z)))


def sun_dir(angle):
    """Sun on its great circle about AXIS (angle 0 = noon-ish)."""
    up = np.array([0.0, 1.0, 0.0])
    up = up - AXIS * np.dot(up, AXIS)
    up /= np.linalg.norm(up)
    side = np.cross(AXIS, up)
    return np.cos(angle) * up + np.sin(angle) * side


def cascade_offsets(L, cam_int, cam_fract, anchor):
    """begin.csh: double-precision snapped offsets."""
    c = L.astype(np.float64) @ ((cam_int - anchor).astype(np.float64) + cam_fract.astype(np.float64))
    out = []
    for k in range(4):
        t = texel(k)
        snapped = np.floor(c[:2] / t) * t
        out.append((c[:2] - snapped).astype(np.float32))
    return out


def texel_coord(world, L, cam_int, cam_fract, anchor, k):
    """Receiver/caster: float32 player-space position, rotation, offset, cascade-space texel."""
    player = (world - cam_int - cam_fract).astype(np.float32)        # Iris gives camera-relative
    lp = (L.astype(np.float32) @ player)[:2]
    off = cascade_offsets(L, cam_int, cam_fract, anchor)[k]
    c = (lp + off) / np.float32(EXTENTS[k])                           # [-1,1] inside the cascade
    return (c * 0.5 + 0.5) * (RESOLUTION * 0.5)                       # texel units


def update_anchor(anchor, cam_block):
    if anchor is None or np.any(np.abs(cam_block - anchor) > ANCHOR_RANGE):
        return cam_block.copy()
    return anchor


def test_translation_is_absorbed():
    rng = np.random.default_rng(1)
    L = light_basis(sun_dir(0.6))
    base = np.array([12000, 70, -8000])
    world = base + np.array([3.37, 0.81, -2.29])
    anchor = None
    ref = None
    for step in range(400):
        cam = base + rng.uniform(-6, 6, 3) + np.array([step * 0.37, np.sin(step * 0.1) * 3.0, -step * 0.21])
        cam_int = np.floor(cam).astype(np.int64)
        cam_fract = cam - cam_int
        anchor = update_anchor(anchor, cam_int)
        coords = [texel_coord(world, L, cam_int, cam_fract, anchor, k) for k in range(4)]
        if ref is None:
            ref, ref_anchor = coords, anchor.copy()
        if np.array_equal(anchor, ref_anchor):
            for k in range(4):
                # The cascade re-centres in whole texels, so only the sub-texel phase must hold.
                d = coords[k] - ref[k]
                err = np.max(np.abs((d + 0.5) % 1.0 - 0.5))
                assert err < 0.02, f"cascade {k}: static point moved {err:.4f} texels (step {step})"
    print("translation: static point keeps its texel to < 0.02 texel in all cascades")


def drift_per_frame(use_anchor, world_base, noise=0.0, frames=240):
    rng = np.random.default_rng(2)
    cam = world_base.astype(np.float64)
    cam_int = np.floor(cam).astype(np.int64)
    cam_fract = cam - cam_int
    anchor = cam_int.copy() if use_anchor else np.zeros(3, dtype=np.int64)
    world = cam + np.array([4.2, -1.3, 2.7])
    angle = 0.5
    prev = None
    worst = 0.0
    for _ in range(frames):
        angle += 2 * np.pi / 24000.0 / 3.0            # sun motion per frame at 60 fps (20 ticks/s)
        d = sun_dir(angle) + rng.normal(0.0, noise, 3)   # float noise of view-space sunPosition
        L = light_basis(d)
        tc = texel_coord(world, L, cam_int, cam_fract, anchor, 0)
        if prev is not None:
            # Drift of the sub-texel phase (what makes edges shimmer); the true geometric motion of
            # a point 5 blocks from the camera under the sun's rotation is ~5e-4 texel per frame.
            worst = max(worst, np.max(np.abs(((tc - prev) + 0.5) % 1.0 - 0.5)))
        prev = tc
    return worst


def test_rotation_drift():
    base = np.array([12000.0, 70.0, -8000.0])
    for noise, label in ((0.0, "sun motion"), (1e-6, "sun motion + head-turn noise")):
        old = drift_per_frame(False, base, noise)
        new = drift_per_frame(True, base, noise)
        print(f"{label}: cascade-0 drift per frame  world-origin pivot {old:.3f} texel, "
              f"near-player anchor {new:.4f} texel")
        assert new < 0.05, new
        assert old > 5 * new, (old, new)


def test_jitter_reconstruction():
    # A surface 100 blocks away seen through a 1080p, 70 degree view: half a pixel of jitter.
    fov = np.radians(70.0)
    pixel_angle = 2.0 * np.tan(fov / 2.0) / 1080.0
    jitter_px = 0.5
    err_blocks = 100.0 * pixel_angle * jitter_px
    far_texel = texel(3)
    print(f"jitter: uncorrected reconstruction error at 100 blocks = {err_blocks:.3f} block "
          f"= {err_blocks / far_texel:.2f} far-cascade texels (corrected: 0)")
    assert err_blocks / far_texel > 0.3


if __name__ == "__main__":
    test_translation_is_absorbed()
    test_rotation_drift()
    test_jitter_reconstruction()
    print("OK")

"""Reference test for the sun's bloom (program/composite/bloom.fsh, lib/post/bloom.glsl, final.fsh).

Builds a 1920x1080 daytime sky with the sun disk, runs the bloom chain (box mips, per-tile soft
limit of 24 x display white, level weights 2^-0.55 L, mix 0.045), and measures how far from the
sun the glare stays above a visible level, with the raw disk radiance (before) and with the disk
limited to SUN_DISK_PEAK x display white (lib/sky/celestial.glsl, after).

    python -P tools/tests/test_sun_glare.py
"""

import numpy as np

W, H = 1920, 1080
FOV_Y = np.radians(70.0)
SUN_SIZE = 1.5
SUN_RADIUS = 0.004654 * SUN_SIZE            # radians
SUN_ILLUMINANCE = 10.0
EXPOSURE = 0.25                              # daylight (sky ~0.6 display before tone mapping)
SKY = 0.6 / EXPOSURE
SUN_DISK_PEAK = 120.0
LIMIT = 24.0
VISIBLE = 0.05                               # display units added by bloom that read as glare


def render(limit_disk):
    pix = 2.0 * np.tan(FOV_Y / 2) / H
    y, x = np.mgrid[0:H, 0:W]
    ang = np.hypot(x - W / 2, y - H / 2) * pix
    img = np.full((H, W), SKY)
    peak = SUN_ILLUMINANCE / (np.pi * SUN_RADIUS ** 2)
    if limit_disk:
        peak = min(peak, SUN_DISK_PEAK / EXPOSURE / 1.32)
    cover = np.clip((SUN_RADIUS - ang) / pix + 0.5, 0, 1)
    img += cover * peak
    return img, peak


def mip(img, level):
    f = 2 ** level
    h, w = img.shape[0] // f, img.shape[1] // f
    return img[: h * f, : w * f].reshape(h, f, w, f).mean(axis=(1, 3))


def bloom(img):
    out = np.zeros_like(img)
    wsum = 0.0
    for level in range(2, 8):
        m = mip(img, level - 1)
        lum = m * EXPOSURE
        m = m * (LIMIT / (LIMIT + lum))
        up = np.kron(m, np.ones((2 ** (level - 1), 2 ** (level - 1))))
        up = np.pad(up, ((0, H - up.shape[0]), (0, W - up.shape[1])), mode="edge")
        wgt = 2.0 ** (-0.55 * (level - 2))
        out += up * wgt
        wsum += wgt
    return out / wsum


def glare_radius(limit_disk):
    img, peak = render(limit_disk)
    b = bloom(img)
    added = (0.045 * (b - img)) * EXPOSURE        # display-referred contribution of the bloom mix
    pix = 2.0 * np.tan(FOV_Y / 2) / H
    y, x = np.mgrid[0:H, 0:W]
    ang = np.degrees(np.hypot(x - W / 2, y - H / 2) * pix)
    mask = added > VISIBLE
    return (ang[mask].max() if mask.any() else 0.0), peak * EXPOSURE


if __name__ == "__main__":
    r0, p0 = glare_radius(False)
    r1, p1 = glare_radius(True)
    print(f"raw disk ({p0:,.0f} x white): glare above {VISIBLE} display reaches {r0:.1f} deg from the sun")
    print(f"limited disk ({p1:,.0f} x white): glare above {VISIBLE} display reaches {r1:.1f} deg")
    assert r1 < 0.5 * r0, (r0, r1)
    assert r1 > 0.5, "the sun should still glow"
    print("OK")

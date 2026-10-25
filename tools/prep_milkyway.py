"""Build shaders/textures/milkyway.png from NASA SVS "Deep Star Maps 2020" (SVS 4851).

Source: https://svs.gsfc.nasa.gov/4851  file milkyway_2020_4k.exr (celestial coordinates,
plate carree, linear half-float RGB; the Milky Way and faint stars with the bright Hipparcos
and Tycho stars removed - the pack draws bright stars procedurally). Credit NASA/Goddard
Space Flight Center Scientific Visualization Studio, Gaia DR2: ESA/Gaia/DPAC. SVS work is
public domain, but the map is derived from Gaia data, which ESA distributes under CC BY-NC
3.0 IGO: treat the output as non-commercial with attribution (docs/THIRD_PARTY_ASSETS.md).

Orientation of the source, verified from the data (not assumed): row 0 is Dec +90, the
galactic centre (RA 266.4, Dec -29.0) is the brightest broad region at u = 0.742, the LMC
(RA 80.9, Dec -69.8) appears at u = 0.275, i.e. u = 0.5 - RA / 360 (RA 0h at the centre,
increasing to the left, as seen from inside the sphere).

Output: box-filtered to --width x width/2, encoded as 8-bit sRGB-container PNG with a cube-root
curve (value = linear^(1/3), linear normalised to the source maximum of 1.0); the shader cubes
it back. The cube root keeps the faint off-band sky (median 0.014 -> code 61) well above 8-bit
banding. Usage:
    python -P tools/prep_milkyway.py --exr <dir>/milkyway_2020_4k.exr [--width 2048]
Needs the OpenEXR Python package (pip install OpenEXR).
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "shaders" / "textures"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exr", required=True)
    ap.add_argument("--width", type=int, default=2048)
    args = ap.parse_args()
    import OpenEXR  # imported here so the rest of tools/ does not depend on it

    f = OpenEXR.File(args.exr)
    ch = f.channels()
    rgb = ch["RGB"].pixels.astype(np.float32) if "RGB" in ch else np.stack(
        [ch[c].pixels.astype(np.float32) for c in ("R", "G", "B")], axis=-1)
    h, w = rgb.shape[:2]
    if w != 2 * h:
        raise SystemExit(f"expected a 2:1 plate carree map, got {w}x{h}")
    k = w // args.width
    if k < 1 or w % args.width:
        raise SystemExit("--width must divide the source width")
    small = rgb.reshape(h // k, k, w // k, k, 3).mean(axis=(1, 3))
    small = np.clip(small, 0.0, 1.0)
    enc = np.cbrt(small)
    img = np.clip(enc * 255.0 + 0.5, 0, 255).astype(np.uint8)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img, "RGB").save(OUT / "milkyway.png", optimize=True)
    # Wrap in RA (horizontal); linear filtering.
    (OUT / "milkyway.png.mcmeta").write_text('{"texture": {"blur": true, "clamp": false}}\n')
    lum = small.mean(-1)
    print(f"milkyway.png {small.shape[1]}x{small.shape[0]}  median {np.median(lum):.4f}  "
          f"p99 {np.percentile(lum, 99):.4f}  max {lum.max():.4f}")


if __name__ == "__main__":
    main()

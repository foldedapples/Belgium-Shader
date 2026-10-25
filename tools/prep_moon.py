#!/usr/bin/env python3
"""Builds the moon textures from NASA's CGI Moon Kit (SVS 4720, public domain).

Inputs (download from https://svs.gsfc.nasa.gov/4720 into tools/raw/ or pass --raw):
  lroc_color_poles_2k.tif / _4k.tif / _8k.tif   LRO LROC WAC colour mosaic, equirectangular,
                                                 8-bit sRGB, longitude 0 at the centre
  ldem_16_uint.tif                               LRO LOLA elevation, 16 px/deg (5760x2880),
                                                 uint16 in half-metre units

Outputs (shaders/textures/):
  moon_albedo_{2k,4k,8k}.png  colour, mean linear albedo normalised to 0.28, stored as a mip
                              atlas (base W x H on the left, levels 1.. stacked in a W/2 column)
  moon_normal_{2k,4k}.png     tangent-frame normals (R = east, G = north, 0.5 = flat) from the
                              LOLA DEM, same atlas layout. No 8K normal map is produced: the
                              DEM's native resolution is 5760 px wide, so 8K would be invented
                              detail. The 8K albedo option uses the 4K normal map.

Iris does not build mipmaps for custom textures; the atlas lets the shader pick a prefiltered
level so the small moon disk does not alias or shimmer.

Usage: python -P tools/prep_moon.py [--raw DIR] [--sizes 2k 4k 8k]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "shaders" / "textures"
MOON_RADIUS_M = 1737400.0
TARGET_MEAN_ALBEDO = 0.28


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def downsample2(a):
    h, w = a.shape[0] // 2 * 2, a.shape[1] // 2 * 2
    a = a[:h, :w]
    return 0.25 * (a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2])


def build_atlas(base, renormalize=False):
    """base: H x W x C float. Returns atlas H x 1.5W x C (levels until height < 4)."""
    h, w, c = base.shape
    atlas = np.zeros((h, w + w // 2, c), dtype=np.float32)
    atlas[:, :w] = base
    level = base
    y = 0
    while level.shape[0] >= 8:
        level = downsample2(level)
        if renormalize:
            level = renorm(level)
        lh, lw = level.shape[:2]
        atlas[y:y + lh, w:w + lw] = level
        y += lh
    return atlas


def renorm(n):
    # normals stored as (east, north, up) in [-1,1]
    l = np.linalg.norm(n, axis=-1, keepdims=True)
    return n / np.maximum(l, 1e-6)


def save_rgb(arr01, path):
    Image.fromarray(np.clip(arr01 * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB").save(path, optimize=True)
    print(f"  {path.name}: {arr01.shape[1]}x{arr01.shape[0]}, {path.stat().st_size / 1e6:.1f} MB")


def make_albedo(raw: Path, size: str):
    src = raw / f"lroc_color_poles_{size}.tif"
    img = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
    lin = srgb_to_linear(img)
    lum = lin @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    # Area-weighted mean (equirectangular rows shrink by cos(latitude)).
    h = lin.shape[0]
    lat = (0.5 - (np.arange(h) + 0.5) / h) * np.pi
    wts = np.cos(lat)[:, None]
    mean = float((lum * wts).sum() / (wts.sum() * lum.shape[1]))
    lin = lin * (TARGET_MEAN_ALBEDO / mean)
    atlas = build_atlas(lin)
    save_rgb(linear_to_srgb(atlas), OUT / f"moon_albedo_{size}.png")


def make_normals(raw: Path, width: int, name: str):
    dem = np.asarray(Image.open(raw / "ldem_16_uint.tif")).astype(np.float64) * 0.5  # metres
    h_src, w_src = dem.shape
    # Resample (area-average) to the target size.
    target = (width, width // 2)
    dem_img = Image.fromarray(dem.astype(np.float32), "F").resize(target, Image.Resampling.BOX)
    dem = np.asarray(dem_img).astype(np.float64)
    h, w = dem.shape
    lat = (0.5 - (np.arange(h) + 0.5) / h) * np.pi
    dx = 2.0 * np.pi * MOON_RADIUS_M * np.maximum(np.cos(lat), 0.05) / w   # metres per column
    dy = np.pi * MOON_RADIUS_M / h                                         # metres per row
    # Central differences; longitude wraps, latitude clamps.
    dzdx = (np.roll(dem, -1, axis=1) - np.roll(dem, 1, axis=1)) / (2.0 * dx[:, None])
    up = np.vstack([dem[:1], dem[:-1]])
    down = np.vstack([dem[1:], dem[-1:]])
    dzdn = (up - down) / (2.0 * dy)          # north is up in the image
    n = np.stack([-dzdx, -dzdn, np.ones_like(dem)], axis=-1)
    n = renorm(n).astype(np.float32)
    atlas = build_atlas(n, renormalize=True)
    rgb = np.concatenate([atlas[..., :2] * 0.5 + 0.5, np.clip(atlas[..., 2:3], 0, 1)], axis=-1)
    save_rgb(rgb, OUT / f"moon_normal_{name}.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", type=Path, default=ROOT / "tools" / "raw")
    ap.add_argument("--sizes", nargs="+", default=["2k", "4k", "8k"])
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for s in args.sizes:
        print(f"albedo {s}")
        make_albedo(args.raw, s)
    print("normals")
    make_normals(args.raw, 2048, "2k")
    make_normals(args.raw, 4096, "4k")
    for f in OUT.glob("moon_*.png"):
        (OUT / (f.name + ".mcmeta")).write_text('{"texture": {"blur": true, "clamp": true}}\n')


if __name__ == "__main__":
    main()

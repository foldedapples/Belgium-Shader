# Meridian Shaders / Belgium Shader

An original, physically based shader pack for Minecraft Java Edition on Iris, written from
scratch. "Meridian" and "Belgium Shader" are working titles of the same pack; the final name is
not decided. Deferred renderer with LabPBR 1.3 materials, stable cascaded
shadows, a LUT atmosphere, volumetric clouds, real sky data from NASA, interactive water, a
ray-traced black hole in the End, a smoky Nether, and Distant Horizons / Voxy support.

> **Status: development build, not yet run in Minecraft.** Every program compiles under Khronos
> glslang for every dimension, for the base / Distant Horizons / Voxy variants and all five quality
> profiles, and the shadow and glare fixes pass CPU reference tests. In-game behaviour,
> compatibility and performance are still to be verified. See [docs/TESTING.md](docs/TESTING.md)
> and [docs/FEATURE_STATUS.md](docs/FEATURE_STATUS.md).

## Features

* **Materials:** full LabPBR 1.3 decoding (exact conductor Fresnel for the predefined metals,
  porosity, SSS, emission, material AO, parallax with self-shadowing); built-in materials for
  vanilla textures (metals, copper oxidation, glass, ice, wet-able soils, foliage SSS).
* **Lighting:** GGX + height-correlated Smith with multiple-scattering compensation; sky ambient
  from a live spherical-harmonic projection of the sky; bounced sunlight (reflective shadow
  maps); horizon-based AO; contact shadows.
* **Stable shadows:** four texel-snapped cascades whose grid is anchored to the world, so static
  shadows do not move when you walk, strafe, fly or turn (reference-tested, not yet in game); physically sized soft shadows
  (PCSS), coloured shadows through stained glass, cloud shadows, caustics under water.
* **Coloured light:** torches, lava, soul fire, sea lanterns, froglights, redstone and more colour
  nearby surfaces; brightness follows vanilla light, so colour never leaks through walls.
* **Sky:** physically based atmosphere (Rayleigh, aerosols, ozone, multiple scattering); a Moon
  built from NASA's CGI Moon Kit (2K/4K/8K colour, LOLA relief) with geometric phases, earthshine
  and solar/lunar eclipses; 42,731 real stars (Yale Bright Star Catalogue + NASA Deep Star Maps)
  and NASA's Milky Way, with star visibility that follows moonlight.
* **Clouds:** volumetric cumulus, stratus, stratocumulus and storm towers from a moving weather
  map, multiple scattering and silver linings, cirrus, temporal reconstruction.
* **Water:** wind-driven waves that differ between oceans, lakes and flowing water; an interactive
  wave simulation (swimming, splashes, boat wakes, reflection from shores); refraction,
  absorption, Snell's window, rain ripples.
* **Weather:** wind-slanted rain that reflects the sky, gradual wetting and drying by material
  porosity, puddles, lightning that lights the world.
* **The End:** deep space from real galaxy data, procedural planets, and a gravitationally lensing
  black hole whose accretion disk lights the islands.
* **The Nether:** biome-tinted smoke and haze, lava glow, heat shimmer, ash.
* **Post:** TAA, bloom, auto exposure with night (Purkinje) vision, hue-preserving filmic tone
  mapping (or Khronos PBR Neutral), colour profiles Natural / Vibrant (default) / Cinematic /
  Realistic / Fantasy / Custom.
* **Presets:** Low, Medium, High (default), Ultra, Cinematic. Settings in 23 screens (General …
  Debugging). 20 debug views.

## Install

1. Minecraft 1.21.11 with Fabric, Sodium and Iris. Requires OpenGL 4.3 (not macOS).
2. Copy the repository folder (it must contain `shaders/`) into `.minecraft/shaderpacks/`, or zip
   `shaders/`, `LICENSE` and `THIRD_PARTY_NOTICES.md` and put the zip there.
3. Video Settings → Shader Packs → select the pack. Choose a profile at the top of the settings.

Distant Horizons and Voxy are supported separately. Using both at once is not supported.

## Development

```
python -I tools/validate.py --variants base dh voxy --profiles   # compile everything (needs glslang)
python -I tools/check_options.py                                 # settings menu consistency
python -P tools/tests/test_shadow_stability.py
python -P tools/tests/test_sun_glare.py
```

Files in `shaders/world0`, `world-1` and `world1` are thin wrappers that set the dimension define
and include `shaders/program/...`. Edit the included program. Some source comments mention tools
(`gen_wrappers.py`, `prep_moon.py`, `prep_stars.py`, `gen_noise.py`, `gen_dfg.py`, `package.py`) that
were lost with an earlier working copy and are not in this repository. Their outputs (wrappers,
textures, LUTs) are.

## Documentation

* [Feature status](docs/FEATURE_STATUS.md): what exists, what was reviewed, what is verified
* [Regression audit](docs/REGRESSION_AUDIT.md): what was wrong, the root causes, and the fixes
* [Rendering research](docs/RENDERING_RESEARCH.md): verified Iris/DH facts, techniques, data sources
* [Reference-pack research](docs/REVERSE_ENGINEERING_RESEARCH.md): how Eclipse, Bliss and Complementary approach each effect
* [Testing](docs/TESTING.md) · [Changelog](CHANGELOG.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)

## Licence

Code: MIT (LICENSE). Data: NASA SVS (public domain, credit requested), Yale BSC (cite), and a
Gaia-derived Milky Way map that is treated as non-commercial — see THIRD_PARTY_NOTICES.md.
This project contains no code from other shader packs.

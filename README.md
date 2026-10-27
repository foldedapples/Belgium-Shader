# Meridian Shaders

An original, physically based shader pack for Minecraft Java Edition on Iris, written from
scratch (working title "Meridian"). Deferred renderer with LabPBR 1.3 materials, stable cascaded
shadows, a LUT atmosphere, volumetric clouds, real sky data from NASA, interactive water, a
ray-traced black hole in the End, a smoky Nether, and Distant Horizons / Voxy support.

> **Status: development build, not yet run in Minecraft.** Every program compiles for every
> profile, dimension and LOD variant (4,245 stage compiles with Khronos glslang), the numerical
> systems pass reference tests, the pack's own GLSL passes GPU unit tests, and the sky, clouds,
> Moon, stars and black hole have been checked visually in a WebGL harness. In-game behaviour,
> compatibility and performance are still to be verified — see docs/TESTING.md.

## Features

* **Materials:** full LabPBR 1.3 decoding (exact conductor Fresnel for the predefined metals,
  porosity, SSS, emission, material AO, parallax with self-shadowing); built-in materials for
  vanilla textures (metals, copper oxidation, glass, ice, wet-able soils, foliage SSS).
* **Lighting:** GGX + height-correlated Smith with multiple-scattering compensation; sky ambient
  from a live spherical-harmonic projection of the sky; bounced sunlight (reflective shadow
  maps); horizon-based AO; contact shadows.
* **Stable shadows:** four texel-snapped cascades whose grid is anchored to the world, so static
  shadows do not move when you walk, strafe, fly or turn (tested); physically sized soft shadows
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
* **Presets:** Low, Medium, High (default), Ultra, Cinematic. Settings in 21 screens (General …
  Debugging). 20 debug views.

## Install

1. Minecraft 1.21.11 with Fabric, Sodium 0.8.12 and Iris 1.10.8 (other versions: see
   docs/COMPATIBILITY.md). Requires OpenGL 4.3 (not macOS).
2. Run `python -P tools/package.py` and copy `dist/MeridianShaders-*.zip` into
   `.minecraft/shaderpacks/` (or copy the repository folder there directly).
3. Video Settings → Shader Packs → Meridian. Choose a profile at the top of the settings.

## Development

```
python -I tools/gen_wrappers.py                       # after adding/renaming programs
python -I tools/validate.py --variants base dh voxy   # compile everything (needs glslang)
python -P tools/tests/test_shadow_stability.py
python -P tools/tests/test_water_sim.py
python -P tools/tests/test_cloud_march.py
python -P tools/tests/test_haze_glare.py
python -P tools/preview/build_preview.py              # WebGL sky preview + GPU unit tests
python -P tools/package.py
python -I tools/install_dev.py                        # copy into the test profile as Meridian-dev
python -I tools/check_iris_log.py                     # Iris/Voxy errors from logs/latest.log
```

Asset rebuild (downloads go to `raw/`, see docs/ASSET_SOURCES.md): `tools/prep_moon.py`,
`tools/prep_stars.py`, `tools/gen_noise.py`, `tools/gen_dfg.py`.

## Documentation

* [Feature status](docs/FEATURE_STATUS.md) – what is implemented, what is verified and how
* [Regression audit](docs/REGRESSION_AUDIT.md) – what went wrong before, root causes, fixes
* [Rendering research](docs/RENDERING_RESEARCH.md) – verified Iris/Voxy/DH/LabPBR facts, data sources, techniques
* [Architecture](docs/ARCHITECTURE.md) – frame, buffer ownership, algorithms, units
* [Source provenance](docs/SOURCE_PROVENANCE.md) · [Asset sources](docs/ASSET_SOURCES.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)
* [Testing](docs/TESTING.md) · [Compatibility](docs/COMPATIBILITY.md) · [Performance](docs/PERFORMANCE.md)
* [Milestones](docs/MILESTONES.md) · [Changelog](CHANGELOG.md)

## Licence

Code: MIT (LICENSE). Data: NASA SVS (public domain, credit requested), Yale BSC (cite), and a
Gaia-derived Milky Way map that is treated as non-commercial — see THIRD_PARTY_NOTICES.md.
This project contains no code from other shader packs.

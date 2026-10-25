# Belgium Shaders

An original, physically based shader pack for Minecraft Java Edition on Iris, written from
scratch: its own rendering engine, water simulation, atmosphere, clouds, celestial model and
black hole. ("Belgium Shaders" is the working title.)

> **Status: pre-release, not yet run in game.** Everything compiles for all presets and
> option combinations under Khronos glslang and the numerical systems pass CPU reference
> tests, but no in-game testing or profiling has happened yet. See
> [docs/FEATURE_STATUS.md](docs/FEATURE_STATUS.md) and [docs/TESTING.md](docs/TESTING.md).

## Highlights

* **Lighting:** GGX microfacet BRDF with exact dielectric/conductor Fresnel, full LabPBR 1.3,
  energy-compensated environment specular, subsurface scattering, coloured block light from a
  voxel flood fill that never leaks past vanilla light, screen-space GI with coloured bounce,
  a dynamic hand light tinted by the held item, block-light highlights, SSAO and contact shadows.
* **Shadows:** the pack's own light matrix and distortion (texel-snapped, stable), five
  filtering tiers up to variable penumbra from the sun's real angular size, coloured
  translucent shadows, cloud shadows.
* **Water:** a wind-driven analytic ocean spectrum plus a GPU height-field simulation around
  you — swimming ripples, mass-conserving splashes, boat wakes — with refraction, absorption,
  reflections, caustics computed from the actual waves, light shafts and Snell's window.
* **Sky:** precomputed atmospheric scattering, limb-darkened sun, NASA LRO moon (2K/4K/8K)
  with real relief and phases from geometry, solar and lunar eclipses from an orbital model,
  procedural stars with NASA's Deep Star Maps Milky Way, auroras, rainbows from optics.
* **Clouds:** volumetric stratus to cumulonimbus driven by weather, temporal reconstruction,
  cirrus, lightning.
* **Dimensions:** a gravitationally lensing black hole with a Doppler-beamed accretion disk
  lights the End; the Nether gets dense smoky haze and heat shimmer.
* **Post:** TAA, auto exposure, energy-conserving bloom, a custom filmic curve, grading,
  optional depth of field and motion blur.
* **Colour profiles:** Natural, Vibrant (default), Cinematic, Fantasy and Custom.
* **Compatibility:** Minecraft 1.20.1 – 26.3 on Iris (exact builds in
  [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)); Distant Horizons and Voxy LOD terrain with
  the same lighting as vanilla terrain; presets LOW → CINEMATIC.

## Install

1. Install [Iris](https://modrinth.com/mod/iris) for your Minecraft version (1.10.4 or newer
   recommended for boat wakes; see docs/COMPATIBILITY.md).
2. Copy the `Belgium Shaders` folder (or the release ZIP from `tools/package.py`) into
   `.minecraft/shaderpacks/`.
3. Video Settings → Shader Packs → select it. Pick a quality preset at the top of the
   settings screen.

Requires OpenGL 4.3 (Windows/Linux; not macOS).

## Repository layout

```
shaders/            the pack (Iris loads this folder)
  program/          stage implementations (one per Iris program family)
  lib/              modules: core, material, lighting, atmosphere, sky, clouds, water,
                    weather, reflections, end, nether, post, compat, debug
  world0|world1|world-1/  generated wrappers (tools/gen_wrappers.py) - do not edit
  textures/         NASA moon atlases and generated noise
docs/               research, architecture, status, compatibility, performance, testing
tools/              wrapper generator, validator, noise/moon asset builders, packaging, tests
```

## Development

```
python tools/gen_wrappers.py                 # after adding or renaming programs
set GLSLANG=C:\path\to\glslang.exe
python tools/validate.py                     # compile every program for every variant
python -P tools/tests/test_water_sim.py      # CPU reference tests
python -P tools/tests/test_celestial.py
python -P tools/tests/test_black_hole.py
python tools/package.py                      # dist/BelgiumShaders-<version>.zip
```

Rebuilding assets: `python tools/gen_noise.py`; `python -P tools/prep_moon.py --raw <dir>`
with the NASA CGI Moon Kit files (see docs/THIRD_PARTY_ASSETS.md).

## Documentation

* [Rendering research](docs/RENDERING_RESEARCH.md) – what the reference packs and Iris do.
* [Original architecture](docs/ORIGINAL_ARCHITECTURE.md) – pipeline, buffers, algorithms.
* [Expansion plan](docs/EXPANSION_PLAN.md) · [Feature status](docs/FEATURE_STATUS.md) · [Compatibility](docs/COMPATIBILITY.md) ·
  [Performance](docs/PERFORMANCE.md) · [Debugging](docs/DEBUGGING.md) ·
  [Test plan](docs/TESTING.md) · [Third-party assets](docs/THIRD_PARTY_ASSETS.md)

## License

Code: MIT (`LICENSE`). Moon imagery: NASA's Scientific Visualization Studio, public domain
(see docs/THIRD_PARTY_ASSETS.md). This project is independent; it contains no code from Bliss,
Eclipse, Glimmer or Halcyon.

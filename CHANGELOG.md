# Changelog

## 0.3.0-dev (branch halcyon-integration, not yet tested in game)

Halcyon's own feature code is being ported onto the Belgium engine (docs/HALCYON_INTEGRATION.md).

* Sky slice: Halcyon's catalogue stars and NASA Milky Way, NASA moon with phases and earthshine,
  solar and lunar eclipses, aurora, cirrus with the 22° halo and rainbows - imported unchanged,
  connected through a new adapter and bridge. Default; Belgium's sky stays selectable (Sky Source).
  Halcyon's celestial model also drives moonlight and eclipse lighting.
* tools/import_halcyon.py (imports modules, generates the hc_ namespace headers),
  tools/halcyon_deps.py (per-module dependency map against Glimmer 6a59109).
* Our own Perlin texture (perlin2d.png) in place of Glimmer's.
* Options renamed in Belgium's sky where Halcyon uses the name differently: BE_AURORA_FREQUENCY,
  BE_MOON_SIZE, BE_STAR_DENSITY, BE_ECLIPSE_PREVIEW, BE_SUN_SIZE.
* Validator follows Iris for bare #define toggles; .lang files may be UTF-8.
* Fixed tools/gen_noise.py, which had a syntax error since the cloud-noise mcmeta change.

## 0.2.0-dev (unreleased, not yet tested in game)

Expansion: Iris/DH/Voxy integration, multi-version support, vibrant coloured lighting.
Statically validated only (105 compile variants, CPU tests).

* Version support: Iris 1.6.14 fallbacks (split camera position derived from the float
  position; emitter levels per block class when `BLOCK_EMISSION_ATTRIBUTE` is missing);
  `iris.features.required/optional`; validator environments for MC 1.20.1 … 26.3.
  Compatibility matrix of exact published builds (docs/COMPATIBILITY.md).
* Distant Horizons: `dh_shadow` behind the experimental LOD Shadows option; per-block albedo
  variation; SSR and puddles disabled on LODs.
* Voxy: water written with a "needs waves" flag; composite adds analytic waves.
* Packed water record (vanilla light levels + wave flag) shared by all water writers.
* Screen-space GI (deferred2/3, half resolution, temporal), lighting moved to deferred4.
* Dynamic hand light coloured by the held item; block-light specular from the light-volume
  gradient.
* Colour profiles Natural / Vibrant (default) / Cinematic / Fantasy / Custom, applied at the
  source of each quantity; new Cinematic and hue-preserving tone curves.
* Debug View 21 (SSGI).

## 0.1.0-dev (unreleased, not yet tested in game)

First complete pass over all ten development phases. Statically validated only.

* Phase 1 – foundation: generated wrappers, core libraries, G-buffer, validator.
* Phase 2 – lighting, LabPBR, shadows, atmosphere LUTs, moon, exposure, TAA.
* Phase 3 – stars, Milky Way, airglow; eclipse model fixes found by simulation (node drift,
  noon new moon, narrow syzygy slowdown).
* Phase 4 – water: wave spectrum, height-field simulation (CPU-tested), water shading,
  caustics.
* Phase 5 – volumetric clouds, cloud shadows, cirrus, weather state.
* Phase 6 – aurora, rainbows, wetness/puddles/ripples, lightning, height fog, light shafts.
* Phase 7 – End black hole (LUT and per-pixel geodesics), Nether smoke.
* Phase 8 – opaque SSR, coloured block light, SSAO, contact shadows.
* Phase 9 – Distant Horizons, Voxy, quality presets.
* Phase 10 – bloom, DOF, motion blur, grading, sharpening, documentation, packaging.

# Changelog

## 0.3.2-dev (branch shadows-sky-fixes, not yet tested in game)

* **Shadow swimming**: the radial distortion was centred on the camera, so every static
  point moved through the warp as the player walked and shadow edges crawled continuously. The
  map is now centred on a world anchor that re-centres only after moving Shadow Stabilisation
  blocks (default 4) across the light; between re-centres static shadows map to the same texels.
* **Bright line through the sun**: volumetric light treated samples outside the shadow map as
  fully lit; the map's side planes contain the light direction, so the lit/shadowed boundary
  showed as a line through the sun. Now faded over the map's outer edge.
* **Cirrus streaks / glare (Halcyon sky)**: Halcyon's cirrus layer at 3.2 km, stretched 3.3x
  along the wind, fanned into long streaks under perspective, and scattered pi times too much
  light around the sun. The Halcyon sky now uses Belgium's 8 km band-limited cirrus, driven by
  Cirrus Coverage and Cloud Movement Speed, with a new 22 deg ice halo (both sky sources).
* **Moon too bright**: Halcyon's night moon disk was ~530x moonlit ground and clipped white.
  The disk now has its physical (sunlit) radiance by day and 12x moonlit ground at night.
* **Bloom**: anti-firefly weighting now in exposed units (it did nothing at night), and bloom
  input is compressed around 64x white so the sun no longer floods the screen.
* Debug views 23 (bloom contribution) and 24 (before tone mapping, magenta > 4x white).
* **Rain ripples**: Halcyon's ripples ported as the default (Rain Ripple Source; Belgium's
  selectable). Belgium's re-dripped at fixed spots on a fixed beat and ignored rain intensity
  for drop count; Halcyon's drops appear at fresh random places, more in heavier rain, with a
  splash and a distance fade. Ripple Strength option.
* **Puddles** only on solid surfaces (not foliage, plants, sand, snow, ice, glass).
* Halcyon adapter no longer includes the atmosphere module itself (it could hide the LUT
  functions from programs that include it first).

## 0.3.1-dev (branch end-lighting-fixes, not yet tested in game)

Root causes from the first End and night screenshots (Iris 1.10.8, MC 1.21.11):

* **Setup programs never ran.** Iris loads setup programs as setup, setup1 ... setup99; the
  pack named them setup_a/_b/_c, so the multiple-scattering LUT, the DFG (split-sum) LUT and the
  black-hole geodesic LUT were never built in any dimension. Effects: the giant black disk in the
  End (the whole ~40 degree lensing region read an empty LUT), no ambient specular on any
  material (flat terrain, "LabPBR not working"), sky missing multiple scattering. Renamed
  setup1/setup2/setup3.
* **Water simulation never ran in the End**: its begin_b..e chain had no begin_a, and Iris stops
  at the first missing letter. The End now uses begin_a..d.
* validate.py checks compute program names against Iris's loader rules.
* **Exposure** metered black sky pixels at -23 stops, so space and starry views drove exposure to
  +9 EV and blew out terrain, fog, nebulae and planets. Sky pixels now weigh 0.3, samples are
  floored at 2^-20, and the End's exposure stays near a reference derived from its constant light.
* **End haze**: volumetric light used the Overworld's ground-fog model in the End (shafts, bright
  horizon band). The End now has one haze shared by fog and light shafts, with a dust albedo.
* **End sky**: nebulae rebuilt (domain-warped fBm, filaments, dust lanes that dim stars, emission
  palette); galaxies reduced from ~400 bright streaks to ~40 small bulge+disk galaxies.
* **Block light** tapers to zero over the last seven levels (it was ~9x moonlight at level 1 and
  then cut off, drawing hard-edged diamonds at night); shared by lightmap and hand light.
* **LabPBR normals**: the tangent frame now follows the face's real +U/+V directions (DirectX
  convention per the LabPBR spec), independent of the vertex tangent's handedness sign.
* tools/tests/render_end_nebula.py: offline preview of the End nebula.

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

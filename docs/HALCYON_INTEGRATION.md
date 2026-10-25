# Halcyon Integration

Halcyon's own feature code (the extract in `foldedapples/my-code-for-shaders---j`, with all
Glimmer code removed) is being ported onto the Belgium Shaders engine. Decisions taken with the
owner on 2026-10-24:

* **Base engine:** Belgium Shaders (independent G-buffer, PBR, shadows, atmosphere LUTs, TAA,
  bloom, DH/Voxy, compute infrastructure). No Glimmer code is restored.
* **Overlaps:** where both packs implement a feature, Halcyon's version is the default and
  Belgium's stays selectable in the menu.
* **Where:** branch `halcyon-integration` of this repository; `main` is untouched.

Status values: **ported** (imported, adapted, compiles in every variant; not yet seen in game)
· **pending** · **not planned** (with reason).

## Module status

| Halcyon feature | Files | Status | Switch |
|---|---|---|---|
| Real stars (Hipparcos + Yale BSC), NASA Milky Way | `atmosphere/sky/stars.glsl`, `starCatalog.bin`, `milkyway_4k/8k.png` | ported | Sky Source = Halcyon |
| NASA moon, phases, earthshine, solar/lunar eclipses | `atmosphere/sky/celestial.glsl`, `moon_2k/4k.png` | ported (also drives moonlight and eclipse lighting) | Sky Source |
| Aurora | `atmosphere/sky/aurora.glsl` | ported | Sky Source |
| Cirrus + 22° halo | `atmosphere/sky/cirrus.glsl` | replaced: its 3.2 km layer fanned into streaks in game; Belgium's 8 km layer with a new 22° halo is used, driven by Halcyon's Cirrus Coverage / Cloud Movement Speed | Sky Source |
| Rainbows | `atmosphere/sky/rainbow.glsl` | ported | Sky Source |
| Volumetric clouds, cloud shadows | `atmosphere/volumetricClouds.glsl`, `cloudNoise.bin` | ported: density, lighting and march inside Belgium's cloud passes; `cloudComposite`, `dc_volumetricClouds`, `prepare5` not needed (Belgium's passes do their job) | Cloud Source |
| End black hole, End ambient, End portal | `atmosphere/sky/blackHole.glsl`, `endAmbient.glsl` | pending | |
| Interactive water simulation | `water/waterSim.glsl`, `program/waterSim.glsl` | ported (prepare_a..d, Overworld) | Water Source |
| Ocean swells | from the `waveNormals.glsl` notes (assembled into `halcyon_waves.glsl`) | ported (added to Belgium's waves) | Water Source |
| Rain ripples | `water/rainRipples.glsl` | ported (water and puddles) | Rain Ripple Source |
| Caustics, underwater shafts | `water/caustics.glsl`, `underwaterShafts.glsl`, refraction helpers from the `waterFog.glsl` notes | ported (shafts use Belgium's water medium) | Water Source |
| Wetness / puddles | `water/wetnessSimple.glsl` | pending | |
| Opaque SSR (GGX) | `lighting/opaqueReflections.glsl`, `util/ggx.glsl` | pending | |
| SSGI | `program/d2_ssgiTrace.glsl`, `d3_ssgiTemporal.glsl`, `d4_ssgiApply.glsl` | pending | |
| Lava, Nether heat haze | `lighting/lava.glsl`, `post/heatHaze.glsl` | pending | |
| Depth of field | `program/c52_depthOfField.glsl` | pending | |
| Exposure/colour hooks, block-light colours | integration notes only | pending (re-expressed on Belgium's post chain) | |

## How the port works

* `tools/import_halcyon.py <extract>` copies the Halcyon modules **unchanged** into
  `shaders/lib/halcyon/` (same sub-paths) and Halcyon's textures into `shaders/textures/halcyon/`.
* GLSL has no namespaces. The tool computes every global name defined by both a Halcyon module and
  Belgium (functions, constants, structs, internal macros) and generates
  `lib/halcyon/hc_begin.glsl` (`#define name hc_name`) and `hc_end.glsl` (`#undef`). Halcyon
  modules are only ever included between the two, so neither engine redefines the other's names.
  Sky slice: `celestialAxis dist henyeyGreenstein lunarPenumbra lunarUmbra moonDiskRadiance
  nightSky solarCoverage solarLimbDarkening sunDiskRadiance surfaceWetness` renamed;
  `CIRRUS_ALTITUDE` (a Halcyon macro, a Belgium constant) undefined after the region.
* **Adapter** - what Glimmer used to provide, reimplemented on Belgium:
  * `lib/halcyon/adapter_core.glsl` (global, unique names): `clamp01 max0 pow2 pow3 rcp sincos`,
    interleaved gradient noise (Jimenez 2014), `hash33(vec3)` (Dave Hoskins, MIT - Halcyon's own
    helper), `hc_henyeyGreenstein(g, cosθ)` (Halcyon's argument order; Belgium's is the
    reverse), the Halcyon samplers, unit constants.
  * `lib/halcyon/adapter_region.glsl` (only inside the region): `worldSunDir`, `worldLightDir`,
    `sunlightColor`, `skylightColor`, `sunIrradiance`, `worldTimeCounter`, `biomeCanRainSmooth`,
    `fsh`, `WORLD_OVERWORLD`.
  * `perlinNoiseTex` is our own texture (`tools/gen_noise.py` → `textures/perlin2d.png`), matched
    to the statistics Halcyon's modules were tuned with (mean 0.5, σ 0.053, energy within a few
    percent per octave band of the original). Glimmer's file is not used.
* **Bridges** replace the Glimmer code that called the modules: `lib/halcyon/halcyon_sky.glsl`
  composes the sky in the order of Halcyon's `getSky()` (aurora → moon and night sky → cirrus →
  rainbow → sun → catalogue stars → Darkness) on Belgium's atmosphere, and exports Halcyon's
  celestial state to `begin_state` so the lighting follows the same moon and eclipses.

## Units

Belgium's light units: sun irradiance `SUN_IRRADIANCE` = 4.0, full moon 1/1500 of that. Glimmer's
sun irradiance was 0.126 and its moonlight luminance 0.00268, which equals Belgium's full-moon
irradiance (0.00267). Hence:

* Modules that take light as *input* (cirrus, rainbow) receive Belgium's values directly
  (`sunlightColor` = `fsLightColor`, `skylightColor` = sky irradiance / π, i.e. mean radiance).
* Night objects with built-in constants (stars, Milky Way, moon disk and glow, aurora) are scaled
  by `HC_NIGHT_SCALE` = Belgium full-moon irradiance / Glimmer moonlight ≈ 1.0, so they keep
  their Halcyon appearance under Belgium's night exposure.
* The sun disk uses `sunIrradiance` = Halcyon's solar tint × `SUN_IRRADIANCE`.

## Lighting coupling (Sky Source = Halcyon)

`begin_state` replaces Belgium's orbital model with Halcyon's: moon opposite the sun, phase from
`moonPhase`, eclipse coverage from `getEclipseState()`, Halcyon's angular sizes, moonlight =
full moon × `moonPhaseBrightness()` × `MOON_BRIGHTNESS` × `eclipseMoonlightFactor`, sunlight ×
(1 − solar coverage). Shadows, sky light, clouds and fog therefore follow the Halcyon sky.
Differences kept on purpose: the sky dome dims linearly with solar coverage (Belgium's
atmosphere LUT) instead of Halcyon's cubic curve; Glimmer's rain greying of the sky is not
repeated (Belgium's atmosphere already handles weather); Belgium's airglow stays in the sky.

## Options

Iris has one global namespace for options. Halcyon keeps its option names. Where Belgium used the
same name for something else, Belgium's option was renamed:

| Name | Resolution |
|---|---|
| `AURORA`, `STAR_TWINKLE` | shared toggles |
| `AURORA_BRIGHTNESS`, `MOON_BRIGHTNESS`, `RAINBOW_BRIGHTNESS` | shared multipliers (union of value lists) |
| `AURORA_FREQUENCY`, `MOON_SIZE`, `STAR_DENSITY`, `ECLIPSE_PREVIEW`, `SUN_SIZE` | Halcyon's meaning; Belgium's became `BE_*` (Belgium's `SUN_SIZE` was a diameter in degrees, Halcyon's a multiplier of the real sun) |
| Belgium sampler `milkyWayTex` | renamed `beMilkyWayTex` (Halcyon's Milky Way map keeps the name) |

The **Halcyon Sky** screen holds Halcyon's options and **Sky Source**; strings are Halcyon's,
including its Minecraft colour codes (the validator now accepts UTF-8 in `.lang` files).

## Remaining Glimmer dependencies of pending modules (from `tools/halcyon_deps.py`)

Real dependencies only (local-variable name matches removed):

| Module | Needs |
|---|---|
| `volumetricClouds.glsl` | `dualHenyeyGreenstein`, `CLOUD_EXTINCTION_COLOR`, `skyMultiplier`, `sunDir`/`lightDir` (view space), `sunlightColor`, `skylightColor`, `CLOUD_COVERAGE`/`CLOUD_DENSITY` (Belgium has options with these names - must be resolved) |
| `cloudComposite.glsl`, `dc_volumetricClouds.glsl`, `prepare5.glsl` | `screenSpaceToViewSpace`, colortex9/10 roles, DH depth, previous-frame matrices, `CLOUDS` |
| `blackHole.glsl`, `endAmbient.glsl` | `worldLightDir`, `perlinNoiseTex`, `luminance`, `pow2` |
| `waterSim.glsl` (lib + program) | `cameraPositionInt/Fract`, `relativeEyePosition`, `isEyeInWater`, `frameTime` (all Iris) |
| `caustics.glsl` | `WAVE_DEPTH`, `rotate`, `lightDir` |
| `underwaterShafts.glsl` | shadow-space helpers, `getCloudShadow`, `sunVisibilitySmooth`, `weatherSunlightColor` |
| `rainRipples.glsl` | `biomeCanRainSmooth` |
| `opaqueReflections.glsl` | Glimmer's `Material`, `fresnel`, `rayIntersects`, `mapSphere`, fog functions, `combinedProjection*` |
| `d2/d3/d4 SSGI` | `decodeNormal`, space conversions, colortex roles 11–14 |
| `heatHaze.glsl` | Glimmer's flood-fill voxel maps, `mapVoxelPosInterp` |
| `c52_depthOfField.glsl` | `vogelDiscSample`, space conversions |

## Provenance

The imported files are Halcyon's own code (classified OWNED_ORIGINAL in
`docs/HALCYON_PROVENANCE.md`, 0–3 % of lines found anywhere in Glimmer's history). No Glimmer code
or texture is included; the adapter is written from the interface description. Halcyon's asset
credits are kept in `shaders/textures/halcyon/CREDITS-night-sky.md` and `THIRD_PARTY_ASSETS.md`.

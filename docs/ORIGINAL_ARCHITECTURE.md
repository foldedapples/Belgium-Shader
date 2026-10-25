# Belgium Shaders — Original Architecture

This document is the design contract for the pack. Code in `shaders/` follows it; when they
disagree, the code is wrong or this document must be updated in the same commit.

## 0. Targets and conventions

* **Loader:** Iris ≥ 1.8 (compute + SSBO + custom images required). Iris ≥ 1.10.4 enables
  boat wakes and shallow-water detection; older Iris falls back to eye-in-water detection.
* **Minecraft:** 1.21.11 and the 26.x line supported by the same Iris branch. Only APIs found
  in Iris source are used (see `RENDERING_RESEARCH.md §2`).
* **GLSL:** `#version 430 compatibility` in every stage (Iris patches compatibility built-ins
  for core-profile Minecraft versions). GPU requirement: OpenGL 4.3.
* **Units:** 1 block = 1 m. Atmosphere quantities in km inside the atmosphere module only.
* **Spaces** (names used in code):
  * `view` — eye space (`gbufferModelView`).
  * `scene` — world-aligned axes, origin at the camera (`gbufferModelViewInverse * view`).
  * `world` — `scene + cameraPosition`; precision-sensitive code uses
    `cameraPositionInt/cameraPositionFract` instead.
  * `light` — our own orthographic light view (`fs.shadowView`), then `fs.shadowProj`, then
    radial distortion → shadow texture coordinates.
* **Directions:** +Y up, north = −Z (Minecraft convention).
* **Radiometry:** linear scene-referred RGB (Rec.709 primaries). The sun's top-of-atmosphere
  irradiance is `SUN_IRRADIANCE` scene units; all other light sources are defined relative to
  it. Exposure is applied only in `final`, so every intermediate buffer is absolute.

## 1. Frame pipeline (legal Iris order)

```
setup        setup.csh        transmittance LUT          (once per pipeline build)
             setup_a.csh      multiple-scattering LUT
             setup_b.csh      DFG (split-sum) LUT
             setup_c.csh      black-hole geodesic LUT    (End only)
begin        begin.csh        FrameState update: celestial model, eclipses, light choice,
                              shadow matrices, weather smoothing, water-sim control
             begin_a.csh      sky-view LUT + hemispherical sky irradiance
             begin_b..e.csh   water-simulation steps 0..3 (each no-ops if not scheduled)
shadow       shadow.vsh/fsh   custom light matrix + distortion; translucent tint; voxelization
shadowcomp   shadowcomp.csh   flood-fill coloured light propagation (one step per frame)
prepare      prepare.csh      cloud-shadow map
gbuffers     opaque programs  → G-buffer (colortex1-4)
deferred     deferred.fsh     volumetric clouds at reduced resolution  (scale.deferred)
             deferred1.fsh    cloud upsample + temporal reconstruction
             deferred2.fsh    SSGI trace, half resolution            (scale.deferred2, option SSGI)
             deferred3.fsh    SSGI bilateral + temporal filter, half res (scale.deferred3)
             deferred4.fsh    opaque lighting, sky, celestial, clouds, aerial perspective
dh_shadow    dh_shadow.vsh/fsh DH LODs into the shadow map (option LOD Shadows, off, untested)
gbuffers     translucents     water → colortex6 data; glass/particles/weather → colortex5
composite    composite.fsh    water shading, SSR, translucent overlay, underwater fog
             composite1.fsh   volumetric light (reduced res)          (scale.composite1)
             composite2.fsh   volumetric apply (depth-aware upsample) + Nether heat haze
             composite3.fsh   temporal anti-aliasing
             composite4.fsh   depth of field (optional)
             composite5.fsh   motion blur (optional)
             composite6.csh   exposure metering + adaptation
             composite7..15.csh bloom pyramid (5 down, 4 up)
final        final.fsh        exposure, bloom, tone curve, grade, sharpen, dither, debug views
```

Dimension folders: `world0` (Overworld and unknown dimensions), `world-1` (Nether), `world1`
(End). Every file in them is a generated wrapper (`tools/gen_wrappers.py`) that sets the stage
macro and dimension macro and includes one implementation from `shaders/program/`.

## 2. Buffers

### 2.1 Colour targets

| Buffer | Format | Contents | Producer → Consumer | Lifetime | Res | Cost @1440p |
|---|---|---|---|---|---|---|
| colortex0 | RGBA16F | HDR scene radiance | deferred4 → composites → final | frame | full | 29.5 MB |
| colortex1 | RGBA8 | albedo.rgb (sRGB-encoded), material id | gbuffers/dh/voxy → deferred4, composite | frame | full | 14.7 MB |
| colortex2 | RGBA16 | mapped normal (oct, rg), geometric normal (oct, ba) | gbuffers → deferred4, composite | frame | full | 29.5 MB |
| colortex3 | RGBA8 | LabPBR-like specular: smoothness, F0/metal code, porosity/SSS, emission | gbuffers → deferred4, composite | frame | full | 14.7 MB |
| colortex4 | RGBA8 | block light, sky light, AO, flags bitfield | gbuffers → deferred4, composite, TAA | frame | full | 14.7 MB |
| colortex5 | RGBA16F | premultiplied translucent colour, coverage | translucent gbuffers → composite | frame (clear 0) | full | 29.5 MB |
| colortex6 | RGBA16F | water: oct normal (rg), sky light (b), coverage (a) | gbuffers_water/dh_water/voxy → composite | frame (clear 0) | full | 29.5 MB |
| colortex7 | RGBA16F | TAA history (rgb), history confidence (a) | composite3 ↔ composite3 | persistent | full | 29.5 MB |
| colortex8 | RGBA16F | current clouds: in-scatter rgb, transmittance a | deferred → deferred1 | frame | ½ used | 29.5 MB |
| colortex9 | RGBA16F | cloud history | deferred1 ↔ deferred1, deferred4 | persistent | full | 29.5 MB |
| colortex10 | RGBA16F | volumetric in-scatter rgb, transmittance a | composite1 → composite2 | frame | ½ used | 29.5 MB |
| colortex11 | RGBA16F | debug channel (only allocated when a debug view references it) | any → final | frame | full | 29.5 MB |
| colortex12 | RGBA16F | raw SSGI irradiance correction rgb (signed), hit fraction a | deferred2 → deferred3 | frame (clear 0) | ½ used | 29.5 MB |
| colortex13 | RGBA16F | filtered SSGI irradiance correction rgb (signed), view distance a | deferred3 ↔ deferred3 → deferred4 | persistent | ½ used | 29.5 MB |
| colortex14 | R11F_G11F_B10F | sun/sky-lit diffuse radiance of opaque surfaces (bounce source) | deferred4 → next frame's deferred2 | persistent | full | 14.7 MB |

colortex6 `b` is the packed water record (`lib/water/water_record.glsl`): `(sky·16 + block + 1)/256`
for the vanilla lightmap levels, negated when composite must add analytic waves itself (Voxy
water, whose patch cannot read the pack's state).

SSGI traces against the current depth buffer and takes radiance from last frame's colortex14
(reprojected): only sun/sky-lit diffuse light, without block light or emission (the vanilla
lightmap already spreads those), water, fog or clouds. Each hit adds its radiance minus the
environment radiance it blocks, so the result is a signed correction that both adds coloured
bounce and darkens occluded sky light; deferred4 clamps the sum of environment light and
correction at zero. Multi-bounce builds up over frames. LOD, sky and hand pixels are skipped as
origins and as hits. With SSGI on, the analytic ground bounce is reduced to 40 %.

**Colour profiles** (`lib/post/color_profile.glsl`): `COLOR_PROFILE` selects a set of `CP_*`
constants (sun warmth, sky tint, shadow colour, block light, light/GI saturation, reflection,
water colour, cloud light, aurora, saturation, vibrance, contrast, tone curve). They are
applied where the quantity is produced (begin_state for sun/sky, floodfill for light chroma,
deferred4/composite for GI and reflections, grade/final for the image), not as a final filter.
Saturation changes use `cpSaturate`, which keeps luminance. Custom (4) maps each constant to a
menu option.

Reduced-resolution passes render into the lower-left corner of a full-size target using
Iris' `scale.<pass>` directive. This wastes allocation but keeps sampling simple; it is a
deliberate trade for correctness and is listed in `PERFORMANCE.md` as a later optimisation.

### 2.2 Custom images (`image.*`, max 16)

| Image | Format | Size | Producer → Consumer | Lifetime |
|---|---|---|---|---|
| transmittanceLut | RGBA16F | 256×64 | setup → everything lit by the sun | pipeline |
| multiScatterLut | RGBA16F | 32×32 | setup_a → begin_a | pipeline |
| dfgLut | RG16F | 64×64 | setup_b → deferred4, composite | pipeline |
| skyViewLut | RGBA16F | 192×216 (sun and moon panels) | begin_a → deferred4, composite, translucents | frame |
| waterSimA / waterSimB | RGBA16F (h_now, h_prev, ∂h/∂x, ∂h/∂z) | N×N (N = 256…2048) | begin_b..e ↔ ping-pong → gbuffers_water | persistent |
| cloudShadowMap | R16F | 256² / 512² / 1024² | prepare → deferred4, composite, composite1, translucents | frame |
| bloomAtlas | RGBA16F | 0.75×0.5 of screen | composite7..15 → final | frame |
| voxelMap | R32UI (cleared each frame) | 128×64×128 | shadow.vsh → shadowcomp | frame |
| lightVolA / lightVolB | RGBA16F | 128×64×128 | shadowcomp ping-pong → deferred4 | persistent |
| blackHoleLut | RGBA32F | 512×256 | setup_c → deferred4, composite (End) | pipeline |

### 2.3 Shader storage buffers

`binding 0 — FrameState` (`lib/core/frame_state.glsl`, 1024 bytes reserved), written by
`begin.csh` (celestial state, light choice and colour, sky irradiance, weather, cloud state and
wind offsets, aurora activity, shadow matrices) and `composite6.csh` (exposure, autofocus);
read by every other stage. Iris zero-fills it on creation; `fsHeader.x != FS_VERSION` means
uninitialised and readers fall back. The field list lives in that file only.

`binding 1 — WaterSimState` (`lib/water/water_sim_common.glsl`, 256 bytes), written by the
water control in `begin.csh`: window centres (current and previous), step parity and count,
clear/awake flags, accumulator and render alpha, idle timer, water-plane height, last player
and boat positions, per-frame source segments, pending splash impulse and delayed rebound.

## 3. G-buffer encoding

* Normals: octahedral encoding (Cigolle et al. 2014) into two unorm16 channels.
* `colortex3` uses the **LabPBR byte layout** so LabPBR data passes through untouched;
  vanilla materials synthesise equivalent bytes in `lib/material/labpbr.glsl`
  (`synthesizeSpecular`). Decoding is centralised in `decodeMaterial()`.
* Flags (`colortex4.a`, 8 bits): `1` hand, `2` entity, `4` foliage/SSS, `8` LOD terrain,
  `16` parallax-shadowed, `32` metal-from-albedo, `64` no-wetness, `128` unused.
* Material id (`colortex1.a`): a compact class index (0-255) derived from `block.properties`
  ranges (see `lib/material/material_ids.glsl`).

## 4. Celestial model and shadows

* **Sun:** direction taken from vanilla `sunPosition` transformed to scene space — keeps day
  length, `sunPathRotation` and time commands authoritative.
* **Moon:** elongation model. The moon's hour angle trails the sun's by an elongation `E(t)`
  that advances 2π per synodic period of 8 Minecraft days: full moon at midnight of
  `moonPhase 0` (vanilla-consistent), new moon at noon four days later (waning half 3.5
  days, waxing half 4.5) so conjunctions — solar eclipses — happen in daylight.
  Out-of-plane latitude `β = i·sin(u)`; the argument of latitude drifts against the month
  with period `ECLIPSE_CYCLE_DAYS + 2.5` (integer wrap `2C+5` days), so eclipse seasons
  alternate between new and full moons. A narrow `cos⁸` slowdown with a closed-form
  antiderivative makes the moon linger ±½ day around syzygy, so eclipses last minutes
  (artistic). Verified by `tools/tests/test_celestial.py` (6 solar, 22 lunar eclipses in 392
  days at defaults).
* **Phase illumination** follows from geometry: the moon sphere is shaded with the real sun
  direction (Lommel–Seeliger + Lambert mix), so the terminator is never painted.
* **Lunar eclipse:** per-pixel umbra/penumbra test on the moon disk; umbral light is the sun
  filtered by the transmittance LUT at grazing incidence (gives the red tint physically).
* **Solar eclipse:** analytic circle–circle overlap with limb darkening weight scales sun
  irradiance, which darkens sky LUT, clouds and terrain consistently; corona appears near
  totality; star visibility follows from sky luminance.
* **Shadow light:** sun when above −3°, else moon when above −3°, else none (ambient only).
  End: the black hole direction. Nether: none.
* **Shadow matrix:** built in `begin.csh` (orthographic, light-aligned, centre snapped to
  shadow-texel increments to eliminate swimming). `shadow.vsh` uses it instead of Iris'
  matrix; `shadow.culling = false` is required so Iris' culling does not depend on its own
  light direction.
* **Distortion:** `p' = p·(1+k)/(|p|+k)` (hyperbolic radial), depth unscaled. Texel world size
  at any point is known analytically, which drives normal-offset bias.
* **Filtering tiers:** hard (1 tap HW compare), PCF Vogel-disk (8/16/32), PCF + blocker search
  (variable penumbra). Coloured translucency from `shadowtex0` vs `shadowtex1` and
  `shadowcolor0`; water flagged in `shadowcolor1` drives caustics and underwater attenuation.
  Screen-space contact shadows at HIGH+.

## 5. Lighting model (`lib/lighting/`)

* Direct: GGX NDF, height-correlated Smith visibility, Schlick Fresnel for dielectrics, exact
  conductor Fresnel (complex IOR) for LabPBR hardcoded metals, albedo-as-F0 for code 255.
  Diffuse: Lambert scaled by `(1 − F)` and `(1 − metal)`.
* Image-based ambient: hemispherical sky irradiance (from sky-view LUT, recomputed per frame)
  × sky-lightmap visibility curve × AO; specular ambient via sky-view LUT + DFG LUT.
* Block light: lightmap-driven inverse-square-like falloff, 2800 K blackbody default colour;
  replaced by the flood-fill light volume where available (coloured, directional bias).
* Emission: LabPBR alpha (or id-driven defaults) in absolute units.
* Subsurface: foliage and LabPBR SSS use a wrapped back-light term attenuated by the
  shadow-map thickness estimate.
* Energy: no term may exceed its BRDF bound; all branches guard divisions and `normalize()`.

## 6. Sky and atmosphere (`lib/atmosphere/`)

* Planet radius 6360 km, top 6460 km. Rayleigh scale height 8 km, Mie 1.2 km, ozone layer
  (tent at 25 km) — standard physical values.
* Transmittance LUT (Bruneton height/angle parameterisation), multiple-scattering LUT
  (isotropic second-order approximation per Hillaire 2020), sky-view LUT (non-linear
  elevation mapping to concentrate texels near the horizon) — all written from scratch.
* Aerial perspective: per-pixel optical depth of a scaled exponential atmosphere along the
  view segment, in-scatter = sky-view radiance × (1 − T). `AERIAL_DISTANCE_SCALE` compensates
  for Minecraft's short view distances (artistic).
* Weather fog, morning fog, cave darkening and the Nether/End atmospheres live in
  `lib/atmosphere/fog.glsl` with explicit per-dimension paths.

## 7. Clouds (`lib/clouds/`)

* Single march through a type-aware slab: weather map (coverage, type, local base offset)
  → height profile by type (stratus, stratocumulus, cumulus, cumulonimbus with anvil)
  → 3-D shape noise (generated offline, our own Perlin-Worley) → detail erosion.
* Cirrus/cirrostratus as a 2-D high layer with streak noise (no volume cost).
* Lighting: Beer–Lambert with exponentially spaced light steps, dual-lobe HG phase, 3 octaves
  of multiple scattering, powder term for dark edges, height-graded ambient, lightning point
  light from `lightningBoltPosition`.
* Cost control: reduced resolution, per-frame jittered start, adaptive step count from slab
  path length, coarse-density empty-space skipping, early exit at T < 0.01, fewer light steps
  for distant samples.
* Reconstruction: bilateral (depth-aware) upsample, reprojection assuming the cloud layer's
  mid-altitude intersection, neighbourhood clamp, history confidence; rejected when camera
  enters the slab.
* Cloud shadow map: 2-D transmittance along the light through the coarse density field,
  camera-centred, texel-snapped.

## 8. Water (`lib/water/`)

### 8.1 Layer A — analytic waves
Sum of directional trochoidal (Gerstner-type) components with deep-water dispersion
`ω = √(g·k)`; amplitudes from a wind-speed-dependent spectrum shaped per band, directions
spread around `WIND_DIRECTION`. Normals are evaluated analytically; components finer than
the pixel footprint fade out (anti-shimmer). Open ocean vs inland water scaling uses a
smoothed biome uniform and sky exposure.

### 8.2 Layer B — local height-field simulation (our own scheme)
* Domain: N×N cells, `CPB` cells per block, centred on the player, addressed toroidally by
  integer world cell (`cell & (N−1)`), so moving the window never copies data. Cells entering
  the window are zeroed on the first step after a move.
* Equation: damped Klein–Gordon wave equation with Kelvin–Voigt viscosity
  `∂²h/∂t² = c²∇²h − Ω²h + ν∇²(∂h/∂t) − γ∂h/∂t + f`. The restoring term (gravity analogue)
  gives a finite dip `F/Ω²` under a steady pressure instead of the unbounded hole of the bare
  2-D wave equation, and makes ripples dispersive. Leapfrog (Verlet) over two time levels in
  one RGBA16F texel (`h_now`, `h_prev`, plus the gradient for smooth rendering), Oono–Puri
  isotropic 9-point Laplacian, sponge layer near the window edge. CPU reference tests:
  stability at every quality setting, splash volume conserved to 1e-9, round ripples, sponge
  absorbs 83 % of reflections, V-shaped boat wake, world-anchored scrolling.
* Stability: fixed `dt = 1/SIM_HZ`, Courant number `c·dt/Δx` clamped ≤ 0.6 at compile time,
  viscous number ≤ 0.12, accumulator capped at 4 steps/frame (excess time discarded),
  amplitude limiter and NaN/Inf reset.
* Sources (only those the platform exposes): the player (swimming force, entry splash as a
  mass-conserving Laplacian-of-Gaussian impulse, exit splash, idle bobbing) and the player's
  boat (elliptical pressure footprint swept along its path between sub-steps, bow surge,
  stationary bobbing). Positions are interpolated per sub-step.
* Lifecycle: teleport (> 24 blocks/frame) or dimension change → cold reset; idle 30 s →
  sleep (no dispatch work beyond an early-out); sim plane height tracks the player's water
  surface; water surfaces > 2 blocks from that plane ignore the sim.
* Rendering: bilinear height taps → central-difference gradient, temporally interpolated
  between the last two steps with the accumulator fraction.

### 8.3 Shading
Composite pass: Fresnel (Schlick, n = 1.333), SSR with rough fallback to sky-view LUT
(occluded by sky lightmap), refraction offset limited and re-validated against depth,
Beer–Lambert absorption + in-scatter by water depth, caustics from the analytic wave Hessian
on surfaces under water (via shadow-map water flag), underwater fog and shafts, Snell's window
and total internal reflection from below.

## 9. Night sky, aurora, End, Nether
* Stars: procedural cube-face cells in a celestial frame that rotates with the sun's diurnal
  axis; magnitude drawn from a power-law, colour from Planck evaluated at three wavelengths;
  analytic Gaussian PSF (stable under motion), extinction from the transmittance LUT, mild
  horizon scintillation.
* Milky Way: procedural galactic band (fixed galactic pole), dust lanes, bulge toward the
  galactic centre; no texture dependency.
* Aurora: raymarched emission layer 100–300 km; curtains are distance fields to slowly
  deforming procedural curves; altitude-dependent spectrum (green 557.7 nm low, red 630 nm
  high, occasional N₂⁺ blue/violet fringe); nightly activity from a deterministic per-day hash.
* End black hole: Schwarzschild null geodesics precomputed into a LUT `r(b, φ)` in `setup_c`;
  per-pixel lensing and disk crossings become texture lookups. Performance: primary disk image
  only; High: primary + secondary image; Cinematic: direct per-pixel integration. Disk
  temperature from a thin-disk profile, observed colour with relativistic Doppler and
  gravitational shift. The disk also acts as the End's shadow-casting light. With Black Hole
  Drift the hole wanders up to 18° in azimuth and 5° in elevation (periods dividing the 3600 s
  wrap of `frameTimeCounter`, so the motion is continuous).
* End planets (`lib/end/planets.glsl`): three analytic spheres between the observer and the
  hole, lit by it (phases follow from geometry), rotating procedural surfaces (bands and a
  storm, craters, ice caps), a ringed gas giant with the planet's shadow on the ring, front-to-
  back compositing. Drawn unlensed over the lensed sky, on sky pixels only. Geometry preview and
  invariants: `tools/tests/render_end_planets.py`.
* Nether: dense coloured height fog from `fogColor`, procedural smoke, lava glow ambient,
  heat haze in composite2 (screen offset scaled by distance and temperature proxy).

## 10. Post (`lib/post/`)
Temporal AA (Halton 2,3 jitter, closest-depth motion, YCoCg variance clip), compute bloom
pyramid with firefly-safe first level, auto exposure (centre-weighted log average, separate
up/down adaptation rates), our own luminance-preserving filmic curve with highlight
desaturation, white balance, contrast, vibrance, contrast-adaptive sharpening, ordered
dither. HDR display output is **not** implemented (Iris provides no HDR swap chain).

## 11. Compatibility layers (`lib/compat/`)
* DH: `dh_terrain`/`dh_water` write the same G-buffer; lighting reconstructs position from
  `dhDepthTex` with `dhProjectionInverse`; near-field DH fragments are discarded with a
  dithered band to avoid overlap; no shadow-map shadows on LODs (cloud shadows + sky-light
  shadow approximation instead).
* Voxy: `voxy.json` v1 + `voxy_opaque.glsl` / `voxy_translucent.glsl` implementing
  `voxy_emitFragment`; normals from the face index; depth from `vxDepthTexOpaque` with
  `vxProjInv`.
* When neither mod is present the LOD code is compiled out.

## 12. Settings and presets
All options are `#define`s in `lib/core/settings.glsl` with ranges in comments (Iris option
syntax). Presets are `profile.*` lines in `shaders.properties`. `tools/validate.py` fails if
an option is not reachable from the menu, has no language string, or a preset references an
unknown option.

## 13. Validation
`tools/validate.py` expands Iris includes and option defines, injects Iris standard macros, and
compiles every program of every dimension with Khronos glslang for each preset profile, colour
profile, DH, Voxy, and several Minecraft/Iris version environments (Iris 1.6.14 without the
optional emission feature, pre-1.10.4 Iris, MC 1.20.1 … 26.3). This catches compile errors offline; it cannot replace in-game testing.

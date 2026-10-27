# Reference-pack research

This page records how three well-known Iris packs approach the effects this pack implements.
The studies were done on 2026-10-26 by reading their public source. Nothing was copied: no GLSL,
constants, lookup tables, noise textures or settings files. The comparisons describe techniques
in our own words, and every change made to this pack is independently written (see
[REGRESSION_AUDIT.md](REGRESSION_AUDIT.md) and the commit history). Anything marked *inference*
is our reading of the code, not something the source states.

## Licences: what we may and may not reuse

| Pack | Source | Licence (summary) | Consequence for us |
|---|---|---|---|
| Complementary Reimagined / Unbound | `ComplementaryDevelopment/ComplementaryReimagined` (r5.9.2) | Complementary License Agreement 1.7. Free for normal use. A modified pack may be shared only under strict conditions: it must keep their licence, must not use their name, and must contain substantial new code. Everything else is all rights reserved | Copying any code would make this pack a "Modified Pack" under their terms. Techniques only |
| Bliss | `X0nk/Bliss-Shader` (Stable) | `LICENSE.md`: "© 2020 Chocapic13. All rights reserved." No grant. Bliss is an edit of Chocapic13 | No code reuse at all |
| Eclipse | `Merlin1809/Eclipse-Shader` (Unstable) | Same licence line; "a Bliss edit". Also contains third-party snippets under their own terms: Photon curl noise, Shadertoy-derived ripples and wave simulation (Shadertoy's default is CC BY-NC-SA), Physics Mod ocean (public domain), afl_ext waves | No code reuse; even the third-party parts carry non-commercial or unclear terms |

## Complementary (Reimagined and Unbound)

Reimagined and Unbound are one codebase. A single style option changes only the defaults: water
style, cloud style, aurora, sun/moon look and the sun-path tilt. Lighting is **forward**: opaque
geometry is shaded in the gbuffers programs. Deferred and composite passes add SSAO, sky, clouds,
fog, reflections, refraction, light shafts, TAA, bloom and the tone map.

| Feature | Technique (their approach, in our words) | Cost / limitation | Ours, and the decision |
|---|---|---|---|
| Water normals | Unbound: several octaves of a scrolling tiling normal texture, a short height-based parallax step, waves reduced in covered water (sky light) and at grazing angles. Reimagined: vanilla texture, pixel-snapped motion | Cheap; repeats at texture scale | Analytic wave trains with deep-water dispersion and a steepness budget, plus advected gradient noise (`lib/water/waves.glsl`). No texture tiling. Keep ours |
| Water depth look | Thickness from opaque depth → exponential fog that also raises alpha | Single tap | Beer–Lambert absorption plus in-scatter over the refracted path in a composite pass. Equivalent idea, physically parameterised |
| Refraction | One offset tap from world-space noise, rejected if the offset pixel is not water | Approximate | Refraction from the actual normal (Snell), validated against depth (`composite/translucent.fsh`) |
| Caustics | Written into the water's shadow-colour in the shadow pass | Nearly free | Analytic caustics from the wave field at the receiver (`lib/water/caustics.glsl`) |
| Integrated PBR | `block.properties` IDs → a branch tree of per-block rules deriving smoothness, F0 and emission from vanilla albedo | Large branch tree, very effective on vanilla textures | Same idea, smaller: `lib/material/fallback.glsl` writes LabPBR-encoded values for vanilla blocks |
| LabPBR | Reads normals, height (POM), smoothness, F0 / metals, emission with a mip-0 min to avoid mip bleeding. *Inference:* porosity/SSS and normal-map AO appear unused | — | Full 1.3 decode including porosity, SSS and AO. Predefined-metal tint now applied (fixed 2026-10-26). **Candidate:** the mip-0 minimum for emission |
| Reflections | View-space ray march with growing steps and refinement, roughness-driven mip, edge fade. Sky fallback scaled by sky light, optional clouds in reflections. Optional world-space reflections from the voxel volume | World-space reflections only at top profiles | Screen-space march with 1/z interpolation, binary refinement, GGX-sampled rough reflections integrated by TAA, sky fallback scaled by sky light |
| Clouds | Reimagined: blocky rounded-cell slab from a 2D map. Unbound: fractal 3D value-noise slab, front-to-back with early exit, height-based shading plus a forward-scatter lobe | Cheap; not physically lit | Volumetric shell with weather map, per-type height profiles, light march, octave multiple scattering and temporal reconstruction. More expensive, physically lit |
| Shadows | Radial distortion; rotated-disk PCF (2–16 taps by level); normal-offset bias growing with distance; sample pulled to the block centre where sky light/AO is low (leak control); shadow fades to a lightmap estimate at the edge | One map; resolution varies across the screen | 4 snapped cascades with PCSS. Our leak control is the sky-light gate on direct light. **Candidate:** the AO-aware centre pull for cave leaks |
| Puddles / wetness | Upward faces with high sky light and low block light; thresholded 3-octave noise grown by wetness; smoother and more reflective with rippled normals. Optional column test against glass roofs from the shadow pass | Off below the highest profiles | Same placement inputs plus LabPBR porosity and height; procedural ring ripples (now precision-exact). **Candidate:** the glass-roof column test |
| Tone map / grade | Modified Lottes 2016 curve, a lift of very dark values, a path to white, then pre-tone-map channel mixing and post-tone-map saturation/vibrance | — | Own hue-preserving Naka–Rushton curve, Khronos Neutral option; midtone contrast that keeps black fixed |
| Presets / menu | 8 profiles, each setting ~15 cost options. A "detail quality" meta-switch gates groups of features. Cost options sit in one Performance screen, art options on topic screens; labels colour-coded by cost | — | 5 profiles setting the step and resolution options, which are gathered on the Quality screen. Toggles stay on topic screens |

Philosophy: Reimagined keeps vanilla's visual language and Unbound aims at realism, on the same
expensive core (shadows, SSR, TAA, integrated PBR). Both prefer cheap tricks (lightmap-based leak
fixes, single-tap refraction, caustics in the shadow pass, dither plus TAA) over brute force, and
degrade feature by feature as the profile drops.

## Eclipse and Bliss

Eclipse is built on Bliss, so they share most structure. Both keep their programs in
`shaders/dimensions/` and compute the sky, light colours and (in Eclipse) a weather "scene
controller" in early passes, shared through SSBOs. Files examined: `lib/volumetricClouds.glsl`,
`lib/ROBOBO_sky.glsl`, `lib/Shadows.glsl`, `lib/Shadow_Params.glsl`, `lib/waterBump.glsl`,
`lib/specular.glsl`, `lib/lightning_stuff.glsl`, `lib/ripples.glsl` (Eclipse), the `dimensions/`
composite, deferred and prepare programs, `shadowcomp.csh` and `begin.csh`.

| Feature | Bliss | Eclipse | Ours, and the decision |
|---|---|---|---|
| Cloud layers | Two thin (100-block) cumulus slabs plus a flat altostratus plane; draw order flips with camera height | Small and large cumulus, altostratus, a cirrus layer, and optional distant cumulonimbus with anvil tops | One shell (base to 2.2 km, storms to 9 km) whose per-column type (stratus to Cb) comes from a weather map, plus separate cirrus. Keep: continuous transitions between types |
| Cloud density | 2D coverage noise; pseudo-3D erosion from one 2D texture; coverage-weighted erosion (Schneider/Nubis style); height-dependent shear | Same, plus rounded bases and tops, per-layer scale, and a dithered density threshold before lighting | 3D Perlin-Worley shape plus Worley erosion (billowy low, wispy high) and per-type height profiles. Shear fixed this session to a bounded lean |
| Cloud lighting | 3 light steps; summed HG lobes; a softer multi-scatter term multiplied by a powder term; ambient from a vertical gradient | Selectable phase (HG, Cornette-Shanks, **HG-Draine**, Jendersie & d'Eon 2023); forward anisotropy falls as density rises; optional terrain-shadowed clouds | Light march (4-9 steps), dual-lobe HG, octave multiple scattering (Wrenninge 2013). **Candidates:** HG-Draine and density-dependent anisotropy, from the published papers |
| Cloud temporal | No cloud history; relies on dither plus the main TAA | Dedicated cloud/fog history: camera reprojection, 3x3 clamp, reset when alpha jumps, edge-aware upsampling | Dedicated history with variance clipping, now also reprojected through the clouds' own wind motion |
| Cloud shadows | One coverage-only sample per layer projected along the sun | Same for all layers, plus a low-sun planet shadow | A 256² optical-depth map with a snapped centre. Better quality at similar cost |
| Sky | Single-scattering march (10 view and 4 light steps) into one sky-view LUT, with a faked multiple-scattering ambient | Same model, computed earlier (prepare/begin) | Transmittance, multiple-scattering and sky-view LUTs (Hillaire 2020 style). Keep |
| Shadows | One distorted map, no cascades, no explicit snapping; reduced-resolution blocker search plus 13-tap PCF; normal-offset bias; block-centre snap where sky light is low (credited to Complementary) | Same filter; bias in projected space; can build its own shadow matrix (custom moon orbit, lightning, the End) | 4 cascades snapped about a near-player anchor (fixed this session), PCSS. Avoids the blur at range of a single map |
| Water waves | Height field from 3 rotated noise-texture lookups and a large-wave mask; normals by finite differences whose step **grows with distance** (cheap anti-aliasing) | Same, plus parallax and slope flow | Analytic dispersive trains. **Adopted idea:** distance-aware filtering, as a per-frequency footprint prefilter with roughness transfer (below) |
| Player interaction | None | Compute wave equation on a ping-pong image that scrolls with the player; capped update rate; sleeps when idle | Toroidal world-anchored grid, fixed 60 Hz steps, mass-conserving disturbances, shore reflection. Wake race fixed this session |
| Rain ripples | None | Hashed-cell expanding rings (Shadertoy-derived) within 35 blocks | Our own two-layer hashed-cell rings, now precision-exact and footprint-filtered |
| Puddles / wetness | Noise mask x sky light >= 0.9 x up-facing x rain x biome; porosity darkening | Moved to deferred; drip streaks on walls; separate wetness and puddle modes | Same placement idea plus LabPBR height; porosity-aware wetness. **Candidate:** drip streaks on vertical faces |
| Reflections | One VNDF-sampled ray (Heitz 2018), linear march against quarter-resolution depth, previous-frame colour on hit, sky-plus-clouds LUT fallback | Also marches DH/Voxy depth; optional voxel DDA reflections | GGX-sampled march with binary refinement on full depth, sky fallback (double-counted sun fixed this session). **Candidate:** VNDF sampling |
| Coloured light | Flood-fill light volume (off by default) | On from High; hand-light shadows | Flood-fill volume gated by vanilla light, so it doesn't leak |
| TAA | 8-sample jitter, nearest-depth velocity, Catmull-Rom history, clamp, blending in tonemapped space | Same, plus the separate cloud/fog filter | Equivalent design. Jittered reconstruction fixed this session |
| DH | Mixed vanilla+DH depth, overdraw discard inside vanilla range, DH projections for reprojection | Adds Voxy, a dithered vanilla fade at `far`, DH SSR | Shared G-buffer with an LOD flag, discard inside 0.8 x far, per-source projections |
| Presets | None (sliders only) | Potato to Ultra | Low to Cinematic, with cost options on one Quality screen |
| Tone map | Minimal AgX (default) and alternatives | Retuned AgX | Own hue-preserving curve. **Candidate:** an AgX option written from the published description |

What makes their clouds convincing: cheap coverage plus erosion, height shear, light reaching
lower layers through upper ones, a strong forward lobe with a softer multi-scatter term, powder
darkening, and haze into the sky colour. Their water convinces less through wave shape than
through distance-aware normals, caustics from the same field, and sky-lit reflections.

## Changes made in this pack after the research

Each was found while comparing our implementation against the problems these packs solve. All
are our own code:

* Interactive water: removed a read/write race on the body history (wakes missing in tiles).
* Rain ripples: integer-camera, period-wrapped coordinates (exact at any distance).
* Wave trains: frequencies on an hourly lattice (no pop when `frameTimeCounter` wraps).
* LabPBR: predefined-metal albedo tint; built-in metals encoded as albedo-F0.
* Water: a per-frequency footprint prefilter, exp(-k²f²/24) for a Gaussian matched to a box
  pixel, with the removed slope variance moved into the glint and reflection roughness
  (`tools/tests/test_wave_filter.py`: never worse than unfiltered, and 7x closer to the true pixel
  average where aliasing starts). Inspired by the reference packs' distance-aware normals; the
  formulation is ours.

## Candidates not yet implemented

Each would be written from the published paper, not from reference code: HG-Draine cloud phase
(Jendersie & d'Eon 2023), density-dependent cloud anisotropy, VNDF reflection sampling (Heitz
2018), drip streaks on wet walls, an AO-aware block-centre pull against cave light leaks, a
glass-roof puddle mask, and an AgX tone-map option.

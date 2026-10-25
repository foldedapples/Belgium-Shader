# Feature Status

Every entry is one of:

* **Implemented** – code exists, compiles for every preset/option variant (`tools/validate.py`),
  and any algorithm with a CPU reference passes its test in `tools/tests/`.
* **Partial** – implemented with a documented limitation.
* **Not implemented** – not in the pack; listed so nothing is silently missing.

**No feature has been verified inside Minecraft yet.** Development so far had no game
runtime; all validation is static (compiler + reference simulations). The in-game test plan is
`docs/TESTING.md`. Until that plan has been run, treat visual quality and performance as
unverified.

| Area | Status | Notes |
|---|---|---|
| Pipeline foundation, generated wrappers, G-buffer | Implemented | 248 program files incl. Voxy harnesses; 105 option/version variants compile. |
| LabPBR 1.3 decoding (normals, smoothness, F0, IOR metals 230–237, albedo metals, porosity, SSS, emission, AO) | Implemented | Height drives parallax occlusion mapping on terrain (no self-shadowing, no depth offset). |
| Vanilla material defaults | Implemented | Conservative: only glass/ice/water/polished/metal/foliage/emitter classes differ. |
| GGX / Smith / exact Fresnel, DFG LUT with energy compensation | Implemented | |
| Sun and moon light, light colour through the atmosphere | Implemented | |
| Custom shadow matrix, distortion, texel snapping, 5 filter tiers, coloured translucent shadows | Implemented | Requires `shadow.culling = false` (set). |
| Contact shadows, SSAO | Implemented | Screen-space; off on LOD terrain and the hand. |
| Subsurface scattering (foliage, LabPBR SSS) | Implemented | Thickness from the shadow map. |
| Coloured block light (voxel flood fill) | Implemented | Colour only; intensity from vanilla lightmap (no leaking past vanilla light). 128×64×128 blocks around the player. |
| Screen-space GI (indirect diffuse) | Implemented | Half-res cosine rays against depth; bounces last frame's sun/sky-lit diffuse radiance (multi-bounce over time) and occludes sky light; bilateral + clamped temporal filter. Block light is not re-bounced (the lightmap covers it). Screen-space only: off-screen and LOD geometry contribute nothing. Off on LOW. |
| Dynamic hand light (coloured by held item) | Partial | Both hands; colour from `item.properties` emitter classes. Not occluded: it reaches through walls up to its light level in blocks. |
| Block-light specular | Implemented | Direction from the light-volume gradient; needs coloured lighting. Approximate (one dominant direction per point). |
| Colour profiles Natural / Vibrant (default) / Cinematic / Fantasy / Custom | Implemented | Applied at the source of each quantity; Custom exposes 13 controls. Look not yet judged in game. |
| Version fallbacks (Iris 1.6 camera position, no emission attribute, no vehicle uniforms) | Implemented | Compile-checked per version environment; see COMPATIBILITY.md. |
| Atmosphere (transmittance, multiple scattering, sky-view LUTs), aerial perspective | Implemented | |
| Sun disk (limb darkening), corona at totality | Implemented | |
| Moon: NASA LROC colour (2K/4K/8K mip atlases), LOLA relief normals, phases from geometry, earthshine | Implemented | 8K uses 4K normals (the DEM is 5760 px wide). |
| Solar and lunar eclipses from an orbital model; preview option | Implemented | Simulated in `tools/tests/test_celestial.py`. Totality is rare at default sizes (as in reality). |
| Stars, Milky Way, airglow | Implemented | Procedural stars; Milky Way from NASA SVS 4851 / Gaia DR2 (CC BY-NC 3.0 IGO, see THIRD_PARTY_ASSETS) or procedural; airglow at real night-sky brightness. |
| TAA on Voxy terrain | Not implemented | Voxy supports a `voxy_taa.glsl` jitter hook; not added because the TAA on/off state cannot be verified inside Voxy's shader without testing. Voxy LODs are not jittered (edges stay aliased; no ghosting). |
| Aurora | Implemented | |
| Rainbows (primary/secondary from dispersion) | Implemented | |
| Volumetric clouds (all types, weather, shadows, temporal reconstruction), cirrus | Implemented | |
| Lightning illumination (terrain + clouds) | Implemented | Uses the single active bolt Iris exposes. |
| Wetness, puddles, rain ripples | Implemented | |
| Morning mist, rain haze, volumetric light shafts (air and underwater) | Implemented | |
| Ocean waves (analytic spectrum) | Implemented | Normals only; the water mesh is not displaced (shoreline gaps avoided). |
| Interactive water simulation (player, splashes, boat wakes) | Implemented | Sources limited to the local player and their boat (platform limit). Simulated in `tools/tests/test_water_sim.py`. Single water plane near the player. Rendered slopes lag heights by one 1/60 s step. |
| Water shading: refraction, absorption, SSR, Fresnel, glint, caustics, underwater fog, Snell's window | Implemented | Translucents *behind* water are overlaid unrefracted (single translucent layer). |
| Opaque SSR (smooth, metal, wet) | Implemented | Screen-space only; off-screen falls back to the sky. Not used when the camera is under water (environment specular instead). |
| End black hole (LUT lensing, disk, Doppler, photon ring, lensed background) | Implemented | Verified integrator in `tools/tests/test_black_hole.py`. |
| End lighting from the disk | Implemented | Shadows cast from the black hole's direction; follows Black Hole Drift. |
| End planets (ringed gas giant, rocky, ice; orbits, spin, phases, ring shadow) | Implemented | Geometry checked offline (`tools/tests/render_end_planets.py`); not lensed (in front of the hole). |
| Nether haze, smoke, heat haze, lava bounce | Implemented | |
| TAA, auto exposure, bloom, filmic curve, grading, sharpening, DOF, motion blur, vignette | Implemented | DOF / motion blur / vignette are off by default. |
| HDR display output | Not implemented | Iris offers no HDR swap chain to packs. |
| Distant Horizons | Implemented, untested | G-buffer, water, fog, clouds, TAA; per-block albedo variation. SSR, puddles, SSAO, SSGI off on LODs. |
| DH shadows (`dh_shadow`, LOD Shadows option) | Partial, experimental | Off by default; untested. Only LODs inside the shadow distance are covered. |
| Voxy | Implemented, untested | Depth convention assumed standard (see COMPATIBILITY.md). Water gets analytic waves in composite. |
| Quality presets LOW…CINEMATIC | Implemented | Values are estimates until profiled (PERFORMANCE.md). |
| Debug views (22) | Implemented | `docs/DEBUGGING.md`. |
| Parallax occlusion mapping | Implemented | Terrain only; tile-wrapped; distance-limited. |
| Waving foliage | Implemented | Same displacement in gbuffer and shadow passes. |
| Water vertex displacement | Not implemented | Waves are normal-only to avoid shoreline gaps. |
| Entity/mob interaction with water, other players' wakes | Not possible | Iris does not expose other entities' positions to shaders. |
| ColorWheel / Physics Mod / Photonics integration | Not implemented | |

## Review log

* 2026-10-24 - independent code review of the highest-risk passes found 12 runtime-logic
  issues. Fixed: bloom upsample dispatch sizes; opaque SSR not attenuated by fog/clouds in
  front; SSR-eligible surfaces losing all specular under water; SSR fallback in the End and
  Nether; water attenuation/caustics depending on the coloured-shadows option; double
  atmosphere on water; overcast double-counting without cloud shadows; black-hole metadata
  blending across the capture boundary; underwater sun share ignoring occlusion; stale water
  plane after teleporting into water; LOD-vs-vanilla depth comparisons; bloom atlas size.
  Also found while fixing: End terrain received no sky ambient (no sky light data there), and
  deferred applied air fog with the camera under water. Documented, not changed: simulated
  slopes lag heights by one step.
* 2026-10-24 - second review (expansion code), 15 findings. Fixed: SSGI re-bounced block light
  and emission, took radiance after water/fog, never darkened occluded sky, accepted hand hits,
  and had an unclamped history, an infinite sky distance in fp16 and an upsample that always
  renormalised; block/hand light counted twice in Nether/End specular; block highlights doubled
  on SSR surfaces; hand-light specular had a double cosine; the reflection profile scale was not
  capped; the water profile changed clarity; `cpSaturate` raised luminance; the water lightmap
  record was quantised to 16 levels (now 32); DH shadow casters overlapped vanilla chunks.
  Documented, not changed: the hand light is not occluded.
* 2026-10-24 - first in-game run (MC 1.21.11, Iris 1.10.8, Sodium 0.8.12, Voxy 0.2.16-beta,
  RTX 5070 Ti, HIGH). Load failures fixed: trailing comment on an `#include`, non-literal
  `workGroups`, a function name Iris injects, boolean options without `#ifdef` references
  (validator now enforces all four). Visual bugs from the user's screenshots, root causes
  traced in code:
  - Dotted white streak toward the sun: cirrus noise minified ~20x without mipmaps, then
    thresholded and lit by the ice phase function. Octaves now fade by pixel footprint.
  - Stacked/banded cumulus: ~140 m march steps at low elevation and no step-back after
    skipping clear air (front error up to 206 m, sometimes 1 sample per cloud; CPU test).
    Two-rate march: <= 47 m front error, >= 6 samples (tools/tests/test_cloud_march.py).
  - Black Voxy terrain at night, dark shaded LOD sides by day: Voxy writes sky light 0 for
    sections ingested without sky-light data; such faces are now treated as open sky.
  - Distant terrain fading to black at night and clouds as dark holes: the night-sky
    background (airglow) was ~200x too faint and starlight was not in the sky ambient. Both
    now follow real ratios to the full moon and are part of skyRadiance()/sky irradiance.
  Not yet confirmed in game.

* 2026-10-24 - TAA blended in absolute radiance, so its tone compression was linear at night
  and bright lights dominated; it now compresses in exposed units (found by the research pass,
  docs/SHADER_RESEARCH.md).

# Regression audit (2026-10-26)

What was wrong, why, and what changed. Each item was found by reading the pipeline, and where
possible confirmed with a CPU reference test in `tools/tests/`. None of it has been checked in
Minecraft yet (see [TESTING.md](TESTING.md)).

## Repository state before this audit

* `foldedapples/Belgium-Shader` `main` (ad5fa43 … bcc7b6a) and PR #1 all contained
  Halcyon/Glimmer-derived code (`shaders/lib/halcyon/*`, `tools/import_halcyon.py`). That code
  must not be used, so no earlier commit could serve as a clean "last working version".
* The local `Meridian-dev` folder held the from-scratch Meridian pack (the same project under its
  other working title) with no Halcyon or Glimmer code. Its `tools/` and `docs/` were missing.
  Commit d34f1be put that tree on top of `main`. History was kept and nothing was force-pushed.

## Shadows moving with the camera / head

| Cause | Effect | Fix |
|---|---|---|
| Geometry is drawn with the TAA jitter added in clip space; every deferred/composite pass reconstructed positions with the unjittered `gbufferProjectionInverse` | Reconstructed world positions moved by up to ½ pixel per frame: 0.065 block at 100 blocks, 0.4 of a far-cascade texel. Shadow lookups, fog, SSR and TAA reprojection all wobbled | `sceneToView` / `viewToScene` in `lib/common/transform.glsl` remove/re-apply the jitter (vanilla and DH; Voxy draws unjittered) |
| Cascade snapping pivoted the light rotation about the world origin | Every change of the light direction moved the texel grid by \|ΔL\| × (distance to 0,0,0). At x≈12,000 the sun's motion alone gave a fresh random sub-texel phase every frame. The float noise in view-space `sunPosition` when turning the head moved it about 1 cascade-0 texel | Snapping relative to `state.shadowAnchor`, a block within 32 blocks of the player (`program/begin/frame_setup.csh`). Drift: 0.50 → 0.02 texel/frame (`test_shadow_stability.py`) |

Static geometry with a fixed light keeps its sub-texel phase to within 0.02 texel in all four
cascades while the camera walks, strafes, flies and turns (same test).

## Sun glare, highlights, moon

* The sun disk was emitted at its physical radiance, about 16,000× display white, and saturated
  every bloom level. It is now limited to 120× white at the current exposure (local adaptation,
  `lib/sky/celestial.glsl`). Glare above 0.05 display units shrank from 3.5° to 1.5°
  (`test_sun_glare.py`).
* Smooth reflections drew the sun/moon disk from the sky fallback even though the BRDF already
  adds the shadow-casting body as an analytic glint, so it was counted twice, and the second copy
  was an aliased sub-pixel spot (`program/composite/translucent.fsh`, `lib/sky/sky.glsl`).
* Directional specular used a point light. At the minimum alpha (0.0016), D ≈ 1e5 gave sub-pixel
  sparkles that flickered under TAA. Alpha is now widened by the source's angular radius, and no
  glint may exceed the limited disk (`lib/lighting/brdf.glsl`, `lighting.fsh`).
* The Moon disk peak was 2.5× white, and its real peak was ~1.3× above the assumed one, so the
  highlands clipped. It is now 1.6× (`lib/sky/moon.glsl`).

## HDR / grading

* Display contrast `(√c − 0.45)·k + 0.45` was not anchored at black. Vibrant (k = 1.06) turned
  every display value below 0.00065 to pure black, and Cinematic (1.12) everything below 0.0026,
  which crushed night and cave shadows. It is now a midtone-weighted curve with fixed black and
  white points, monotonic for k in 0.7–1.4 (`lib/post/grading.glsl`).
* Exposure metering, bloom energy (mix 0.045), tone curves and sRGB output were reviewed. No
  further fault was found.

## Volumetric clouds

* Wind shear was 0.35·h × (wind displacement accumulated since loading), which grows without
  bound. Clouds leaned more every minute until they sheared into flat streaks (after 10 km of
  drift, a 220 m height step sampled noise 350 m away), and they popped when the offset wrapped.
  Shear is now a fixed lean along the wind (`lib/clouds/clouds_common.glsl`).
* Clouds moved against `windDirection()` (the noise was sampled at x + offset), opposite to the
  rain and plants. They now move with it.
* Cloud history is reprojected through the clouds' own wind motion (`clouds.csh`).

## Water, weather, materials (second pass, 2026-10-26)

* **Interactive water wakes missing in tiles.** Invocation (0,0) of the simulation step rewrote
  the player/vehicle history in the shared state buffer while every other invocation of the
  same dispatch read it to build the bow wave. Workgroups that ran later saw no motion. The
  history is now rolled in the single-invocation bookkeeping pass, before the steps
  (`program/prepare/water_sim.csh`).
* **Rain ripples jittering far from spawn.** They were evaluated at float camera + offset: up to
  0.8 % of a ring wavelength of error at x = 30,000 and 25 % at x = 10^6. They now use Iris'
  integer camera position wrapped to a 1536-block period with wrapped cell hashes, which is
  exact and seamless (`lib/weather/ripples.glsl`, `test_ripple_precision.py`).
* **The sea popping once an hour.** `frameTimeCounter` wraps at 3600 s and each wave train
  jumped phase. Frequencies are now rounded to whole cycles per hour. Flowing-water advection
  still jumps at the wrap.
* **LabPBR predefined metals untinted.** The spec says the albedo tints their reflections; the
  tint is now applied. The built-in vanilla metals (and the Voxy adapter) moved to code 255 so
  vanilla gold and copper are not tinted twice.
* **Distant water sparkling.** Wave normals had no per-frequency filtering. Each component is
  now prefiltered by the pixel footprint and the lost slope variance becomes roughness
  (`lib/water/waves.glsl`, `test_wave_filter.py`).

## From the first in-game screenshots (2026-10-27)

The pack ran in Minecraft 1.21.11 with Iris 1.10.8, Sodium 0.8.12 and Voxy 0.2.16. The log showed no
shader errors. Root causes of what the screenshots showed:

* **Waves faster near the player.** A train's phase was k·x − ωt with k changing over time:
  every train rotated with the slowly turning wind, and the long wavelengths and a river current
  followed the player's smoothed biome. The apparent frequency at a point is then ω + x·dk/dt.
  For the 0.55-block train it measured 1.4 to 82 rad/s depending on position, against a true
  10.6, and 106 rad/s while walking into a river biome (`test_wave_speed.py`). The fix: fixed
  lattice wave vectors in exact wrapped coordinates, with amplitude-only weather and biome, and
  two-phase bounded advection (`lib/water/waves.glsl`, `lib/common/world_coord.glsl`).
* **No player or boat ripples.**
  * The water plane was one block low for a floating player, which in shallow water put it in
    the river bed.
  * `relativeVehiclePosition` (camera − vehicle, per the Iris source) was added instead of
    subtracted.
  * Cells, the body and the shore voxels used different coordinate frames (Iris shifts
    `cameraPosition`).
  * Fresh cells were compared against the wrong frame.

  All fixed in `program/prepare/water_sim.csh` and `lib/water/sim_common.glsl`
  (`test_water_sim_frames.py`).
* **Black End portal.** `gbuffers_block` never read `blockEntityId`, so the portal was its dark
  texture lit like stone. It now has its own parallax starfield (`lib/material/end_portal.glsl`).
* **Fade in from black on load.** Auto exposure adapted from an uninitialised or stale value. It
  now snaps to the target unless it ran on the previous frame, and TAA ignores never-written
  history.
* **Beige veil in the End.** The End dust was dense with a strong forward lobe toward the black
  hole. It is now thin and confined to the island band.
* **Banded accretion disk.** Differential rotation wound the advected pattern into ever finer
  rings. It now uses two-phase advection over a bounded window.
* **Repetitive rings.** The periodic sine profile was replaced by a ring-system optical depth with
  ringlets, slant-path opacity, and shadows from the rings onto the planet and from the planet
  onto the rings.
* **Saturated cyan shorelines.** Caustic focus was capped at 6×; it is now 3.5×.

## Reviewed, no fault found

* End exposure and lighting: lit End stone lands near middle grey because exposure is clamped
  around a reference derived from the disk light. The event horizon is a hard capture
  (transmittance 0).
* Volumetric light: the bright line through the sun is already prevented (cascade-edge fade).
* Shadow atlas: quadrant discard and receiver tap clamping prevent cross-cascade bleeding.
* Water simulation stability (k = 0.02 ≤ 0.5), teleport rejection, domain recentring
  (toroidal grid, fresh cells cleared), low FPS (dt clamp, at most 4 steps per frame).
* Wetness and puddles: sky-exposure and biome gating, porosity darkening, puddles only on
  exposed upward faces.
* LabPBR normal convention: the tangent frame follows +V, matching LabPBR's DirectX (Y-down)
  maps.
* Cloud shadow map: snapped centre, written by one invocation and read only by later passes.

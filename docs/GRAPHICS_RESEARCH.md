# Graphics research: Eclipse source study and our own designs

Studied on 2026-10-27 from `Merlin1809/Eclipse-Shader`, branch Unstable, commit e89e6c6. The
repository was cloned into a scratch folder and only read; nothing was run, and nothing was copied
into this pack. Eclipse's `LICENSE.md` reads "© 2020 Chocapic13. All rights reserved.", so none of
its code may be reused. Several Eclipse files also credit third-party sources with their own terms:
- the water simulation: "Base water ripple shader from shadertoy.com/view/wdtyDH, heavily edited"
- rain ripples: Ctrl-Alt-Test / Zavie, from Shadertoy
- aurora: a non-commercial Shadertoy source
- clouds: curl noise borrowed from Photon

Shadertoy's default licence is CC BY-NC-SA 3.0 unless the author states otherwise. Below,
"read at source level" means the file itself was read; other entries come from the 2026-10-26
study summarised in [REVERSE_ENGINEERING_RESEARCH.md](REVERSE_ENGINEERING_RESEARCH.md).

## 1. Interactive water simulation (read at source level)

**Files:**
- `shaders/dimensions/prepare.csh`
- `shaders/dimensions/prepare1.csh`
- `shaders/dimensions/prepare2.csh`
- the consumers in `all_translucent.fsh` (around line 850) and `all_translucent.vsh`

**How it works:**
- **State.** Two images. `waveSim` (RG16F) holds height, which Eclipse calls "pressure", plus
  vertical velocity. `waveSim2` (RGBA16F) holds the same, plus the height gradient in BA. A third
  piece, a set of SSBO fields, holds the bookkeeping: the previous player position, a fractional
  movement accumulator, the integer scroll offset, the disturbance size, an "idle" flag and the
  last update time.
- **Bookkeeping (`prepare.csh`, one thread).** The body position is the camera minus
  `relativeEyePosition`, or minus `relativeVehiclePosition` when riding. Its movement is
  accumulated in grid units, and whole cells are handed to the update as an integer scroll offset.
  A disturbance radius grows with speed and is larger in a boat. On Iris ≥ 1.10.4 the code uses
  the `onWaterSurface`, `vehicleId`, `vehicleInWater`, `isRiding` and `vehicleLookVector` uniforms.
  On older Iris it guesses the water and boat state from the voxel volume. Updates happen at most
  once per frame, gated by `frameTimeCounter` against a 30 or 60 Hz period.
- **Update (`prepare1.csh`, then `prepare2.csh`).** Two half-steps alternate between the images,
  so each frame reads only what the previous half-step wrote (ping-pong). Each half-step does the
  following:
  1. Read the cell, shifted by the scroll offset in the first half-step, so the grid follows the
     player.
  2. Take the five-point Laplacian of the height.
  3. Update velocity from the Laplacian, then height from the velocity (semi-implicit Euler).
  4. Add a small restoring spring and multiply the velocity by a damping factor.
  5. Fade height and velocity toward zero with distance from the grid centre (absorbing edge).
  6. While the player is on the water surface, add height inside a disk around them, every update.
     For a boat it uses a capsule along `vehicleLookVector` with signed amplitude: raised at the
     bow, lowered at the stern.

  `prepare2` also stores central-difference gradients, so the water fragment needs a single
  bilinear fetch. Any non-zero cell clears the idle flag, and the next frame skips the update when
  nothing moves.
- **Shading (`all_translucent.fsh`).** The gradient channel is sampled around the player's grid
  centre and blended into the procedural wave normal.

**Limits we can infer:**
- No shorelines: waves fade at the grid edge but pass straight through land.
- One update per frame: below the update rate, ripples slow down.
- The disk source adds volume on every update. A player standing still in water keeps pumping it,
  which is why the code shrinks the disk for a stationary boat.
- Only the player's own vehicle is known. Iris exposes no other entities.

**Our design** (`program/prepare/water_sim.csh`, `lib/water/sim_common.glsl`), written
independently:

| Aspect | Ours | Why |
|---|---|---|
| Scheme | Leapfrog on height and previous height (the damped 2D wave equation, explicit, 5-point Laplacian), k = (c dt/dx)² = 0.02 against the k ≤ 0.5 stability limit | Second-order accurate in time; c ≈ 2 blocks/s matches 1–3 m water waves |
| Time | Fixed 1/60 s steps, up to 4 per frame from an accumulator | Same speed from 15 FPS to any high frame rate |
| Grid | World-anchored toroidal grid (texel = cell mod N) in exact integer cells from `cameraPositionInt/Fract`; cells that wrap in are cleared | No copying when moving; precise anywhere in the world |
| Disturbance | Moving-body displacement B(x−p_now) − B(x−p_prev), added to both time levels; zero-volume splash on entry | Conserves volume: a swimmer makes a bow wave and trough without digging a hole |
| Shores | Cells whose column has no water at the surface plane (voxelised terrain) are reflecting walls; sponge layer at the domain edge | Ripples bounce off banks |
| Water plane | Top of the highest water voxel in the body's column | Works for floating, swimming, shallow water and boats |
| Boats | Three displacement points along `vehicleLookVector`, moved like the body; only the player's own vehicle (`vehicleId` from `entity.properties`) | Iris exposes nothing about other boats |
| Idle / dimensions | Sleeps when nothing moves (idea shared with Eclipse); the field resets when the dimension changes | Saves GPU time; no cross-dimension leaks |

We don't use `onWaterSurface`. It wasn't listed on the shaders.properties uniform pages checked
on 2026-10-26, and our voxel water plane covers the same cases.

## 2. Rain ripples versus the simulation (read at source level)

Eclipse's `lib/ripples.glsl` is a decorative procedural effect: hashed cells, each emitting a
periodically expanding ring, summed over the 3×3 neighbouring cells. It is **not** part of the
simulation and does not interact with it. Ours (`lib/weather/ripples.glsl`) has the same
separation and an independent formulation:
- two hashed-cell layers at different scales, each drop at a random place and time in its cell
- a damped capillary ring whose derivative gives the gradient
- coordinates in exact wrapped world space, with periods matched to the cells
- prefiltered by the pixel footprint on water

## 3. Water waves (`lib/waterBump.glsl`)

Eclipse's waves are three rotated, anisotropically scaled noise-texture lookups. Normals come from
finite differences whose step grows with distance, which doubles as cheap anti-aliasing. Ours are
analytic dispersive trains with fixed lattice wave vectors (their speed doesn't depend on camera,
biome or wind; see `tools/tests/test_wave_speed.py`). They are prefiltered per frequency by the
pixel footprint, and the removed slope variance becomes roughness.

## 4. Other systems (summarised from the earlier study)

**Clouds (`lib/volumetricClouds.glsl`):**
- Small and large cumulus, altostratus and cirrus layers, plus distant cumulonimbus.
- 2D coverage with pseudo-3D erosion.
- A choice of HG, Cornette–Shanks or HG–Draine phase.
- A dedicated temporal filter.

Ours: one shell with a per-column cloud type and separate cirrus.

**Shadows (`lib/Shadows.glsl`, `Shadow_Params.glsl`, `begin.csh`):**
- One distorted map with PCSS-style filtering.
- `begin.csh` can build its own shadow matrix (custom moon orbit, lightning direction, the End).

Ours: four cascades snapped about a near-player anchor.

**Lightning (`lib/lightning_stuff.glsl`):** the bolt is a vertical-line point light, used for
terrain, fog and clouds, plus an optional shadow map aimed from the bolt.

**Not yet studied at source level:** aurora, rainbows, shader grass (geometry and tessellation
stages), snow, emissive ores and trims, chunk fading.

## 5. Features added after the study (2026-10-27), all original

* **Rainbows** (`lib/sky/sky.glsl`). Each wavelength is placed at its minimum-deviation angle,
  computed from water's refractive index n(λ) (Cauchy fit through measured values):
  * primary bow: 4r − 2i;
  * secondary bow: π − (6r − 2i), with the colours reversed;
  * Alexander's dark band between them.

  `tools/tests/test_rainbow.py` puts the primary at 42.45° to 40.58° and the secondary at 50.23°
  to 53.59°. The bow appears after rain while the air is still wet and the sun is below 42°.
* **Aurora.** Folded emission curtains with vertical rays, sampled on altitude shells between
  100 and 280 km. Colour comes from altitude (557.7 nm green low, 630 nm red high). It appears on
  some nights by default.
* **Snow cover.** A material-level overlay in snowy biomes on exposed upward faces, patchy
  along a noise edge. It has no geometry stage, so it costs nothing elsewhere.
* **Emissive ores** (option, off by default). Only the mineral specks glow; ores now have their own
  block ID.
* **Distant Horizons chunk fade.** A dithered hand-over from vanilla chunks to the DH terrain
  underneath, resolved by TAA.

## 6. Status of the requested features in this pack

These exist in the code:
- the interactive simulation (above)
- rain ripples
- puddles (recalibrated 2026-10-27)
- the Moon with NASA textures, orbit, phases and eclipses (default size raised to 3×)
- volumetric clouds and cirrus

**Not implemented yet:**
- shader grass: needs a geometry or tessellation stage whose cost must be measured first; Iris
  compiles such stages for the whole program even when an option turns the effect off
- lightning shadows: needs a second shadow projection aimed from the bolt
- emissive armour trims: trims are not distinguishable from other armour layers in the stages
  checked
- chunk fading for Voxy
- the 1.21.11 chunk fade-in: no per-chunk age is exposed to shaders that we could verify
- Photonics and Caelum integration: not researched; nothing implemented and nothing claimed

Each needs its own design and in-game testing. In particular, shader grass needs a geometry or
tessellation stage whose cost must be measured before it goes into any preset.

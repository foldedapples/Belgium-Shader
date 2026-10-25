# Compatibility

Status definitions (as required): **SUPPORTED** = tested and working · **PARTIAL** = working with
documented limitations · **UNTESTED** = expected but unverified · **UNSUPPORTED** = confirmed
incompatible.

**No configuration has been run in Minecraft yet, so nothing is SUPPORTED.** "Static: PASS"
means every program compiles under Khronos glslang with that environment's `MC_VERSION`,
`IRIS_VERSION` and feature macros (`tools/validate.py`, 105 variants). UNSUPPORTED entries are
confirmed from source code (a missing interface), not from a failed run.

## How capabilities were determined

* **Iris:** each Minecraft version has a branch in the Iris repository whose head is the newest
  Iris build for it. The features the pack uses were searched for on each branch head
  (2026-10-24):

| Capability | Iris 1.6.14 (1.20.2) | Iris 1.7.x – 1.9.x | Iris 1.10.8, 1.11.x |
|---|---|---|---|
| SSBO, compute, custom images, `IRIS_FEATURE_*` defines, separate HW shadow samplers, `shadow.culling`, render stages, `heldItemId`, `playerLookVector`, `dynamicHandLight` | yes | yes | yes |
| `cameraPositionInt/Fract`, `previousCameraPositionInt/Fract` | **no** → derived from the float position (less precise far from the origin) | yes | yes |
| `BLOCK_EMISSION_ATTRIBUTE` (optional feature) | **no** → per-class vanilla light levels | yes | yes |
| Distant Horizons programs, `dhShadow.enabled` | **no** | yes | yes |
| `feetInWater`, `vehicleId`, `relativeVehiclePosition`, `vehicleLookVector`, `vehicleInWater` | no | **no** → water reacts only while the head is submerged; no boat wakes | yes (`IRIS_VERSION >= 11004`) |

* **Voxy:** its Iris interface (`voxy.json` version 1, `voxy_emitFragment`) first appeared in the
  Voxy repository on 2025-08-15, i.e. Voxy 0.2.4-alpha and later. `VoxyFragmentParameters` is
  unchanged from then to the current head; its `lightMap` is encoded as `(level + 0.5) / 16`
  (vanilla convention). Voxy's only 1.20 build (0.1.5-alpha, 2024) predates the interface.
* **Distant Horizons:** integration is through Iris (`DISTANT_HORIZONS`, `dh_terrain`, `dh_water`,
  `dh_shadow`, `dhDepthTex0/1`, `dhProjection*`, `dhMaterialId`), present from Iris 1.7.
* `MC_VERSION` / `IRIS_VERSION` are formatted by Iris as `MMmmpp` (1.21.11 → 12111,
  26.1.2 → 260102; Iris 1.10.8 → 11008).

## Test matrix

Newest published builds per Minecraft version (Modrinth API, 2026-10-24). Loader = what that
Iris build supports.

| Minecraft | Iris | Loader | Sodium | Distant Horizons | Voxy | Static | Core lighting | Water sim | LOD rendering | Known issues |
|---|---|---|---|---|---|---|---|---|---|---|
| 1.20.1 | 1.7.6 | Fabric/Quilt | mc1.20.1-0.5.13 | 3.3.3-1.20.1 | — | PASS | UNTESTED | PARTIAL (no boat wakes) | DH: UNTESTED | |
| 1.20.2 | 1.6.14 | Fabric/Quilt | mc1.20.2-0.5.5 | 3.3.3-1.20.2 | — | PASS (`iris_1_6` variant) | UNTESTED | PARTIAL (no boat wakes) | DH: UNSUPPORTED (Iris 1.6 has no DH shader interface) | Reduced position precision; emission from block classes |
| 1.20.4 | 1.7.2 | Fabric/Quilt | mc1.20.4-0.5.8 | 3.3.3-1.20.4 | 0.1.5-alpha | PASS | UNTESTED | PARTIAL | DH: UNTESTED · Voxy: UNSUPPORTED (no Iris interface) | |
| 1.20.6 | 1.7.2 | Fabric/Quilt | mc1.20.6-0.5.11 | 3.3.3-1.20.6 | — | PASS | UNTESTED | PARTIAL | DH: UNTESTED | |
| 1.21.1 | 1.8.8 (Fabric), 1.8.14-beta.1 (NeoForge) | Fabric / NeoForge | mc1.21.1-0.6.13 | 3.3.3-1.21.1 | — | PASS | UNTESTED | PARTIAL | DH: UNTESTED | |
| 1.21.4 | 1.8.8 | Fabric / NeoForge | mc1.21.4-0.6.13 | 3.3.3-1.21.4 | — | PASS | UNTESTED | PARTIAL | DH: UNTESTED | |
| 1.21.5 | 1.8.11 | Fabric / NeoForge | mc1.21.5-0.6.13 (beta) | 3.3.3-1.21.5 | — | PASS | UNTESTED | PARTIAL | DH: UNTESTED | |
| 1.21.8 | 1.9.6 | Fabric / NeoForge | mc1.21.8-0.7.3 | 3.3.3-1.21.8 | 0.2.5-alpha | PASS | UNTESTED | PARTIAL | DH, Voxy: UNTESTED | |
| 1.21.10 | 1.9.7 | Fabric / NeoForge | mc1.21.10-0.7.3 | 3.3.3-1.21.10 | 0.2.9-alpha | PASS | UNTESTED | PARTIAL | DH, Voxy: UNTESTED | |
| 1.21.11 | 1.10.8 | Fabric / NeoForge | mc1.21.11-0.8.15-beta.1 | 3.3.3-1.21.11 | 0.2.16-beta | PASS | UNTESTED | UNTESTED (full) | DH, Voxy: UNTESTED | |
| 26.1.2 | 1.11.4 | Fabric / NeoForge | mc26.1.2-0.9.2 | 3.3.3-26.1.2 | 0.2.18-beta | PASS | UNTESTED | UNTESTED (full) | DH, Voxy: UNTESTED | |
| 26.2 | 1.11.4 | Fabric / NeoForge | mc26.2-0.9.2 | 3.3.3-26.2 | 0.2.19-beta | PASS | UNTESTED | UNTESTED (full) | DH, Voxy: UNTESTED | |
| 26.3 | 1.11.7 | Fabric / NeoForge | mc26.3-0.9.3-beta.1 | 3.3.4-26.3 | 0.2.20-beta | PASS | UNTESTED | UNTESTED (full) | DH, Voxy: UNTESTED | |

Configurations to test per row (docs/TESTING.md): Iris alone · Iris + DH · Iris + Voxy · with a
LabPBR pack · LOD terrain in rain, at night, at sunrise/sunset. **DH and Voxy together are not
claimed** (the pack prefers DH if both define their macros; the combination is untested).

Iris on Minecraft 1.20.x bundles or requires Sodium on Fabric; on NeoForge, Iris for 1.21.x
uses Sodium's NeoForge build. Use the pairs above rather than mixing versions.

## Requirements and fallbacks

* Required Iris features: SSBO, compute shaders, custom images, separate hardware shadow
  samplers (present in every Iris version above). Iris refuses the pack with a clear message if
  one is missing (e.g. GPUs without OpenGL 4.3; macOS).
* Optional: `BLOCK_EMISSION_ATTRIBUTE` (falls back to per-class light levels for coloured light).
* Iris < 1.7: split camera position derived from the float position. Effects that rely on it
  (water simulation grid, light volume, noise anchoring) lose precision beyond roughly
  ±100 000 blocks from the origin.
* Iris < 1.10.4: no feet-in-water or vehicle uniforms. The water simulation reacts while the
  player's head is under water only, and boats leave no wake. The analytic waves are unaffected.
* OptiFine: not supported (none of the Iris-only interfaces exist there).

## Distant Horizons

Iris defines `DISTANT_HORIZONS`; the pack compiles `dh_terrain`, `dh_water` and (with **LOD
Shadows**, off by default, untested) `dh_shadow`, and merges `dhDepthTex0/1` with vanilla depth in
every pass that reconstructs positions.

| On LOD terrain | Behaviour |
|---|---|
| Sun, moon, sky light, block light | Same lighting model and FrameState as vanilla terrain; no normal/specular maps (DH has none). Per-block albedo variation. |
| Shadows | Cloud shadows; sky-light shadow estimate; shadow-map shadows only with LOD Shadows inside the shadow distance. |
| Fog, haze, clouds, exposure, grading | Identical chain to vanilla (shared `atmosphere_chain.glsl`); border fog moves to the DH distance; clouds march to LOD depth. |
| Water | Same composite shading; analytic waves band-limited by footprint; no simulation. |
| SSAO, contact shadows, SSGI, SSR, puddles | Off (no reliable depth/material data). Rain darkening still applies. |
| Hand-off | DH fragments dither in over 78–92 % of the vanilla render distance; TAA resolves the dither into a cross-fade. |

## Voxy

Voxy defines `VOXY` while rendering with a pack and loads `voxy.json`, `voxy_opaque.glsl`,
`voxy_translucent.glsl`. Normals come from the face index; materials from `customId`. Voxy
water is written with a flag so composite adds analytic waves (the Voxy patch cannot read the
pack's state). Other far translucents get a lightmap-only estimate. Voxy depth is read as
conventional [0,1] depth with `vxProjInv` (as both reference packs do) — verify with Debug
Views 17/18.

## Not supported

ColorWheel, Physics Mod ocean, Photonics, HDR display output (no Iris API).

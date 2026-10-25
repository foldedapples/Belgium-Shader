# Expansion Plan (Iris + DH + Voxy + colour + multi-version)

Status legend: **done (static)** = implemented and compile-validated, not run in game;
**needs game** = cannot progress without in-game testing/profiling.

## Interfaces verified (sources, 2026-10-24)

* Iris: per-Minecraft branches of the Iris repository (feature table in COMPATIBILITY.md).
  Only uniforms/defines found in those sources are used; version-dependent ones are gated on
  `IRIS_VERSION` (`>= 10700` split camera position, `>= 11004` feet/vehicle uniforms) or on
  `IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE`.
* Distant Horizons via Iris: `dh_terrain`, `dh_water`, `dh_shadow`, `dhShadow.enabled`,
  `dhDepthTex0/1`, `dhProjection*`, injected `dhMaterialId`.
* Voxy: `voxy.json` v1, `voxy_opaque.glsl`/`voxy_translucent.glsl`, `voxy_emitFragment`,
  `VoxyFragmentParameters` (unchanged since 0.2.4-alpha), `vxDepthTex*`, `vxProj*`.
* Published builds per Minecraft version from the Modrinth API (COMPATIBILITY.md matrix).

## Milestones

| | Milestone | State |
|---|---|---|
| A | Workspace audit, interface verification, version matrix | done (static) |
| B | Version fallbacks (Iris 1.6, missing optional features, pre-1.10.4 uniforms), validator environments per version | done (static) |
| C | DH: shared lighting/atmosphere chain, hand-off dither, LOD safety (no SSR/puddles/SSAO/SSGI), `dh_shadow` (experimental) | done (static); needs game |
| D | Voxy: independent path, water record with wave flag, analytic waves in composite | done (static); needs game |
| E | Coloured lighting: profile-scaled block light, hand light, block-light specular | done (static); needs game |
| F | SSGI (half-res trace + bilateral/temporal filter) | done (static); needs game |
| G | Colour profiles and tone curves | done (static); look needs game |
| H | Performance: per-preset SSGI cost, LOD distances | needs game (PERFORMANCE.md protocol) |
| I | Visual cohesion pass (vanilla vs LOD colour match, profile tuning) | needs game (TESTING.md §8b) |

## Design decisions

* **One lighting model for all geometry.** DH and Voxy only differ in how a G-buffer sample is
  produced (data adapters); everything after the G-buffer reads the same FrameState, so sun,
  sky and fog cannot diverge between vanilla and LOD terrain.
* **Interactive water stays local.** The simulation window follows the player; LOD water gets
  the band-limited analytic waves only.
* **DH preferred if both LOD mods are present.** Running both is not claimed.
* **Profiles change sources, not the final image.** Light colours, GI saturation and
  reflection strength are scaled where computed; only contrast/saturation/vibrance and the tone
  curve act on the final image.
* **Graceful degradation over refusal.** Required features are those present in every target
  Iris build; anything newer has a fallback.

## Open risks (to check in game)

* Voxy depth convention (assumed conventional [0,1] with `vxProjInv`).
* SSGI temporal stability on fast camera motion.
* Profile tuning values are first guesses; Vibrant must not oversaturate foliage.
* dh_shadow cost and coverage.

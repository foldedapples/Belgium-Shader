# Rendering research

Facts the pack relies on, with where each was checked. **Verified** means it was read from the
cited source during development. **Implemented** means the technique exists in the code, and
names the file. External shader packs (Eclipse, Bliss, Photon, Complementary, Glimmer) were used
only as background on which techniques exist. No code was taken from them.

## Iris interfaces

| Topic | Fact | Status |
|---|---|---|
| Distant Horizons programs | `dh_terrain`, `dh_water`, `dh_shadow`; all must use the `compatibility` profile; `DISTANT_HORIZONS` is defined for every program when DH is active | Verified, shaders.properties DH page (2026-10-26) |
| DH attributes | `gl_Vertex`, `gl_MultiTexCoord2`, `gl_Normal`, `gl_Color`, `dhMaterialId` (declared by Iris; categories `DH_BLOCK_*`); `mc_Entity` is not available | Verified, same page |
| DH uniforms/textures | `dhNearPlane`, `dhFarPlane` (not the render distance), `dhRenderDistance`, `dhProjection(Inverse)`, `dhPreviousProjection`, `dhDepthTex0/1` (DH geometry only, own near/far) | Verified, same page |
| DH shadows | DH has no shadow distance (all chunks are rendered); the shadow pass keeps the normal projection; `dhShadow.enabled` toggles it | Verified, same page |
| Voxy | The shaders.properties Voxy page only points to the Cortex Discord `#docs` channel. The pack's `voxy.json`, `voxy_emitFragment`, `vxDepthTexOpaque/Trans` and `vxProj*` usage cannot be checked against a public reference | **Unverified** against docs; compiles only |
| Shadow snapping | `shadowIntervalSize = 0` turns Iris' own snapping off; the pack snaps itself | Implemented, `lib/lighting/shadow_proj.glsl` |

## Techniques used (own implementations)

| Area | Technique | Where |
|---|---|---|
| Shadows | 4 orthographic cascades in a 2×2 atlas, texel-snapped about a near-player anchor in double precision; PCSS (blocker search + Vogel disk); normal-offset and slope bias; coloured translucent shadows | `program/begin/frame_setup.csh`, `lib/lighting/shadows.glsl` |
| TAA | Halton(2,3) jitter; reconstruction with the jitter removed; closest-depth reprojection; YCoCg variance clipping | `lib/common/jitter.glsl`, `transform.glsl`, `program/composite/taa.fsh` |
| BRDF | GGX + height-correlated Smith (Heitz 2014); split-sum DFG LUT; multiple-scattering compensation (Turquin 2019); sun and moon as disks via alpha widening | `lib/lighting/brdf.glsl` |
| Materials | LabPBR 1.3 decoding (smoothness, F0 / predefined metals with complex IOR, porosity / SSS, emission, AO, height) | `lib/material/labpbr.glsl` |
| Sky | Precomputed transmittance / multiple-scattering / sky-view LUTs (Hillaire 2020 style), order-2 SH sky irradiance | `program/prepare/atmosphere.csh`, `lib/atmosphere/atmosphere.glsl` |
| Celestial | Orbital moon (phases from geometry, 5.1° inclination, regressing nodes, eclipses); Lommel–Seeliger lunar shading; disk local adaptation | `lib/sky/celestial.glsl`, `lib/sky/moon.glsl` |
| Clouds | Perlin–Worley shape plus Worley erosion on a moving weather map; per-type height profiles; octave multiple scattering (Wrenninge et al. 2013); dual-lobe HG; temporal reconstruction with variance clipping | `lib/clouds/clouds_common.glsl`, `program/deferred/clouds.csh` |
| Water | Wind-driven analytic waves; height-field simulation around the player; Snell's window; Beer–Lambert absorption | `lib/water/*`, `program/prepare/water_sim.csh` |
| Tone mapping | Own hue-preserving Naka–Rushton curve; Khronos PBR Neutral (Apache-2.0, see THIRD_PARTY_NOTICES.md); extended Reinhard | `lib/post/tonemap.glsl` |
| Grading | Bradford white balance; scene saturation; midtone-weighted display contrast; vibrance; split toning | `lib/post/grading.glsl` |

## Tone-mapper survey

Candidates: Tony McMapface (a 3D LUT), AgX, ACES fits, Lottes 2016, Uchimura 2017 and Khronos
PBR Neutral. Only Khronos PBR Neutral is transcribed (Apache-2.0, notice kept in
THIRD_PARTY_NOTICES.md). The default curve is the pack's own. The licences of the other
candidates have **not** been checked in this pass. Check them before adopting any of them.

## Data sources

NASA SVS 4720 (CGI Moon Kit), NASA SVS 4851 (Deep Star Maps 2020; its Milky Way is Gaia-derived,
CC BY-NC 3.0 IGO), Yale Bright Star Catalogue. Credits and terms: THIRD_PARTY_NOTICES.md.

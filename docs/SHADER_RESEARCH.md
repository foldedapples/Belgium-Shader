# Shader Research II: Photon, shaderLABS, Iris docs vs. source

Scope: the techniques that `RENDERING_RESEARCH.md` does **not** cover, studied in Photon
(sixthsurge) and the shaderLABS templates, cross-checked against the Iris documentation and
Iris source, and compared with what Belgium Shaders currently does in `shaders/`. Licences,
Iris basics, Voxy's interface and the Bliss/Eclipse/Glimmer/Halcyon analysis are in
[`RENDERING_RESEARCH.md`](RENDERING_RESEARCH.md) and are not repeated here. The design
contract is [`ORIGINAL_ARCHITECTURE.md`](ORIGINAL_ARCHITECTURE.md); current status is
[`FEATURE_STATUS.md`](FEATURE_STATUS.md).

No code from any pack is reproduced here. Identifiers are named so the reader can find the
relevant code, and formulas are given only where they come from a published paper.

**Evidence tags** used throughout:

* **[src]**: read in source code (Photon, Iris, Voxy or Belgium) at the snapshot below.
* **[doc]**: stated in the Iris documentation (shaders.properties, read 2026-10-24).
* **[inf]**: my inference from the code or the literature, not confirmed by testing.
* **[not found]**: searched for and not found. That does not mean it is absent.

No runtime performance figures were published by any of the studied projects. Every cost
statement below is a count of samples, taps or bytes, never a millisecond figure.

Snapshots: Photon `main` at `6e67b36e` (2026-10-23); shaderLABS Base-330 at `3722d8b3`
(2025-06-01) and Snippets (2025-06-01); Iris branch `26.1` at `bff1e69` (same checkout as
`RENDERING_RESEARCH.md`); Voxy at its 2026-10-19 head.

---

## 1. Sources and licences

### 1.1 Photon: "Photon Shaders License Agreement" (`LICENSE`, recorded verbatim)

> Photon Shaders License Agreement
>
> Copyright © 2021-2025 Benjamin Stott ("SixthSurge")
>
> All rights reserved unless otherwise explicitly stated.
>
> Any person obtaining a copy of this software package ("Photon Shaders") may:
> - Use Photon Shaders, including for commercially published screenshots and videos.
> - Modify Photon Shaders for personal use.
> - Examine and learn from Photon Shaders's source code.
> - Redistribute modified or unmodified portions of Photon Shaders with the following exceptions:
>     - You may not redistribute Photon Shaders or derivative works on platforms that provide direct or indirect monetary compensation to creators (e.g. Modrinth, CurseForge) without my explicit written permission.
>     - You may not demand money in exchange for copies of Photon Shaders or derivative works without my explicit written permission.
> - Redistribute Photon Shaders as part of a (commercial) Modpack.
>
> This license document is to be included in all substantial copies of Photon Shaders.
>
> PHOTON SHADERS IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH PHOTON SHADERS OR THE USE OR OTHER DEALINGS IN PHOTON SHADERS.

What the licence permits, in plain terms (this is a reading of the text, not legal advice):

| Allowed | Not allowed without written permission |
|---|---|
| Using it, including for commercial screenshots and videos | Redistributing it, or a derivative, on Modrinth, CurseForge or any platform that pays creators |
| Modifying it for personal use | Charging money for copies or derivatives |
| Studying the source | |
| Redistributing portions elsewhere, and in (commercial) modpacks, with the licence attached | |

**Consequence for Belgium Shaders.** The pack is likely to be published on Modrinth or
CurseForge, so **no Photon code, constants, tables or data files may be included**. Photon
is a study reference only, the same status as Bliss and Eclipse. Photon also contains
third-party material with its own terms: the ACES files in
`include/post_processing/aces/` (with their own `license.md`), a shadow-bias method credited
to Complementary Reimagined, a blue-noise texture from momentsingraphics.de and a NASA
galaxy image. None of these may be taken through Photon either. Where Photon uses a
published technique, this document cites the paper, and any Belgium implementation must be
written from that paper.

### 1.2 shaderLABS

* **Base-330** (`LICENSE`): the Unlicense ("This is free and unencumbered software released
  into the public domain …"). It may be copied without conditions. It is a pass-through
  template ("none of them actually do anything", `readme.md`): `#version 330 compatibility`
  programs with `gtexture`, `lightmap`, `alphaTestRef`, `gl_TextureMatrix[1]` lightmap
  coordinates and `/* RENDERTARGETS: 0 */`. It has no technique to adopt. Its value is as a
  minimal, known-good interface reference when debugging a loading problem: swap one
  program for its Base equivalent and see whether the problem goes away.
* **shaderLABS/Snippets** (Unlicense unless a folder says otherwise): a *GLSL debug text
  renderer* (by SixthSurge; glyphs based on Monocraft, so check that font's licence before
  using its data) and a *blue-noise generator* (void-and-cluster; Ulichney 1993). These are
  debugging patterns worth adopting (§4).
* Other organisation repositories (Base-120/150, Shadow-Tutorial) are also Unlicense and add
  nothing beyond the Iris docs.

### 1.3 Primary literature for techniques covered here

Jimenez, Wu, Pesce, Jarabo, *Practical Realtime Strategies for Accurate Indirect Occlusion*
(GTAO), Activision tech. report ATVI-TR-16-01, 2016 ·
Kaplanyan & Dachsbacher, *Cascaded Light Propagation Volumes*, I3D 2010 ·
Schneider & Vos, *The Real-time Volumetric Cloudscapes of Horizon Zero Dawn*, SIGGRAPH 2015;
Schneider, *Nubis: Authoring Real-Time Volumetric Cloudscapes with the Decima Engine*,
SIGGRAPH 2017 ·
Hillaire, *Physically Based Sky, Atmosphere and Cloud Rendering in Frostbite*, 2016 ·
Karis, *High Quality Temporal Supersampling*, SIGGRAPH 2014 ·
Salvi, *An Excursion in Temporal Supersampling*, GDC 2016 ·
Pedersen, *Temporal Reprojection Anti-Aliasing in INSIDE*, GDC 2016 ·
Yang, Liu, Salvi, *A Survey of Temporal Antialiasing Techniques*, EG STAR 2020 ·
Heitz, *Sampling the GGX Distribution of Visible Normals*, JCGT 7(4), 2018 ·
McGuire & Mara, *Efficient GPU Screen-Space Ray Tracing*, JCGT 3(4), 2014 ·
Stachowiak, *Stochastic Screen-Space Reflections*, SIGGRAPH 2015 ·
Fernando, *Percentage-Closer Soft Shadows*, SIGGRAPH sketch 2005 ·
Vogel, *A better way to construct the sunflower head*, Math. Biosci. 1979 ·
Lagarde & de Rousiers, *Moving Frostbite to PBR*, SIGGRAPH 2014 (EV100, sensor
calibration, specular occlusion) ·
Wronski, *Volumetric Fog*, SIGGRAPH 2014 ·
Lottes, *Advanced Techniques and Optimization of HDR Color Pipelines*, GDC 2016 ·
Hoffman, *Fresnel Equations Considered Harmful*, EGSR/MAM 2019 (F82 tint) ·
Ramamoorthi & Hanrahan, *An Efficient Representation for Irradiance Environment Maps*,
SIGGRAPH 2001 (SH irradiance) ·
LabPBR Material Standard v1.3 (shaderlabs.org wiki).

---

## 2. Iris facts verified

Docs = shaders.properties pages read 2026-10-24. Source = Iris `26.1` Java. Where they
disagree, the source is trusted. "Belgium" = the current files in `shaders/`.

| # | Topic | Docs say | Source says | Belgium status |
|---|---|---|---|---|
| 1 | Program order | setup → begin → shadow → shadowcomp → prepare → gbuffers(opaque) → deferred → gbuffers(translucent) → composite → final; suffixes 1–99 [doc] | Same (`ProgramArrayId`, already in `RENDERING_RESEARCH.md §2`) | Matches `ORIGINAL_ARCHITECTURE.md §1`. |
| 2 | Compute placement | Computes run before the vertex stage of their slot; `_a.._z` run alphabetically after the suffixless file [doc] | `CompositeRenderer.renderAll` dispatches all computes of slot *i*, then issues a barrier, then draws slot *i*'s quad. A slot with only `.csh` becomes a `ComputeOnlyPass` [src] | Matches. `composite6..15.csh` and `begin*.csh` are compute-only. |
| 3 | Barriers (default) | `TEXTURE_FETCH | SHADER_IMAGE_ACCESS` before and after every compute, **without** the SSBO bit [doc] | `ComputeProgram.dispatch` issues `IMAGE_ACCESS | TEXTURE_FETCH | SHADER_STORAGE` **before** every dispatch, and the composite loop issues the same three bits **after** a slot's computes (both modes) [src] | **Docs are out of date; trust the source.** Belgium's begin.csh → shadow-pass SSBO reads are covered. |
| 4 | `allowConcurrentCompute` | One barrier after the last compute of a pass [doc] | Removes only the per-dispatch barrier; the post-slot barrier remains [src] | Not used (correct: begin_b..e are dependent steps). |
| 5 | Fragment `imageStore` → later fragment read | (not documented) | No barrier is inserted after fragment passes; only the next compute dispatch inserts one [src] | Safe today: the only fragment/vertex image writer is `shadow.vsh` (voxelMap), read by the `shadowcomp` compute. **Rule for new work:** a fragment-written image must be consumed by a compute, or a compute (even an empty one) must sit between writer and reader [inf]. |
| 6 | `setup` | Runs at pack load and on window resize [doc] | Re-dispatched when render targets are resized, after a full clear of render targets (`onFullClear`); dispatched with size (1,1) [src] | Belgium's setup computes use absolute `workGroups` (required, because `workGroupsRender` would resolve against 1×1) [src]. Every colortex history (TAA, clouds, SSGI) resets on resize; images and SSBOs are not cleared. |
| 7 | Flipping | Each colortex has main/alt; writing flips it; `flip.<pass>.<buf>` overrides; **compute-only passes never flip** [doc] | Same; plus at the end of the frame Iris *copies* alt → main for every non-cleared buffer that ended flipped (`FinalPassRenderer` swap passes) [src] | Histories `colortex7/9/13` read and write in one pass and are correct. The copy is one full-screen blit per such buffer per frame: a bandwidth cost to measure (milestone H). |
| 8 | `scale.<pass>` vs `size.buffer` | `scale` changes only the viewport; `size.buffer.<buf> = w h` (absolute or relative) changes the allocation; a resized buffer cannot be written by gbuffers, and one program may only write equal-size buffers [doc] | `PackDirectives.getTextureScaleOverride` sizes the target; `CompositeRenderer` throws if the draw buffers of one pass differ in size [src] | Belgium uses only `scale.*`, so reduced-res targets are allocated full size (`PERFORMANCE.md`, "Known inefficiencies"). `colortex8/10/12/13` are each written by exactly one reduced-res pass, so they qualify for `size.buffer` (§4, step 3). |
| 9 | Colour buffer count | 16, raised to 32 in Iris 1.10.5 [doc] | `IrisLimits.MAX_COLOR_BUFFERS = 32`, macro `MAX_COLOR_BUFFERS` [src] | **`RENDERING_RESEARCH.md §4.12` says "≤16 colortex"; that is true only for Iris < 1.10.5.** Belgium targets Iris ≥ 1.8, so `colortex16+` needs an `#if MAX_COLOR_BUFFERS > 16` gate (Photon uses `colortex16` only under Voxy). |
| 10 | Lazy allocation | (not documented) | `RenderTargets.getOrCreate` allocates a colortex only when a loaded program references it [src] | Partly answers the `PERFORMANCE.md` question: SSGI's `colortex12/13` are not allocated with SSGI off **if** no enabled program declares those samplers. Needs a check of deferred4's `#ifdef SSGI` guards [inf]. |
| 11 | Custom images | Max 16 (8 before Iris 1.6.4); `clear` per frame; `relative` sizes [doc] | `irisCustomImages.size() > 15` → error [src] | Belgium declares at most 12. 4 slots left. |
| 12 | SSBOs | Index 0–8; screen-relative form `bytes true sx sy`; init-from-file in Iris 1.8+ [doc] | Index ≤ 12 accepted, `> 12` fatal [src] | **Docs and source disagree; trust the source.** Belgium uses 0 and 1, which is safe under both. |
| 13 | Indirect dispatch | `indirect.<pass> = <ssbo> <offset>`, uvec3 at the offset [doc] | Parsed; adds `GL_COMMAND_BARRIER_BIT` and dispatches indirect [src] | Unused. Useful for skipping the water sim or flood-fill when asleep (§3.9). |
| 14 | Shadow culling | `true | false | reversed`; `reversed` keeps everything within `voxelDistance` and frustum-culls beyond [doc] | `false` → `DISTANCE` box culler; `reversed`/`safe_zone` → `SafeZoneCullingFrustum` (advanced frustum + box of `voxelDistance`); `DEFAULT` + voxelisation → distance only [src] | Belgium needs `false` (own light matrix) and has it. Photon uses `reversed` only when coloured lights are on (Iris' frustum is valid for Photon because it keeps Iris' shadow matrix) [src]. |
| 15 | `voxelizeLightBlocks` | Light blocks render as a degenerate quad at the block centre, `at_midBlock = 0`, lightmap = light level [doc] | Honoured in the Sodium mesh-build mixin [src] | Belgium sets it `true`. In `shadow.glsl` the emission level comes from `at_midBlock.w`. If that is also 0 for light blocks (the docs say "at_midBlock will be 0"), the block is skipped as air-like, and its light shows only through the vanilla lightmap (neutral chroma). That is harmless, but the directive currently buys nothing [inf]. |
| 16 | `alphaTestRef` | (not on the pages read) | Uniform holding the current render type's alpha cut-off; renamed to `iris_currentAlphaTest` by the patcher [src] | Belgium hard-codes `0.1` in `gbuffers_solid`/`shadow`. Base-330 uses `alphaTestRef`. Low risk, but `alphaTestRef` follows vanilla per render type. |
| 17 | `shadowcomp` stages | "Required stages: vertex, fragment" [doc] | Compute-only slots are legal (`ComputeOnlyPass`) [src] | Belgium's `shadowcomp.csh` alone is fine. **Docs page is wrong.** |

Two documentation mismatches inside this repo:

* `ORIGINAL_ARCHITECTURE.md §2.2` lists `skyViewLut` as 192×108, but `shaders.properties`
  declares 192×216 and `begin_skyview.glsl` dispatches 24×27 groups (two panels: sun and
  moon) [src]. The table should say 192×216.
* `RENDERING_RESEARCH.md §4.12` gives the colortex limit as 16 (see row 9).

---

## 3. Techniques

Each subsection covers: purpose; Photon's approach (algorithm and data flow); its
advantages, limitations and cost; then what Belgium already does, the gap, and what to adopt
as an independent implementation.

### 3.1 Ground-truth ambient occlusion (GTAO)

**Purpose.** Replace point-sampled SSAO with a cosine-weighted visibility integral that is
correct for the visible hemisphere, plus a *bent normal* (mean unoccluded direction) for
directional sky lighting.

**Technique (Jimenez et al. 2016).** For each of *S* screen-space slice directions around
the view vector, march the depth buffer in both directions to find the maximum horizon
angles h₁, h₂. Clamp them to the hemisphere of the projected normal (angle n in the slice),
then integrate the cosine-weighted visible arc analytically:
â(h₁,h₂,n) = ¼(−cos(2h₁−n) + cos n + 2h₁ sin n) + ¼(−cos(2h₂−n) + cos n + 2h₂ sin n),
weighted by the projected normal length. A multi-bounce fit (paper §5) brightens AO on
light-coloured surroundings. Bent normal = average of the slice bisectors.

**Photon** (`include/lighting/ao/gtao.glsl`, `program/d3_ao.fsh`) [src]:

* Runs in `deferred3` at **half resolution** (`ao_render_scale = 0.5`). Defaults are 2 slices
  × 3 horizon steps × 2 directions = **12 depth reads per half-res pixel**, radius 2 blocks
  with a falloff from 75 % of the radius. Slice angle and step offset are jittered by blue
  noise plus an R2 sequence per frame.
* Output `colortex6` (RGBA16): AO, an "ambient SSS" term (how far the horizon lies past 90°,
  used for subsurface ambient), and the bent normal octahedral-packed into two channels.
  History metadata `colortex14` (RG16F): depth and pixel age. Both `size.buffer` 0.5×0.5,
  never cleared.
* **Temporal accumulation**: reproject by scene position; Catmull–Rom history fetch; weight
  `age/(age+1)` with age capped at 10 frames; age is multiplied by a depth-similarity term
  (scaled by N·V) and an "off-centre" term that penalises history fetched between texels
  (reduces blur in motion). The bent normal is slerped and rotated from last frame's view
  space into the current one.
* Multi-bounce: a fixed surrounding albedo of 0.2 in the paper's fit form (simplified).
* Upsampled in `deferred4` with a depth/normal-weighted 2×2 bilateral. The bent normal is
  rejected if it faces away from the surface normal.
* LOD terrain: radius ×3 on DH/Voxy pixels, which works because Photon traces against a
  *combined* depth buffer (§3.8).
* The bent normal feeds an **L1 spherical-harmonics sky irradiance** computed per frame by a
  256-thread compute (`deferred4_a.csh` → `colorimg4`), so occluded pixels receive sky light
  from their open direction rather than an isotropic average.

**Advantages.** Physically meaningful (the integral equals cosine-weighted visibility within
the radius), stable under TAA, cheap after temporal reuse, and it also produces the bent
normal. **Limitations.** Depth-buffer only (no off-screen or behind-surface occluders, and
it over-darkens thin geometry because the depth buffer has no thickness), half-res halos at
silhouettes, and ghosting if history rejection is weak. **Cost.** 12 depth reads per
half-res pixel is about 3 per full-res pixel, plus 4 history taps and the upsample [inf from
counts].

**Belgium now** (`lib/lighting/screen_space.glsl`, `deferred4`) [src]: full-res
cosine-hemisphere point SSAO, 4/6/8/12/16 samples by preset, fixed radius 0.65 blocks, a
binary occlusion test with a range check, no own temporal filter (TAA averages it), no bent
normal, no multi-bounce. Sky ambient uses two scalars (`fsSkyIrradianceUp`/`Side`,
azimuth-averaged).

**Gap / adopt.**
1. Implement GTAO from the paper as a half-res `deferred` pass. That needs a new slot before
   `deferred4`, and both new targets should get `size.buffer` 0.5. Output AO + bent normal +
   depth, with its own reprojected accumulation (a pixel-age scheme like the one above is
   standard; Yang et al. 2020 §5).
2. Use the paper's multi-bounce fit with the *actual* albedo from `colortex1` instead of a
   constant.
3. Add an L1 SH projection of the sky-view LUT in `begin_a.csh`: 4 RGB coefficients in
   FrameState (48 bytes; the 1024-byte SSBO has room). Evaluate it with the bent normal
   (Ramamoorthi & Hanrahan 2001). This also fixes the current lack of sun-side sky
   brightening on vertical walls.
4. Specular occlusion from bent normal and AO (Lagarde & de Rousiers 2014 §4.10.2) for the
   sky-view specular ambient.
5. Keep SSAO as the LOW/MEDIUM path. GTAO on HIGH+.

### 3.2 Coloured voxel light propagation (flood fill)

**Purpose.** Coloured, occlusion-aware block light without ray tracing.

**Photon** (`program/lpv/floodfill.csh`, `include/lighting/lpv/*.glsl`) [src]:

* **Voxelisation** in the shadow vertex stage: terrain render stages only; one voxel write
  per block from a vertex at the block's lower grid corner (`at_midBlock` gives the block
  centre). Blocks whose vertices do not reach a grid corner are flagged as "transparent"
  (bit 7), so non-full emitters and props pass light. Leaves and SSS blocks are remapped to a
  light-grey tint. The image is `voxel_img` R8UI, **cleared every frame**, 64³…512³
  (default 128³ = 2 MB).
* **Volume placement**: by default the volume is shifted *ahead* of the camera along the
  look direction, so only 15 % of it lies behind the player (`VOXEL_VOLUME_CENTER_AHEAD`).
  Old-to-new alignment is applied when reading the previous volume.
* **Propagation**: one step per frame, ping-pong `light_img_a/b` (RGBA16F, persistent).
  Each voxel = emission + tint × (weighted mean of itself and its 6 neighbours of last
  frame). Centre weight is 1.05 and the weights sum to 1, so there is no explicit decay;
  falloff comes from diffusion alone. Colours are **squared** on write and **square-rooted**
  on read.
* **Colour tables**: a 48-emitter × 16-tint table is written once by a `setup.csh` into a
  48×2 image, and `block.properties` ids 32–79 and 80–95 index it.
* **Shading**: trilinear sample at position + 0.5·normal, × AO; the vanilla lightmap is
  added where the volume is dim (weight `exp2(−4·L)`); fade to vanilla over the last 25 % of
  the volume; Darkness-effect modulation. The volume also lights **volumetric fog**
  (`include/fog/lpv_fog.glsl`, 24 steps) on Ultra.

**Analysis [inf].** With weights summing to one and a constant source, the steady state of a
3-D neighbour average approximates the discrete Green's function of the Laplacian, which
falls off roughly as 1/r. The square/square-root encoding then reshapes that curve. So
Photon's light *intensity* comes from the volume and can differ from Minecraft's
15-block linear falloff. Light also reaches only as far as the diffusion has propagated:
about 1 block per frame, so a new torch takes ~15 frames to reach full reach, and fast
camera motion shifts the "ahead" volume.

**Belgium now** (`lib/lighting/floodfill.glsl`, `program/shadowcomp_floodfill.glsl`) [src]:
128×64×128 R32UI voxel map centred on the player (word = opaque/glass/foliage flags,
material, emission level, RGB565 tint); 6-neighbour mean × 0.97 per step, foliage × 0.7,
glass × tint; **only the chroma is used**, and intensity stays the vanilla lightmap
(guaranteed no leaking beyond vanilla). The gradient gives a block-light specular
direction. Emitters with `at_midBlock == 0` (`voxelizeLightBlocks` light blocks) need
checking (§2 row 15).

**Comparison.** Belgium's chroma-only design is deliberately safer. Photon gets
occlusion-correct *intensity* (light does not wrap around walls the way the vanilla
lightmap does) but must blend back to vanilla at the edges and where the volume is dim.
Belgium's 64-block vertical extent is half of Photon's default.

**Adopt.**
1. Optional "volume-driven intensity" mode: use the volume's luminance where the volume
   confidence is high, and the vanilla lightmap elsewhere or at the edges, with the
   architecture's no-leak rule kept as the default.
2. Look-ahead volume placement (shift the centre along the horizontal look direction,
   quantised to whole blocks so re-alignment stays an integer shift).
3. Light the volumetric fog (`composite1`) from the volume: one trilinear fetch per VL step
   gives coloured torch haze in caves.
4. Move emitter/tint colours from shader constants into a small setup-written image or SSBO
   only if the table grows. It is not needed now.

### 3.3 Cloud layering and weather variation

**Purpose.** A sky that changes day to day with physically plausible cloud types per layer.

**Photon** (`include/sky/clouds*.glsl`, `include/weather/*.glsl`, `program/p0_clouds_prep`,
`d1_clouds`, `d2_clouds_upscaling`) [src]:

* **Weather state** = three scalars, *temperature, humidity, wind* ∈ [0,1], each a slow 1-D
  noise of world age (period scaled by settings), shifted by time of day, the biome
  temperature/humidity uniforms, `wetness` (rain) and user biases. **Every layer parameter
  is a function of this state** (`get_clouds_parameters`): coverage, cumulus↔stratus blend,
  detail weights, edge sharpening, altitude scale, extinction, and the crepuscular-ray
  amount.
* **Layers**, marched front to back with early exit at transmittance < 10⁻³:
  1. Cumulus / stratocumulus / stratus (default base 1200 m; 40 steps at the horizon,
     20 at the zenith; 6 light steps; 2 ambient steps);
  2. Altocumulus / altostratus (3200 m; 12/6 steps; 4 light; 2 ambient);
  3. Cumulus congestus (a tall, distant layer from 400 m, blended in only for hot, humid,
     windy weather; 20 steps);
  4. Planar cirrus + cirrocumulus;
  5. Noctilucent clouds at 80 km (rare, from a per-day hash).
* **Coverage map**: the cumulus local coverage is precomputed each frame in `prepare` into a
  512² target (`colortex8`, together with the cloud shadow map; `size.buffer` is 512 512,
  although the comment in Photon's `buffers.glsl` says 256×256) with a **radial
  distortion** that concentrates texels near the player (covering 150 km).
* **Lighting**: Beer–Lambert toward the light with geometrically growing steps (×2),
  analytic sky and ground ambient terms, a powder term, and a multi-scattering octave loop
  that reduces extinction and the phase anisotropy per octave (Wrenninge 2013; Hillaire
  2016).
* **Reconstruction**: clouds render **one pixel of each N×N block per frame** (default N = 4,
  so 1/16 of the pixels) in a fixed checkerboard order into a 1/N-sized target. `d2`
  reprojects full-res history using the per-pixel **apparent distance** (the
  transmittance-weighted distance of the cloud contribution, stored alongside), keeps
  history for pixels not rendered this frame, invalidates on disocclusion, NaN or hand,
  clamps to the neighbourhood **only when moving fast relative to the clouds**, and caps the
  pixel age at 20.

**Advantages.** The weather model gives variety with coherent cause and effect (humid +
warm + windy → congestus, cold + calm → stratus sheet), and is cheap (a few scalars per
frame).
Apparent-distance reprojection is correct for every layer height, whereas a single
mid-altitude plane is correct only for one layer. **Limitations.** Checkerboard 1/16 needs
≥16 frames to converge, so it smears during rapid camera rotation or fast cloud wind. The
weather is global (not spatial), so there are no fronts. **Cost.** Steps × resolution: at
N = 4 a frame marches 1/16 of the pixels. The reconstruction is a few taps per full-res
pixel [inf].

**Belgium now** [src, `ORIGINAL_ARCHITECTURE.md §7`]: one type-aware slab (stratus …
cumulonimbus with anvil) from a weather map, 2-D cirrus, two-rate march (fix from the first
in-game run), half-res by default (`CLOUD_RES`), reprojection at the slab's mid-altitude
intersection, neighbourhood clamp, history confidence. Daily variation exists
(`CLOUD_DAILY_VARIATION`) but not as a weather state driving every layer.

**Adopt.**
1. A FrameState **weather vector** (temperature, humidity, wind, plus storminess from
   `thunderStrength`), smoothed in `begin.csh`, from which coverage, type bias, wind speed,
   cirrus amount, fog density and rain haze all derive. One cause, many consistent effects.
2. Store an **apparent depth** per cloud pixel (alpha-weighted distance) in the cloud target
   and reproject with it instead of the mid-altitude plane. This removes parallax ghosting
   for low and high clouds.
3. Make reconstruction an option between the current half-res and a checkerboard ¼×¼ mode
   for LOW/MEDIUM, with clamping only above a relative-motion threshold.
4. A second volumetric layer (alto-) is the next visual step. It should share the light
   march with the existing code, and its own step budget must come out of the profiling
   (milestone H).

### 3.4 Screen-space reflections and temporal reflection filtering

**Photon** (`include/lighting/specular_lighting.glsl`, `include/misc/raytracer.glsl`) [src]:

* Reflections are computed in **deferred** shading (before translucents) and sample the
  **previous frame's final HDR** (`colortex5`, the TAA output, mipmapped via
  `colortex5MipmapEnabled` in `deferred4`) at the **reprojected** hit position. Last frame's
  fog in-scatter (`colortex7`) is subtracted from it, and analytic fog is re-applied along
  the reflected segment.
* Rough surfaces: `SSR_RAY_COUNT` (default 4) rays sampled with **GGX VNDF** (Heitz 2018);
  the mip level grows with roughness (up to 5) to pre-blur; the estimator weights by the
  Smith terms. Smooth surfaces: one ray. Steps: 16 smooth / 8 rough + 4 binary refinement.
  Depth tolerance grows with step length (credited to DrDesten). Border fade.
* Miss / off-screen: the sky from the 192×108 sky map, faded by sky light (underground =
  black).
* **No dedicated temporal reflection denoiser was found** [not found]. Stability relies on
  multiple rays + mip pre-blur + TAA.

**Belgium now** (`composite_water.glsl`, `lib/reflections/ssr.glsl`) [src]: one ray per
pixel, linear march (12–64 steps) + binary refinement, **current-frame** `colortex0`, half
vector sampled from the GGX NDF (not VNDF) with an unweighted estimator, mirrored below the
geometric normal; fallback to the sky-view LUT occluded by sky light; TAA resolves the noise.

**Gap / adopt (all independent implementations of the cited papers).**
1. **VNDF sampling** (Heitz 2018) with the proper estimator weight (F·G₂/G₁). This removes
   back-facing samples and the NDF-sampling bias at grazing angles.
2. **Roughness-dependent pre-filtering**: either sample a mipmapped previous-frame colour
   (`colortexNMipmapEnabled` is regenerated before every pass that declares it, [doc]
   row 7), or a cheap half-res blur. Iris regenerates the chain each time, so declare it in
   exactly one pass [doc].
3. **Hit reprojection into the previous frame** lets SSR run *before* the water and
   translucent overlay without self-feedback problems, and gives multi-bounce reflections
   for free [inf].
4. A **temporal reflection filter** is not present in Photon either. If ghosting on rough
   metal shows up in game, the literature path is Stachowiak 2015 (ray reuse + temporal
   with hit-distance-based reprojection).
5. Hierarchical-Z tracing (McGuire & Mara 2014) is already in `PERFORMANCE.md` as a known
   inefficiency. Keep it behind the measurements.

### 3.5 Shadow filtering

**Photon** (`include/lighting/shadows/pcss.glsl`, `distortion.glsl`, `ssrt.glsl`) [src]:
Iris' own shadow matrix (`shadowModelView`); distortion by a *quartic* length (smaller
distortion along diagonals) with factor 0.85 and depth scale 0.2; normal-offset bias that
grows with distance (credited to Complementary; do not copy). PCSS (Fernando 2005): blocker
search with **3** Vogel-disc taps (more when SSS needs a thickness), penumbra =
16·(d_receiver − d_blocker)/d_blocker × scale, **enlarged up to 5× under cloud shadow**
(overcast softening), PCF tap count *scales with filter radius* between 6 and 12. Below a
minimum radius it blurs and then sharpens (anti-aliasing). Coloured shadows from
`shadowtex0`/`shadowtex1`/`shadowcolor0`. Screen-space shadow ray (10 steps, geometric step
growth, assumed thickness 10 blocks) supplements the map. Profile defaults: 2048² at 128
blocks even on Ultra (only 1024² on Low).

**Belgium now** [src, `ORIGINAL_ARCHITECTURE.md §4`]: own light matrix, hyperbolic radial
distortion with analytic texel size (drives the bias), five tiers up to 12-tap blocker search
+ 32 PCF taps, penumbra from the real sun or moon angular radius, contact shadows HIGH+.

**Assessment.** Belgium's model is already more physically grounded (angular light radius,
analytic texel size). Worth adopting:
1. **Adaptive tap count**: taps ∝ penumbra size in texels, clamped. Small penumbrae (most
   pixels at noon) then cost fewer taps than the fixed 16/32 [inf].
2. **Overcast softening**: scale the effective light radius by cloud-shadow transmittance
   (diffuse sky dominates under cloud), consistent with Belgium's physical model if the
   radius is derived from the sun+bright-cloud solid angle rather than a constant
   multiplier.
3. Contact shadows with geometrically growing steps and a distance-dependent ray length
   (Belgium uses 10 uniform steps over 0.55 blocks).

### 3.6 Temporal accumulation and denoising (TAA and per-effect histories)

**Photon** (`c3_taau_prep`, `c4_taa_exposure`) [src]: R2-sequence jitter (custom uniform);
Catmull–Rom current and history fetch with a confidence term (Yang et al. 2020 §5.1);
blending in a **Reinhard-compressed** space; YCoCg AABB clipping (Pedersen 2016) with
optional variance clipping (Salvi 2016); flicker reduction near the box edge; history weight
`max(1/age, mix(0.35, 0.10, distance))`; off-centre rejection. Optional TAAU at a render
scale of 0.5–1.0 (default 0.75 when enabled, off by default) that also drives Voxy's
`renderScale` and Photonics. Every effect with its own history (AO, clouds) keeps a *pixel
age* and rejects on depth.

**Belgium now** (`program/composite_taa.glsl`) [src]: Halton jitter, closest-depth motion,
3×3 YCoCg variance clip (γ = 1.25), blend 0.08–0.25 by speed, compression `c/(1+L(c))`.

**Findings.**
1. **Compression is not exposure-aware** [inf, from code]. Belgium keeps radiance absolute
   until `final` (`SUN_IRRADIANCE = 4`; night exposure up to EV 9). By day L ≈ 1 and the
   compression works. At night radiance is ~10⁻³, so `c/(1+L)` is effectively linear, and
   torches and fireflies dominate the variance box. That is exactly what the compression is
   meant to prevent. **Fix:** compress `c·E` with the previous frame's exposure E from
   FrameState (and uncompress by the same E), as Photon effectively does by working near the
   display range.
2. **Voxy LODs are not jittered** [src]: Belgium's `voxy.json` has no `taaOffset` and there
   is no `voxy_taa.glsl` in `world*/`. Voxy's patch then uses no offset (Voxy
   `IrisShaderPatch.taaOffset` defaults to null). Vanilla and DH geometry are jittered;
   Voxy terrain is not, so TAA cannot anti-alias it and its edges flicker against jittered
   neighbours. **Fix:** provide the jitter via `taaOffset` (and `useViewportDims`), using the
   same sequence as `lib/core/taa_jitter.glsl`.
3. Effect histories (cloud, SSGI) should keep an explicit **pixel age** rather than a fixed
   blend. That gives fast convergence after disocclusion and low noise once converged
   (Photon's AO/cloud pattern; Yang et al. 2020).
4. Catmull–Rom history sampling (5-tap optimised form) reduces the blur of bilinear
   history under motion (Karis 2014).

### 3.7 Exposure, tonemap and bloom ordering

**Photon** [src]:
* Order (`c4` → `c5..c18` → `c19`): TAA → bloom down/up chain on **pre-exposure** HDR (Call
  of Duty AW downsample, Jimenez 2014) → `c19`: `mix(scene, bloom, 0.12·intensity)`
  (energy-conserving) → × exposure → vignette → input grade (white balance in XYZ) →
  tonemap (default **Lottes 2016**; ACES fit/full, Hejl, Uncharted 2, Reinhard and others
  selectable; split-screen comparison mode) → output grade → Rec.2020 → Rec.709. Photon's
  working space is **linear Rec.2020** (`include/utility/color.glsl`).
* Exposure: **manual EV by default** (`AUTO_EXPOSURE_OFF`). The optional modes are
  "simple" (top mip of `colortex0`) and a **histogram** (32–128 bins of log luminance
  built in the *vertex* stage of the TAA pass from a mipmapped `colortex0`, median at a
  configurable percentile). Exposure is stored in `colortex5.a` of texel 0. Adaptation is
  asymmetric and frame-time-correct, `exp(−rate·Δt)`. Calibration follows the EV100/sensor
  model (Lagarde & de Rousiers 2014).

**Belgium now** [src]: `composite6.csh` meters a centre-weighted 64×64 grid with
`textureLod(colortex0, uv, 0)`, i.e. **4096 point samples at mip 0**, as a log average, key
0.18 with a dark-scene reduction, asymmetric rates, EV clamp [−2, 9]; final: energy-conserving
bloom mix → exposure → scene-referred grade → tone curve → display grade → sharpen →
dither. Same ordering as Photon; working space Rec.709.

**Findings.**
1. **Point-sampled metering aliases** [inf]: a single bright pixel (lava, sun glint) can
   enter or leave the 64×64 grid as the camera moves, so exposure jitters. Fix: meter from a
   low bloom-pyramid level (already computed, pre-filtered), or enable a mip chain on
   `colortex0` for the metering pass only.
2. A **histogram with percentile clipping** (ignore the brightest ~5 % and darkest ~40 %)
   is more robust than the log mean for scenes with sky + cave mixes. It fits in the
   existing single-workgroup compute with shared-memory bins.
3. Adaptation is already frame-time-correct in Belgium (`1 − exp(−rate·Δt)`, Δt clamped to
   0.25 s) [src]. No change needed.
4. A tonemap **comparison/split view** (debug option) would help milestone I (visual
   cohesion) without changing the default curve.
5. A Rec.2020 working space is a larger change (all colour constants, LUT outputs and
   profile scalars). Not recommended now; note it only as the reason Photon's saturated
   lights do not clip [inf].

### 3.8 Distant Horizons and Voxy integration

**Photon** (`include/misc/lod_mod_support.glsl`, `program/voxy.json`, `shaders.properties`)
[src]:
* A **combined depth buffer**: `colortex15` R32F, written in `deferred2` when an LOD mod is
  active, holding vanilla and LOD depth in one *combined projection* (vanilla FOV, near =
  vanilla near, far = LOD render distance). The projection is built as custom uniforms
  (DH) or in-shader (Voxy). GTAO, SSR and clouds then trace a single depth buffer with a
  single matrix, so screen-space effects work on LODs (GTAO radius ×3 there).
* DH: `dh_terrain`/`dh_water`, overdraw distance + fade length options, `dhShadow.enabled =
  false`.
* Voxy: `voxy.json` v1 with `excludeLodsFromVanillaDepth`, translucent draw buffers
  13 and 16 (`colortex16` only exists under Voxy, i.e. it relies on the 32-buffer limit),
  `taaOffset` (scaled 0.66 without TAAU), `useViewportDims`, `renderScale` = TAAU scale, and
  the JSON is run through the Iris preprocessor (settings included inside an unused string
  field) so options can switch Voxy behaviour.

**Belgium now** [src]: per-pixel data adapters (`lib/compat/lod.glsl`, `scenePoint`) choose
vanilla or LOD depth and projection. SSR, puddles, SSAO and SSGI are off on LODs.
`excludeLodsFromVanillaDepth = true`. No `taaOffset` (§3.6).

**Adopt.**
1. **Voxy jitter** (`taaOffset`): a small change with clear benefit (§4, step 1).
2. A **combined linear-depth target** (R32F, full res, written once in `deferred` before
   SSGI) would let SSAO/GTAO, contact shadows and SSGI run on LOD pixels with one code path.
   Linear view depth is simpler and more precise than Photon's combined projection [inf].
   Gate it on `DISTANT_HORIZONS || VOXY`, and keep the slot below 16 so it works on older
   Iris.
3. Preprocessing `voxy.json` (confirmed by Photon's file, which uses `#ifdef` and
   `#include`) allows the Voxy `renderScale` and jitter to follow pack options.

### 3.9 Performance profiles and cost control

**Photon** [src]: four profiles (`profile.low…ultra`) that toggle a small set of options:
shadow resolution (1024² on Low, 2048² otherwise), PCF, coloured shadows, variable
penumbra, entity and block-entity shadows, SSR, SSAO vs GTAO, VL, coloured light shafts,
caustics, water parallax, **coloured lights only on Ultra**, screen-space shadows. Cloud
step counts, TAAU and cloud checkerboard factor are *not* in the profiles. Structural cost
control: `size.buffer` for every reduced-res target (AO, fog 0.5; clouds 1/N; sky map
192×108; coverage/shadow map 512²), `program.*.enabled` for optional passes, and a
vendor-specific extra pass (`composite22`) enabled only for Intel on Windows (a driver
workaround for the AO history flip).

**Belgium now** [src]: five presets that also scale shadows to 8192² and 256 blocks, cloud
quality and resolution, sim size, SSGI rays/steps; `program.*.enabled` gating; `scale.*` only.

**Adopt.**
1. `size.buffer` for `colortex8` (clouds, `CLOUD_RES`), `colortex10` (VL 0.5),
   `colortex12/13` (SSGI 0.5). Each is written by exactly one pass of that size (§2 row 8),
   so the change is mechanical: drop the matching `scale.*`, address texels in the small
   buffer, upsample by UV. At 1440p this frees about ¾ of 4 × 29.5 MB ≈ 88 MB [inf from
   `PERFORMANCE.md` sizes] and reduces cache pressure.
2. A **vendor-macro escape hatch** (`MC_GL_VENDOR_*`, used by Photon) for driver issues once
   in-game reports exist. Do not add any until a bug is observed.
3. `indirect.<pass>` dispatch from the water-sim control SSBO: a sleeping simulation then
   dispatches 0 groups instead of N²/256 early-out groups (§2 row 13).
4. Keep CINEMATIC's 8192² shadow map clearly labelled as a screenshot preset (1.07 GB,
   `PERFORMANCE.md`).

### 3.10 LabPBR handling (short, mostly covered already)

Photon decodes LabPBR 1.3 like Belgium (F0 < 230, metals 230–237, porosity ≤ 64, SSS ≥ 65,
emission alpha < 255) [src]. For hardcoded metals Photon uses an **F82-tint Schlick model**
(Hoffman 2019) with tabulated f0/f82 per metal (credited to Jessie-LC); Belgium evaluates the
**exact conductor Fresnel** from complex IOR, which is more accurate and has no table to
license. No change recommended. Photon also has optional hard-coded emission for vanilla
blocks derived from albedo hue. Belgium's `synthesizeSpecular` covers the same need.

### 3.11 Debugging patterns (shaderLABS, Photon)

* On-screen **numeric text** (shaderLABS Snippets text renderer, public domain; Photon has
  its own `text_rendering.glsl`): print FrameState values (EV, weather vector, light choice,
  `fsHeader`, water-sim state) instead of inferring them from colours.
* A **histogram debug view** (Photon `DEBUG_VIEW_HISTOGRAM`) for exposure tuning.
* A **sampler viewer** (Photon `DEBUG_VIEW_SAMPLER`): show any colortex or image.
  Belgium's 22 views (`DEBUGGING.md`) are fixed per quantity.

---

## 4. Recommended next steps (prioritised)

Ordered by benefit per risk. Every item is an independent implementation from the cited
papers or platform documentation; nothing is copied from Photon. Items 1–3 are small and
should precede milestone H's measurements, because they change what will be measured.

| # | Step | Why | Section | Size |
|---|---|---|---|---|
| 1 | Add Voxy TAA jitter (`taaOffset` + `useViewportDims` in `voxy.json`, same sequence as `taa_jitter.glsl`) | Voxy terrain is currently un-jittered under TAA | 3.6 #2, 3.8 | XS |
| 2 | Exposure-aware TAA compression (`c·E_prev`) | Night-time TAA clamping is effectively uncompressed | 3.6 #1 | XS |
| 3 | `size.buffer` for colortex8/10/12/13; remove matching `scale.*` | ~88 MB at 1440p, less bandwidth; documented inefficiency | 2 row 8, 3.9 | S |
| 4 | Pre-filtered exposure metering (bloom level or mip) + optional histogram/percentile | Stops metering flicker from point samples | 3.7 | S |
| 5 | Fix the doc mismatches (skyViewLut 192×216; colortex limit 32 since Iris 1.10.5; barrier bits); decide whether light blocks (`voxelizeLightBlocks`, `at_midBlock = 0`) should get a default emitter level in the voxeliser | Keeps the contract honest | 2 rows 9, 15 | XS |
| 6 | GTAO (half-res, own pixel-age accumulation, bent normal, albedo multi-bounce) for HIGH+ | Better contact darkening at lower cost per full-res pixel; feeds #7 | 3.1 | M |
| 7 | L1 SH sky irradiance from the sky-view LUT in `begin_a`, evaluated with the bent normal; specular occlusion | Directional sky light (sun-side walls) and correct occluded ambient | 3.1 #3–4 | S–M |
| 8 | SSR: VNDF sampling with the correct weight; roughness pre-filter; previous-frame hit reprojection | Less noise and bias on rough metal and wet surfaces | 3.4 | M |
| 9 | Weather vector in FrameState driving clouds, fog and rain haze; apparent-depth cloud reprojection | Coherent daily variety; removes layer-height reprojection error | 3.3 | M |
| 10 | Adaptive PCF tap count + overcast penumbra softening | Lower cost for sharp shadows; plausible overcast light | 3.5 | S |
| 11 | Flood fill: look-ahead volume, volume-lit VL fog, optional volume-driven intensity | Coloured cave haze; more useful volume | 3.2 | M |
| 12 | Combined linear-depth target for LOD-aware screen-space effects | One code path for AO/GI/contact shadows on DH/Voxy | 3.8 #2 | M |
| 13 | Debug: numeric text overlay, sampler viewer, tonemap split view | Faster diagnosis from user screenshots | 3.11, 3.7 #4 | S |
| 14 | `indirect.*` dispatch for the sleeping water simulation | Zero-cost sleep | 3.9 #3 | S |
| 15 | Second volumetric cloud layer; checkerboard reconstruction mode for LOW/MEDIUM | Visual richness / low-end cost | 3.3 #3–4 | L, after profiling |

Each item must update `FEATURE_STATUS.md` honestly ("implemented, untested in game") and
pass `tools/validate.py` before commit. Items 6, 8, 9 and 11 also need a CPU reference test
in `tools/tests/` where an algorithm can be checked offline (GTAO arc integral vs Monte
Carlo; VNDF sample distribution vs D·G₁/(4 N·V); apparent-depth reprojection on a synthetic
two-layer sky).

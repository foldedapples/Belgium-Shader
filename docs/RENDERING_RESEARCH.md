# Rendering Research Report

Scope: technical study of three reference shaderpacks (Halcyon, Eclipse, Bliss), the Iris
loader they target, and the Voxy / Distant Horizons integration surfaces. The purpose is to
understand the *engineering problems* each pack solves so that Belgium Shaders can solve them
with an independent design. No source code from the references is reproduced here or in the
pack.

Snapshot studied: default branches cloned 2026-10-24 (Halcyon `1.0.0-alpha.22`, Iris branch
`26.1` at `bff1e69`, Voxy at its 2026-10-19 head).

---

## 1. Licensing findings (decides what we may reuse)

| Project | License as published | Consequence for us |
|---|---|---|
| Bliss (X0nk) | `LICENSE.md`: "© 2020 Chocapic13. All rights reserved." | **No code, constants, tables or textures may be reused.** Study only. |
| Eclipse (Merlin1809) | Same notice (Bliss/Chocapic13 derivative) | Same as Bliss. Study only. |
| Glimmer (jbritain) | MIT | Reuse legally possible with notice, but **we choose not to**: the brief requires an independent engine. |
| Halcyon (Freak4U) | MIT, copyright held by jbritain (Glimmer base) | Same as Glimmer. Behavioural reference only. |
| Halcyon assets | Moon from NASA SVS CGI Moon Kit; Milky Way from NASA SVS Deep Star Maps; star catalogue from Hipparcos/Yale BSC; Tony McMapface LUT (MIT) | We source our own copies directly from the original providers (see `THIRD_PARTY_ASSETS.md`). We do not ship Halcyon's processed files. |

Halcyon itself contains third-party MIT snippets (afl_ext ocean waves, Dave Hoskins hashes, a
Shadertoy port of Hillaire's atmosphere). None of those are used here either; where we use the
same *published technique* (e.g. Hillaire 2020 LUTs) we implement from the paper.

## 2. Platform facts verified in Iris source (branch 26.1)

These were read directly from Iris Java sources rather than assumed:

* **Program groups and order.** `ProgramArrayId` defines `setup`, `begin`, `shadowcomp`,
  `prepare`, `deferred`, `composite` arrays of 100 slots each. Every slot may be a fragment
  pass (`.vsh/.fsh`), a compute pass (`.csh`), plus up to 26 extra computes `_a.csh … _z.csh`.
  Per-frame order: `begin → shadow → shadowcomp → prepare → gbuffers(opaque) → deferred →
  gbuffers(translucent) → composite → final`. `setup` runs once per pipeline build.
* **Compute barriers.** `ComputeProgram.dispatch` issues
  `glMemoryBarrier(IMAGE_ACCESS | TEXTURE_FETCH | SHADER_STORAGE)` before every dispatch unless
  the pack sets `allowConcurrentCompute=true`. Consecutive simulation steps are therefore
  correctly ordered without extra work.
* **Dispatch sizing.** `workGroups = ivec3(...)` is absolute; `workGroupsRender = vec2(sx,sy)`
  yields `ceil(ceil(width*sx)/localSize.x)` groups.
* **SSBOs.** `bufferObject.N = bytes` with `N ≤ 12`. Buffers are allocated with
  `glBufferStorage` and **zero-filled** with `glClearBufferSubData` — a zeroed header is a
  reliable "never initialised" signal.
* **Custom images.** `image.<name> = <sampler|none> <format> <internal> <type> <clear> <relative> <w> [h] [d]`.
  At most **16** custom images. `clear=true` images are cleared every frame (`ImageClearPass`),
  so persistent simulation state must use `clear=false`.
* **Feature flags.** `SEPARATE_HARDWARE_SAMPLERS, HIGHER_SHADOWCOLOR, CUSTOM_IMAGES,
  PER_BUFFER_BLENDING, COMPUTE_SHADERS, TESSELLATION_SHADERS, ENTITY_TRANSLUCENT,
  REVERSED_CULLING, BLOCK_EMISSION_ATTRIBUTE, CAN_DISABLE_WEATHER, SSBO, FADE_VARIABLE,
  TEXTURE_FILTERING`.
* **Shadow culling.** `shadow.culling=false` selects a *distance-only* `BoxCuller` around the
  camera (independent of light direction). `true` = advanced frustum culling built from Iris'
  own shadow matrix; `reversed`/`safe_zone` = safe-zone culling. A pack that renders the shadow
  map with **its own light matrix** must use `false`, otherwise geometry outside Iris' frustum
  goes missing.
* **Iris-exclusive uniforms useful for water interaction:** `feetInWater`,
  `inSwimmingAnimation`, `isRiding`, `vehicleInWater`, `vehicleId` (resolved through
  `entity.properties`), `vehicleLookVector`, `relativeVehiclePosition`, `relativeEyePosition`,
  `eyePosition`, `playerLookVector`, `lightningBoltPosition`, `seaLevel`, `thunderStrength`.
  Eclipse gates these behind `IRIS_VERSION >= 11004`, consistent with their introduction in
  Iris 1.10.4.
* **Standard macros:** `MC_VERSION, IRIS_VERSION, IS_IRIS, DISTANT_HORIZONS, MC_NORMAL_MAP,
  MC_SPECULAR_MAP, MC_HAND_DEPTH, DH_BLOCK_*` and more.
* **DH uniforms:** `dhNearPlane, dhFarPlane, dhRenderDistance, dhProjection(+Inverse,
  Previous)`, samplers `dhDepthTex0/1`; programs `dh_terrain, dh_water, dh_generic,
  dh_shadow`.

## 3. Voxy integration surface (verified in Voxy source)

* Voxy injects three optional files per dimension folder: `voxy.json`, `voxy_opaque.glsl`,
  `voxy_translucent.glsl` (and optionally `voxy_taa.glsl`).
* `voxy.json` (`version` must equal **1**) declares `opaqueDrawBuffers`,
  `translucentDrawBuffers`, `uniforms` (names forwarded from Iris), `samplers`, `ssbos`
  (binding → struct body), per-buffer `blending`, `taaOffset`, `excludeLodsFromVanillaDepth`,
  `renderScale`, `useViewportDims`, `useDynamicFarPlane`.
* The pack implements `void voxy_emitFragment(VoxyFragmentParameters p)` where `p` holds
  `sampledColour, tile, uv, face (0..5), modelId, lightMap, tinting, customId` (customId =
  Iris block id). Derivatives/normals are **not** provided; the face index is the only normal.
* Voxy renders with reversed-Z internally and rewrites `gl_FragCoord.z` to `1 - z` in the
  patch, so pack code sees conventional depth.
* Uniforms `vxProj(+Inv/Prev)`, `vxModelView(+Inv/Prev)`, `vxViewProj*`, `vxRenderDistance`,
  `vxNearPlane`, `vxFarPlane`; depth samplers `vxDepthTexOpaque`, `vxDepthTexTrans` (aliased to
  `dhDepthTex*` when DH is absent).

## 4. Subsystem analysis

### 4.1 What each rendering stage accomplishes

| Pack | Organisation |
|---|---|
| Halcyon | Thin `world*/` wrappers include `program/*.glsl`. `setup` computes static LUTs; `prepare*` computes sky LUTs and the water simulation (one 1-thread *control* compute followed by up to three *step* computes); `shadowcomp` does flood-fill light propagation; `deferred` volumetric clouds, sky, SSGI trace/temporal/apply; `composite` fog, god-rays, translucents, exposure (write→compute→apply), motion blur, DoF, temporal filter, bloom (down/up chain over ~9 passes), FXAA; `final` tonemap/grade. |
| Bliss | Single source tree `dimensions/*` compiled per dimension via `#define`. `deferred` = sky/fog LUTs into a small buffer + cloud raymarch; opaque **lighting happens in `composite1`**, after translucent gbuffers; `composite` = fog behind translucents; `composite2` = translucent + water compositing; later composites = TAA (optional upscaling), bloom, DoF, final. Compute used optionally (`setup` block-data table, `shadowcomp` light-propagation volume). |
| Eclipse | Bliss structure plus `begin.csh` (scene controller: per-frame cloud layer parameters, custom celestial vectors and **custom shadow matrix** in an SSBO), `prepare*.csh` (water ripple simulation control + two ping-pong step passes), tessellation (`.tcs/.tes`) for grass. |

### 4.2 Features that need persistent GPU data
* Interactive water: height/velocity fields (Halcyon: two RG16F images; Eclipse: RG16F + RGBA16F
  images) and a small control SSBO (window origin, last player/boat position, accumulator).
* Exposure adaptation: a luminance value carried across frames (SSBO or 1×1 history).
* Temporal accumulation: history colour buffers with `colortexNClear=false` (TAA, clouds, GI).
* Flood-fill / LPV colour light: two 3-D light volumes ping-ponged across frames.
* Celestial/scene state (Eclipse): custom moon vector and shadow matrix in an SSBO.
* Static LUTs (transmittance, multiple-scattering): built once in `setup`.

### 4.3 How water interacts with player and vehicle movement
Both Halcyon and Eclipse use the same platform facts: the player's feet position is derived
from `cameraPosition - relativeEyePosition`; contact from `isEyeInWater` / `feetInWater`; boats
from `isRiding && vehicleId == <boat id>` plus `relativeVehiclePosition` and
`vehicleLookVector`. Velocity is obtained by differencing positions stored in an SSBO across
frames; teleports are detected by implausibly large deltas. The simulated domain is a
camera-following grid addressed toroidally so that scrolling requires no copy. Neither pack
can see *other* entities — the uniforms only describe the local player and their vehicle.
Halcyon's sim is a damped wave equation with a restoring spring term; Eclipse uses a
Shadertoy-derived ripple propagation with a scaled grid. Both are 2-D and assume a single
water plane height.

### 4.4 How clouds are sampled and illuminated
All three march a height-bounded slab: weather/coverage map → base shape noise (3-D) →
height profile per cloud type → detail erosion near edges. Lighting = Beer–Lambert transmittance
toward the sun with a few exponentially growing steps, a dual-lobe Henyey–Greenstein phase and
an octave-style multiple-scattering approximation, plus a height-graded ambient term. Bliss uses
up to three stacked layers (two cumulus-like volumes + an altostratus sheet); Eclipse adds
cirrus/cumulonimbus layers driven by a per-frame "scene controller"; Halcyon a single slab with
type-dependent tops plus a 2-D cirrus layer and coarse/fine two-speed marching.

### 4.5 How the atmosphere integrates with sunlight
Halcyon/Glimmer use Hillaire-style LUTs (transmittance, multi-scatter, sky-view, aerial
perspective). Bliss uses a cheaper analytic sky gradient plus a tiny precomputed skybox
written in `deferred`. In both, the *same* sun colour (top-of-atmosphere irradiance multiplied by
transmittance at the camera) is published through a buffer so terrain, clouds and water receive
a consistent light.

### 4.6 How sky and celestial objects are rendered
Vanilla sun/moon are disabled (`sun=false`, `moon=false`) and the disks are drawn analytically
in the sky pass. Halcyon samples an equirectangular NASA moon map onto a reconstructed sphere
with a Lommel–Seeliger reflectance and computes eclipses from an orbital model scaled to the
8-day Minecraft lunar cycle. Eclipse moves the moon to a custom orbit and therefore also
**recomputes the shadow matrix** so night shadows follow the custom moon.

### 4.7 How shadows are passed between stages
Shadow pass writes `shadowtex0` (all casters), `shadowtex1` (opaque only) and `shadowcolor0/1`
(translucent tint, water flags). All three apply a radial distortion (log or power curve) to
concentrate resolution near the player; the same distortion is re-applied when sampling.
Comparing `shadowtex0` vs `shadowtex1` identifies light passing through water/glass, which is
what enables coloured shadows and caustics.

### 4.8 How material data reaches lighting
Gbuffer programs decode LabPBR `normals`/`specular` samplers and pack albedo, encoded normal,
smoothness/F0/porosity/emission and lightmaps into 2–4 colour targets; block IDs come from
`block.properties` via `mc_Entity`. Lighting passes decode these. Halcyon also writes a separate
geometric normal for shadow bias; Bliss packs multiple values per channel.

### 4.9 How depth and temporal buffers are used
`depthtex0` (with translucents) vs `depthtex1` (opaque) separates water thickness; DH/Voxy depth
is a second depth texture with its own projection that must be merged manually. Temporal passes
reproject with `gbufferPrevious*` and `previousCameraPosition`, clamp history against the local
neighbourhood, and store history in non-cleared colour buffers.

### 4.10 Likely GPU bottlenecks
1. Volumetric cloud marching (dominant; hence half/quarter-res + temporal reconstruction).
2. Shadow map rendering at 4096²+ with large `shadowDistance` (geometry bound) and wide PCF.
3. Screen-space traces (SSR, SSGI) — bandwidth bound.
4. Water simulation at 1024²–2048² × 3 steps/frame (cheap per cell, but scales with N²).
5. Long bloom chains of full-screen passes (bandwidth).
6. Large uncompressed custom textures (8K moon/Milky Way = hundreds of MB VRAM with no mips).

### 4.11 Features that depend on optional mods
Distant Horizons (`dh_*` programs, DH uniforms), Voxy (`voxy.json`), ColorWheel (`clrwl_*`),
Photonics (Eclipse), Physics Mod ocean (`physics_ocean*` in Eclipse). Boat wakes need Iris ≥
1.10.4 uniforms.

### 4.12 What cannot be achieved with standard Iris APIs
* No access to arbitrary entity positions/velocities (only player, vehicle, lightning bolt).
* No Minecraft fluid-simulation state (flow direction only via vertex data of flowing water).
* No mipmaps for custom textures (large textures must be pre-filtered by the pack).
* No HDR display output path for packs (Iris composites to an 8-bit SDR target).
* No arbitrary render graph: fixed stage order, ≤16 custom images, ≤13 SSBOs, ≤16 colortex.
* The shadow pass is one map; real cascades need atlas tricks or a second view (not provided).
* Gbuffer passes cannot read the target they write; translucent layering beyond the front-most
  surface cannot be stored without an OIT scheme.

## 5. Independent literature consulted (concepts, not code)

* Hillaire, *A Scalable and Production Ready Sky and Atmosphere Rendering Technique*, EGSR 2020.
* Bruneton & Neyret, *Precomputed Atmospheric Scattering*, 2008 (LUT parameterisation).
* Schneider, *The Real-time Volumetric Cloudscapes of Horizon Zero Dawn*, SIGGRAPH 2015.
* Hillaire, *Physically Based Sky, Atmosphere and Cloud Rendering in Frostbite*, 2016.
* Wrenninge et al., *Oz: The Great and Volumetric* (multiple-scattering octaves), 2013.
* Walter et al., *Microfacet Models for Refraction through Rough Surfaces*, EGSR 2007 (GGX).
* Heitz, *Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs*, JCGT 2014.
* Tessendorf, *Simulating Ocean Water*, 2001; Fournier & Reeves 1986 (trochoidal waves).
* Oono & Puri, isotropic discrete Laplacian (1988) for lattice PDEs.
* Lommel–Seeliger lunar reflectance; Hapke opposition surge (qualitative).
* Luminet 1979 & James et al. 2015 (*Gravitational lensing by spinning black holes*, Interstellar).
* Novikov–Thorne thin-disk temperature profile; relativistic Doppler / gravitational redshift.
* Karis, *High Quality Temporal Supersampling*, 2014; Salvi variance clipping 2016.
* Jimenez, *Next Generation Post Processing in Call of Duty* (bloom pyramid), 2014.
* LabPBR Material Standard v1.3 (shaderlabs.org wiki), read 2026-10-24.

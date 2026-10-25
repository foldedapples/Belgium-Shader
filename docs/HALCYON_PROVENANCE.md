# Halcyon-Shaders provenance audit

Audit date: 2026-10-24. Subject: `foldedapples/Halcyon-Shaders`, version 1.0.0-alpha.22. The audit asks one
question: which parts of Halcyon, if any, Belgium Shaders could legitimately reuse later. Belgium Shaders
currently contains no Halcyon or Glimmer code (see `docs/THIRD_PARTY_ASSETS.md`), and nothing in this
document changes that.

This is a technical provenance audit, not legal advice. **Verified** means checked directly in the
repositories or on the cited page during this audit. **Inference** means a judgement drawn from that
evidence.

---

## 0. Summary

| Class | Files | Where they are |
|---|---|---|
| OWNED_ORIGINAL | 63 | 27 code files (lib 16, program 7, tools 3, credits note 1) plus 36 trivial dimension stubs |
| LICENSED_REUSE | 313 | 266 dimension stubs; 35 Glimmer code/config files whose code is unchanged or changed only trivially (Halcyon added comments); `ggx.glsl`; `spaceConversions.glsl` (LGPL-3.0); Tony McMapface LUT and licence; NASA moon textures; `.mcmeta` sidecars |
| MIXED_ORIGIN | 42 | Glimmer files with Halcyon edits, e.g. `waveNormals.glsl`, `c3_translucents.glsl`, `gbuffers_main.glsl`, `shaders.properties` |
| EXTERNAL_RESTRICTED | 4 | `FXAA.glsl` (BSL), `blocklightColors.glsl` (Complementary values), `milkyway_4k.png` and `milkyway_8k.png` (Gaia DR2, CC BY-NC 3.0 IGO) |
| UNKNOWN | 8 | `hillaireCommon.glsl`, `textRenderer.glsl`, `blueNoise.png`, `perlinNoise.png`, `caustics.png`, `caustics_new.png`, `cloudNoise.bin`, `starCatalog.bin` |
| **Total** | **430** | Every file under `shaders/` and `tools/` |

Verdicts for the prioritised modules (details in section 4):

| Module | Verdict | In short |
|---|---|---|
| `lib/water/waterSim.glsl` | OWNED_ORIGINAL | No Glimmer ancestry. The README says AI helped write it. |
| `program/waterSim.glsl` | OWNED_ORIGINAL | Same as above. Its only Glimmer content is the program-template boilerplate. |
| `lib/water/waveNormals.glsl` | MIXED_ORIGIN | afl_ext detail waves (MIT, inherited via Glimmer) plus new Gerstner swells, micro-waves, footprint filtering and masking |
| `lib/water/caustics.glsl` | OWNED_ORIGINAL | New analytic Hessian/Jacobian caustics. Glimmer only had texture caustics. It needs the swell tables in `waveNormals.glsl`. |
| `lib/atmosphere/sky/stars.glsl` | OWNED_ORIGINAL | Code is new. The data it reads (`starCatalog.bin`, `milkyway_*.png`) is UNKNOWN or restricted. |
| `lib/atmosphere/sky/celestial.glsl` | OWNED_ORIGINAL | Eclipse model, sun disk, NASA-textured moon. It needs `moonTex` (NASA, credit) and Glimmer's `sunIrradiance`. |
| `lib/atmosphere/sky/aurora.glsl` | OWNED_ORIGINAL | Contains a short published PCG-style integer hash |
| `lib/atmosphere/sky/blackHole.glsl` | OWNED_ORIGINAL | RK4 Schwarzschild photon orbit. Contains Tanner Helland's published blackbody fit. |
| `lib/atmosphere/sky/rainbow.glsl` | OWNED_ORIGINAL | Small heuristic bow |

"OWNED_ORIGINAL" here means only that no Glimmer or third-party ancestry was found and the file matches
the features the user says they added. It is not proof of authorship (see sections 2.4 and 8).

Tonemapping, verified: Halcyon's default operator is **Tony McMapface** (Tomasz Stachowiak, MIT or
Apache-2.0), sampled from Glimmer's byte-identical 48³ LUT. Glimmer switched its default to Tony McMapface
on 2025-10-04 (commit `e778fe0`). Halcyon changed only two lines of Glimmer's `tonemap.glsl`. Details in
section 6.

---

## 1. Licences and notices

### 1.1 Glimmer (jbritain/glimmer-shaders)

Verified:
- `LICENSE` is MIT, "Copyright (c) 2024 Josh Britain (jbritain)". The GitHub page also shows MIT.
- Most source files carry a header with that copyright, "Licensed under the MIT license" and
  `https://jbritain.net`. 47 Halcyon files still carry this header.
- The README acknowledges Andrew Helmer's Shadertoy port of Hillaire's sky (`slSXRW`), Belmu (SSR
  reference), Emin/Complementary (shadow bias), NinjaMike (directional lightmaps), sixthsurge/Photon (code
  reference and the combined projection matrix), Null, BuilderB0y and others. It also says "there are
  links scattered throughout the code".
- History: 220 commits across 8 branches (`main`, `v2`, `deferred`, `aperture_compat`,
  `variance-shadow-mapping`, `viewport`, `wind`, plus `HEAD`). They run from 2024-12-17 (`dec1fde`) to
  2026-09-20 (`92a7229`, branch `wind`). `main` is at `6a59109` (2026-08-15). Tags run up to `v1.5.2`.
  Authors are Josh Britain, Joshua Britain and jbritain, with one commit each from kloppi417 and fuyuan360.
- Third-party code inside Glimmer, as its own comments state:
  - afl_ext "Very fast procedural ocean", Shadertoy `MdXyzX`, stated as MIT in the code comment.
  - Andrew Helmer, "Production Sky Rendering", Shadertoy `slSXRW`. The licence is not stated in Glimmer.
  - FXAA 3.11 "as implemented by capt. tatsu in BSL", by way of Simon Rodriguez's blog.
  - Complementary Reimagined: the uniform list and the block-light colour values (`blocklightColors.glsl`
    links a specific Complementary commit).
  - Jessie-LC `open-source-utility-code` (space conversions). The repo licence is LGPL-3.0 (verified on
    GitHub).
  - sixthsurge's debug text renderer, using the Monocraft character set.
  - shaderLABS Base-150 (block outline). The repo licence is the Unlicense (verified on GitHub).
  - Belmu SSR gist; Shadertoy `7sfXDn` "Ordered Dithering" by Tech_; DistortedDragon1o4 (DH blending
    help).
  - Tone mappers from dmnsgn/glsl-tone-map (Lottes; that repo is MIT, verified), an AgX approximation,
    and Tony McMapface.
  - `textures/LICENSE-MIT_tony_mc_mapface` and `tonyMcMapface.bin`.

Glimmer's MIT grant covers Josh Britain's code. It cannot relicense third-party code that is under
different terms (BSL, Complementary, LGPL, unlicensed Shadertoy code). That code keeps its upstream terms
whatever Glimmer's top-level licence says.

### 1.2 Halcyon (foldedapples/Halcyon-Shaders)

Verified:
- `LICENSE` is a byte-identical copy of Glimmer's MIT licence (Copyright Josh Britain). No copyright line
  was added for the Halcyon author. The README says "I kept the MIT license just like Glimmer."
- Credits in the README and CHANGELOG:
  - Glimmer ("This whole pack is built on top of his code").
  - "Halcyon edits by me: Freak4U".
  - NASA SVS CGI Moon Kit (4720): Ernie Wright and Noah Petro; LROC WAC colour (NASA/GSFC/Arizona State
    University) and LOLA elevation.
  - NASA SVS Deep Star Maps 2020 (4851): Ernie Wright.
  - Hipparcos Main Catalogue (ESA 1997) and Yale Bright Star Catalogue 5th ed. (Hoffleit & Warren 1991),
    by way of CDS VizieR.
  - Tony McMapface (MIT), afl_ext (MIT), Dave Hoskins "Hash without Sine" (MIT, Shadertoy `4djSRW`),
    Heitz 2018 VNDF, Tanner Helland's blackbody fit, and Allen's lunar phase magnitude curve.
- The README says Eclipse Shader and Bliss were looked at but not copied, because they are not MIT.
- The README says: "I used AI to help me fix and learn the water ripple simulation". The CHANGELOG
  (alpha.15) says: "with the help of ai i got it to work but i hate that i had to use AI".
- `shaders/textures/CREDITS-night-sky.md` says Gaia data are CC BY-NC 3.0 IGO (non-commercial) and that
  `nasa_night_sky.py` is MIT.
- The CHANGELOG says `tools/` is not shipped in the release zip. It also claims: "The cloud noise and
  backup moon textures I just made myself."
- GitHub (checked with WebFetch; `gh` is not installed here): the repository shows 1 commit, no releases,
  no listed contributors, and the MIT licence. GitHub has no history beyond the local squashed commit
  (`8044650`, "Initial Halcyon-Shaders commit").
- `celestial.glsl` says the moon texture was "built by tools/nasa_moon.py". That script is **not in the
  repository**.

### 1.3 External licences checked

| Item | Licence or terms | Status |
|---|---|---|
| Tony McMapface (h3r2tic) | Dual Apache-2.0 / MIT, "at your option" | Verified on GitHub. The README does not say whether the LUT file falls under the dual licence. Halcyon and Glimmer ship the MIT text. |
| dmnsgn/glsl-tone-map (Lottes source) | MIT | Verified |
| afl_ext "Very fast procedural ocean" | MIT, as stated in Glimmer's code comment | Shadertoy returned 403, so not verified at the source |
| Helmer `slSXRW` | Not stated anywhere in Glimmer or Halcyon. Shadertoy's default licence is CC BY-NC-SA 3.0 unless the author says otherwise. | Not verified (Shadertoy returned 403) |
| Jessie-LC open-source-utility-code | LGPL-3.0 | Verified on GitHub |
| shaderLABS Base-150 | Unlicense | Verified |
| BSL Shaders | bitslablab.com returned HTTP 525 | Not verified. BSL is generally distributed under its own restrictive licence (inference). |
| Complementary Reimagined | The licence URL tried returned 404 | Not verified. It is not MIT (inference, consistent with how Halcyon's README treats non-MIT packs). |
| sixthsurge text renderer and Photon | GitHub page did not show the licence type | Not verified |
| AgX approximation (polynomial fit with "Mean error^2: 3.6705141e-06" and Default/Golden/Punchy ASC-CDL looks) | Matches Benjamin Wrensch's "Minimal AgX implementation" (iolite blog) | His blog page states no licence. Not verified. |
| NASA SVS 4720 CGI Moon Kit | Credit "NASA's Scientific Visualization Studio"; Ernie Wright (USRA), Noah Petro (NASA/GSFC). The page links NASA's reproduction guidelines and states no licence. | Verified |
| NASA SVS 4851 Deep Star Maps 2020 | Credit "NASA/Goddard Space Flight Center Scientific Visualization Studio" and "ESA/Gaia/DPAC" for Gaia DR2. No licence on the page. | Verified |
| Gaia data (ESA) | "Gaia data are distributed under the CC BY-NC 3.0 IGO license"; commercial use goes through ESA's archive terms | Verified at cosmos.esa.int/web/gaia-users/license |
| Hipparcos and Yale BSC (VizieR) | ESA archive and CDS terms | Not checked. Assumed attribution-only, which is unverified (see 5.2). |

---

## 2. Method

1. Unshallowed the Glimmer clone (`git fetch --unshallow`) and fetched every remote branch. Result: 220
   commits, 3686 objects, 8 branches.
2. For every commit on every branch I listed the tree and collected every distinct blob with all its paths
   and commit dates, so renamed and deleted files count too.
3. For each Halcyon file I ran three comparisons. Scripts are in the scratchpad; they were not added to
   this repo.
   - **Exact match**: git blob SHA against every Glimmer blob. This catches byte-identical files, such as
     the textures.
   - **Raw similarity**: `difflib.SequenceMatcher` ratio on whitespace-normalised lines, against the best
     candidate. Candidates were the same path, the same basename, and the top six blobs by line overlap.
   - **Code similarity**: comments (`//`, `/* */`) and all whitespace removed. I then measured the share of
     Halcyon's code lines (10+ characters) that appear in *any* Glimmer version, and in the closest
     single Glimmer file.
4. Why code similarity is the main measure: Halcyon added a jokey commentary line to nearly every function
   in nearly every file, Glimmer-derived files included. That drags the raw ratio down. For example,
   `FXAA.glsl` scores raw 0.94 but code 100%, and `bloom.glsl` scores raw 0.89 but code 100%.
5. Classification thresholds:
   - Code ≥ 97% → LICENSED_REUSE (Glimmer MIT; Halcyon changed only comments or trivia), unless the file
     itself is third-party code with other terms.
   - 20–97%, or a same-path rewrite → MIXED_ORIGIN.
   - Under 20% with no same-path ancestor → OWNED_ORIGINAL. The matched lines here are only Glimmer's
     full-screen program template: `#include "/lib/common.glsl"`, `ftransform()`, the `texcoord` varying,
     and the depth-to-view-space reconstruction idiom.
   - Manual overrides where a file's upstream is not Glimmer (sections 1.1 and 1.3).
6. History searches across all Glimmer branches (`git log --all -i -G`) found **zero** commits mentioning
   aurora, eclipse, black hole, Gerstner, water sim, ripple, wake, Lommel, Milky Way or Hessian. "rainbow"
   appears once, only as a block-outline colour mode. "stars" appears only in vanilla
   `MC_RENDER_STAGE_STARS` handling and `stars=false`. "caustic" appears in 20 commits, all about
   texture-based caustics (`causticsTex`, `getCaustics`).

### 2.4 Limits of the method

- Absence from Glimmer is evidence, not proof. I could not compare against every public shaderpack or
  Shadertoy. Eclipse, Bliss, Complementary, Photon, BSL and Shadertoy were **not** diffed.
- Halcyon's history is one squashed commit (2026-10-23), so its git data cannot show who wrote anything,
  or when.
- Authorship signals that point different ways:
  - The README and CHANGELOG admit AI help on the water simulation.
  - The shader comments are written in one uniform persona voice throughout, including on code the
    comments themselves call borrowed (FXAA, space conversions, the text renderer).
  - The `tools/*.py` scripts use a formal, technical docstring style quite unlike the shader comments.

  Inference: the comments were added in a bulk pass and do not show who wrote the code under them.
- If any OWNED_ORIGINAL code was largely produced by an AI system, its copyright status is a separate,
  jurisdiction-dependent question. This audit does not resolve it.

---

## 3. Classification

### 3.1 Dimension stubs (`shaders/world0`, `world1`, `world-1`): 302 files

These are 4–8 line wrappers: `#include "/lib/version.glsl"`, one to three `#define`s (stage, dimension,
pass selector) and one `#include "/program/…"`. Glimmer generates them with
`scripts/copy_dimensions.py`.

- 266 match the Glimmer stub for the same path (3 byte-identical, the rest ratio ≥ 0.8) →
  **LICENSED_REUSE** (Glimmer MIT; trivial).
- 36 are new or re-pointed stubs for Halcyon passes → **OWNED_ORIGINAL** (trivial). These are
  `world0/prepare6-9.csh` (water sim, which sets `WATER_SIM_CONTROL` / `WATER_SIM_STEP`), `deferred2-5`,
  `composite52`, `prepare5` and the matching `world1` / `world-1` entries.

Neither group has any meaningful expressive content.

### 3.2 Per-file table (`shaders/` excluding stubs, `tools/`): 128 files

\* Code lines are counted after removing comments and whitespace, keeping lines of 10+ characters.
"Closest Glimmer file" is the Glimmer path (any version) that shares the most code lines. Below 10% the
match is only template boilerplate and is shown as "none".

| Halcyon file | Code lines* | Code lines found in any Glimmer version | Closest Glimmer file | difflib ratio (raw text) | Class |
|---|---|---|---|---|---|
| `shaders/block.properties` | 65 | 78% | `shaders/block.properties` | 0.85 | MIXED_ORIGIN |
| `shaders/colorwheel.properties` | 5 | 100% | `shaders/colorwheel.properties` | 1.0 | LICENSED_REUSE |
| `shaders/entity.properties` | 2 | 50% | `shaders/entity.properties` | 0.667 | MIXED_ORIGIN |
| `shaders/lang/en_US.lang` | 581 | 33% | `shaders/lang/en_US.lang` | 0.477 | MIXED_ORIGIN |
| `shaders/lang/zh_CN.lang` | 203 | 100% | `shaders/lang/zh_CN.lang` | 1.0 | LICENSED_REUSE |
| `shaders/lib/TAA.glsl` | 8 | 100% | `shaders/lib/TAA.glsl` | 0.72 | LICENSED_REUSE |
| `shaders/lib/atmosphere/cloudComposite.glsl` | 36 | 6% | none (boilerplate only) | 0.137 | OWNED_ORIGINAL |
| `shaders/lib/atmosphere/clouds.glsl` | 151 | 80% | `shaders/lib/atmosphere/clouds.glsl` | 0.766 | MIXED_ORIGIN |
| `shaders/lib/atmosphere/fog.glsl` | 151 | 59% | `shaders/lib/atmosphere/fog.glsl` | 0.644 | MIXED_ORIGIN |
| `shaders/lib/atmosphere/sky/aurora.glsl` | 80 | 1% | none (boilerplate only) | - | OWNED_ORIGINAL |
| `shaders/lib/atmosphere/sky/blackHole.glsl` | 219 | 2% | none (boilerplate only) | 0.045 | OWNED_ORIGINAL |
| `shaders/lib/atmosphere/sky/celestial.glsl` | 195 | 2% | none (boilerplate only) | 0.061 | OWNED_ORIGINAL |
| `shaders/lib/atmosphere/sky/cirrus.glsl` | 40 | 2% | none (boilerplate only) | 0.078 | OWNED_ORIGINAL |
| `shaders/lib/atmosphere/sky/endAmbient.glsl` | 9 | 0% | none (boilerplate only) | - | OWNED_ORIGINAL |
| `shaders/lib/atmosphere/sky/hillaireCommon.glsl` | 83 | 94% | `shaders/lib/atmosphere/sky/hillaireCommon.glsl` | 0.821 | UNKNOWN |
| `shaders/lib/atmosphere/sky/rainbow.glsl` | 32 | 3% | none (boilerplate only) | - | OWNED_ORIGINAL |
| `shaders/lib/atmosphere/sky/sky.glsl` | 92 | 54% | `shaders/lib/atmosphere/sky/sky.glsl` | 0.564 | MIXED_ORIGIN |
| `shaders/lib/atmosphere/sky/stars.glsl` | 254 | 0% | none (boilerplate only) | 0.019 | OWNED_ORIGINAL |
| `shaders/lib/atmosphere/volumetricClouds.glsl` | 262 | 3% | none (boilerplate only) | 0.062 | OWNED_ORIGINAL |
| `shaders/lib/common.glsl` | 62 | 87% | `shaders/lib/common.glsl` | 0.782 | MIXED_ORIGIN |
| `shaders/lib/common/debug.glsl` | 20 | 100% | `shaders/lib/common/debug.glsl` | 0.894 | LICENSED_REUSE |
| `shaders/lib/common/material.glsl` | 74 | 73% | `shaders/lib/common/material.glsl` | 0.74 | MIXED_ORIGIN |
| `shaders/lib/common/materialIDs.glsl` | 89 | 76% | `shaders/lib/common/materialIDs.glsl` | 0.788 | MIXED_ORIGIN |
| `shaders/lib/common/settings.glsl` | 243 | 30% | `shaders/lib/common/settings.glsl` | 0.409 | MIXED_ORIGIN |
| `shaders/lib/common/spaceConversions.glsl` | 45 | 100% | `shaders/lib/common/spaceConversions.glsl` | 0.922 | LICENSED_REUSE |
| `shaders/lib/common/syntax.glsl` | 72 | 100% | `shaders/lib/common/syntax.glsl` | 0.913 | LICENSED_REUSE |
| `shaders/lib/common/uniforms.glsl` | 147 | 95% | `shaders/lib/common/uniforms.glsl` | 0.91 | MIXED_ORIGIN |
| `shaders/lib/common/util.glsl` | 113 | 82% | `shaders/lib/common/util.glsl` | 0.818 | MIXED_ORIGIN |
| `shaders/lib/dh.glsl` | 27 | 78% | `shaders/lib/dh.glsl` | 0.742 | MIXED_ORIGIN |
| `shaders/lib/dhBlend.glsl` | 17 | 100% | `shaders/lib/dhBlend.glsl` | 0.884 | LICENSED_REUSE |
| `shaders/lib/endPortal.glsl` | 74 | 10% | none (boilerplate only) | 0.095 | MIXED_ORIGIN |
| `shaders/lib/ipbr/blocklightColors.glsl` | 36 | 53% | `shaders/lib/ipbr/blocklightColors.glsl` | 0.574 | EXTERNAL_RESTRICTED |
| `shaders/lib/lighting/brdf.glsl` | 102 | 89% | `shaders/lib/lighting/brdf.glsl` | 0.798 | MIXED_ORIGIN |
| `shaders/lib/lighting/directionalLightmap.glsl` | 35 | 100% | `shaders/lib/lighting/directionalLightmap.glsl` | 0.906 | LICENSED_REUSE |
| `shaders/lib/lighting/lava.glsl` | 16 | 25% | `shaders/lib/atmosphere/clouds.glsl` | 0.115 | OWNED_ORIGINAL |
| `shaders/lib/lighting/opaqueReflections.glsl` | 84 | 30% | `shaders/program/c3_translucents.glsl` | 0.117 | MIXED_ORIGIN |
| `shaders/lib/lighting/shading.glsl` | 95 | 85% | `shaders/lib/lighting/shading.glsl` | 0.831 | MIXED_ORIGIN |
| `shaders/lib/lighting/shadows.glsl` | 123 | 76% | `shaders/lib/lighting/shadows.glsl` | 0.76 | MIXED_ORIGIN |
| `shaders/lib/parallax.glsl` | 85 | 100% | `shaders/lib/parallax.glsl` | 0.906 | LICENSED_REUSE |
| `shaders/lib/post/FXAA.glsl` | 130 | 100% | `shaders/lib/post/FXAA.glsl` | 0.937 | EXTERNAL_RESTRICTED |
| `shaders/lib/post/bloom.glsl` | 82 | 100% | `shaders/lib/post/bloom.glsl` | 0.886 | LICENSED_REUSE |
| `shaders/lib/post/heatHaze.glsl` | 30 | 20% | `shaders/program/gbuffers_main.glsl` | 0.037 | OWNED_ORIGINAL |
| `shaders/lib/post/processing.glsl` | 77 | 6% | none (boilerplate only) | 0.099 | MIXED_ORIGIN |
| `shaders/lib/post/tonemap.glsl` | 98 | 99% | `shaders/lib/post/tonemap.glsl` | 0.843 | LICENSED_REUSE |
| `shaders/lib/shadowSpace.glsl` | 36 | 100% | `shaders/lib/shadowSpace.glsl` | 0.82 | LICENSED_REUSE |
| `shaders/lib/sway.glsl` | 52 | 100% | `shaders/lib/sway.glsl` | 0.869 | LICENSED_REUSE |
| `shaders/lib/util/ggx.glsl` | 23 | 0% | none (boilerplate only) | - | LICENSED_REUSE |
| `shaders/lib/util/packing.glsl` | 46 | 100% | `shaders/lib/util/packing.glsl` | 0.855 | LICENSED_REUSE |
| `shaders/lib/util/screenSpaceRayTrace.glsl` | 60 | 98% | `shaders/lib/util/screenSpaceRayTrace.glsl` | 0.826 | LICENSED_REUSE |
| `shaders/lib/util/spheremap.glsl` | 16 | 100% | `shaders/lib/util/spheremap.glsl` | 0.857 | LICENSED_REUSE |
| `shaders/lib/util/textRenderer.glsl` | 223 | 100% | `shaders/lib/util/textRenderer.glsl` | 0.826 | UNKNOWN |
| `shaders/lib/version.glsl` | 1 | 100% | `shaders/lib/version.glsl` | 0.667 | LICENSED_REUSE |
| `shaders/lib/voxel/voxelData.glsl` | 35 | 97% | `shaders/lib/voxel/voxelData.glsl` | 0.852 | LICENSED_REUSE |
| `shaders/lib/voxel/voxelMap.glsl` | 15 | 100% | `shaders/lib/voxel/voxelMap.glsl` | 0.846 | LICENSED_REUSE |
| `shaders/lib/water/caustics.glsl` | 61 | 3% | none (boilerplate only) | 0.039 | OWNED_ORIGINAL |
| `shaders/lib/water/puddles.glsl` | 67 | 24% | `shaders/lib/water/puddles.glsl` | 0.207 | MIXED_ORIGIN |
| `shaders/lib/water/rainRipples.glsl` | 45 | 0% | none (boilerplate only) | - | OWNED_ORIGINAL |
| `shaders/lib/water/underwaterShafts.glsl` | 44 | 2% | none (boilerplate only) | 0.106 | OWNED_ORIGINAL |
| `shaders/lib/water/waterFog.glsl` | 88 | 16% | `shaders/lib/water/waterFog.glsl` | 0.289 | MIXED_ORIGIN |
| `shaders/lib/water/waterParallax.glsl` | 33 | 21% | `shaders/lib/water/waterParallax.glsl` | 0.224 | MIXED_ORIGIN |
| `shaders/lib/water/waterSim.glsl` | 116 | 1% | none (boilerplate only) | 0.034 | OWNED_ORIGINAL |
| `shaders/lib/water/waveNormals.glsl` | 221 | 14% | `shaders/lib/water/waveNormals.glsl` | 0.126 | MIXED_ORIGIN |
| `shaders/lib/water/wetnessSimple.glsl` | 16 | 12% | `shaders/lib/water/puddles.glsl` | 0.129 | OWNED_ORIGINAL |
| `shaders/program/bloomDownsample.glsl` | 17 | 88% | `shaders/program/bloomDownsample.glsl` | 0.838 | MIXED_ORIGIN |
| `shaders/program/bloomUpsample.glsl` | 13 | 100% | `shaders/program/bloomUpsample.glsl` | 0.938 | LICENSED_REUSE |
| `shaders/program/c0_combinedDepth.glsl` | 18 | 100% | `shaders/program/c0_combinedDepth.glsl` | 0.889 | LICENSED_REUSE |
| `shaders/program/c1_godraysVisibility.glsl` | 14 | 100% | `shaders/program/c1_godraysVisibility.glsl` | 0.889 | LICENSED_REUSE |
| `shaders/program/c2_godrays.glsl` | 68 | 91% | `shaders/program/c2_godrays.glsl` | 0.825 | MIXED_ORIGIN |
| `shaders/program/c3_translucents.glsl` | 358 | 60% | `shaders/program/c3_translucents.glsl` | 0.589 | MIXED_ORIGIN |
| `shaders/program/c48_writeLuminance.glsl` | 18 | 72% | `shaders/program/c50_applyAutoExposure.glsl` | 0.727 | MIXED_ORIGIN |
| `shaders/program/c49_computeAutoExposure.glsl` | 38 | 45% | `shaders/program/c49_computeAutoExposure.glsl` | 0.6 | MIXED_ORIGIN |
| `shaders/program/c4_fog.glsl` | 90 | 69% | `shaders/program/c4_fog.glsl` | 0.719 | MIXED_ORIGIN |
| `shaders/program/c50_applyAutoExposure.glsl` | 35 | 71% | `shaders/program/c50_applyAutoExposure.glsl` | 0.708 | MIXED_ORIGIN |
| `shaders/program/c51_motionBlur.glsl` | 36 | 100% | `shaders/program/c51_motionBlur.glsl` | 0.821 | LICENSED_REUSE |
| `shaders/program/c52_depthOfField.glsl` | 41 | 24% | `shaders/program/composite4.glsl` | 0.339 | OWNED_ORIGINAL |
| `shaders/program/c89_temporalFilter.glsl` | 44 | 100% | `shaders/program/c89_temporalFilter.glsl` | 0.878 | LICENSED_REUSE |
| `shaders/program/c90_FXAA.glsl` | 13 | 100% | `shaders/program/c90_FXAA.glsl` | 0.853 | LICENSED_REUSE |
| `shaders/program/clrwl_shadow.glsl` | 56 | 100% | `shaders/program/clrwl_shadow.glsl` | 0.872 | LICENSED_REUSE |
| `shaders/program/d0_sky.glsl` | 36 | 83% | `shaders/program/d0_sky.glsl` | 0.773 | MIXED_ORIGIN |
| `shaders/program/d1_dhAo.glsl` | 42 | 100% | `shaders/program/d1_dhAo.glsl` | 0.868 | LICENSED_REUSE |
| `shaders/program/d2_ssgiTrace.glsl` | 56 | 20% | `shaders/program/c4_fog.glsl` | 0.252 | OWNED_ORIGINAL |
| `shaders/program/d3_ssgiTemporal.glsl` | 32 | 31% | `shaders/program/c2_godrays.glsl` | 0.432 | OWNED_ORIGINAL |
| `shaders/program/d4_ssgiApply.glsl` | 41 | 29% | `shaders/program/c4_fog.glsl` | 0.318 | OWNED_ORIGINAL |
| `shaders/program/dc_volumetricClouds.glsl` | 74 | 18% | `shaders/program/c3_translucents.glsl` | 0.134 | OWNED_ORIGINAL |
| `shaders/program/final.glsl` | 46 | 83% | `shaders/program/final.glsl` | 0.743 | MIXED_ORIGIN |
| `shaders/program/gbuffers_clrwl.glsl` | 158 | 98% | `shaders/program/gbuffers_clrwl.glsl` | 0.894 | LICENSED_REUSE |
| `shaders/program/gbuffers_distant.glsl` | 86 | 90% | `shaders/program/gbuffers_distant.glsl` | 0.799 | MIXED_ORIGIN |
| `shaders/program/gbuffers_glowing.glsl` | 37 | 100% | `shaders/program/gbuffers_glowing.glsl` | 0.84 | LICENSED_REUSE |
| `shaders/program/gbuffers_line.glsl` | 48 | 100% | `shaders/program/gbuffers_line.glsl` | 0.85 | LICENSED_REUSE |
| `shaders/program/gbuffers_main.glsl` | 287 | 81% | `shaders/program/gbuffers_main.glsl` | 0.783 | MIXED_ORIGIN |
| `shaders/program/gbuffers_skybasic.glsl` | 18 | 94% | `shaders/program/gbuffers_skybasic.glsl` | 0.81 | MIXED_ORIGIN |
| `shaders/program/gbuffers_skytextured.glsl` | 22 | 86% | `shaders/program/gbuffers_skytextured.glsl` | 0.707 | MIXED_ORIGIN |
| `shaders/program/gbuffers_voxy.glsl` | 57 | 93% | `shaders/program/gbuffers_voxy.glsl` | 0.807 | MIXED_ORIGIN |
| `shaders/program/gbuffers_weather.glsl` | 51 | 100% | `shaders/program/gbuffers_weather.glsl` | 0.903 | LICENSED_REUSE |
| `shaders/program/prepare.glsl` | 95 | 92% | `shaders/program/prepare.glsl` | 0.809 | MIXED_ORIGIN |
| `shaders/program/prepare1.glsl` | 19 | 95% | `shaders/program/prepare1.glsl` | 0.838 | MIXED_ORIGIN |
| `shaders/program/prepare2.glsl` | 27 | 82% | `shaders/program/prepare2.glsl` | 0.818 | MIXED_ORIGIN |
| `shaders/program/prepare3.glsl` | 67 | 100% | `shaders/program/prepare3.glsl` | 0.873 | LICENSED_REUSE |
| `shaders/program/prepare5.glsl` | 15 | 53% | `shaders/program/c2_godrays.glsl` | 0.432 | OWNED_ORIGINAL |
| `shaders/program/setup.csh` | 31 | 100% | `shaders/program/setup.csh` | 0.909 | LICENSED_REUSE |
| `shaders/program/setup1.csh` | 72 | 100% | `shaders/program/setup1.csh` | 0.866 | LICENSED_REUSE |
| `shaders/program/shadow.glsl` | 97 | 98% | `shaders/program/shadow.glsl` | 0.829 | LICENSED_REUSE |
| `shaders/program/shadowcomp.csh` | 38 | 100% | `shaders/program/shadowcomp.csh` | 0.789 | LICENSED_REUSE |
| `shaders/program/voxy.json` | 62 | 84% | `shaders/program/voxy.json` | 0.919 | MIXED_ORIGIN |
| `shaders/program/waterSim.glsl` | 206 | 2% | none (boilerplate only) | 0.064 | OWNED_ORIGINAL |
| `shaders/shaders.properties` | 247 | 49% | `shaders/shaders.properties` | 0.598 | MIXED_ORIGIN |
| `shaders/textures/CREDITS-night-sky.md` | - | - | - | - | OWNED_ORIGINAL |
| `shaders/textures/LICENSE-MIT_tony_mc_mapface` | - | - | - | 0.978 | LICENSED_REUSE |
| `shaders/textures/blueNoise.png` | binary | byte-identical | `shaders/textures/blueNoise.png` | - | UNKNOWN |
| `shaders/textures/blueNoise.png.mcmeta` | - | - | - | 1.0 | LICENSED_REUSE |
| `shaders/textures/caustics.png` | binary | byte-identical | `shaders/textures/caustics.png` | - | UNKNOWN |
| `shaders/textures/caustics_new.png` | binary | byte-identical | `shaders/textures/caustics_new.png` | - | UNKNOWN |
| `shaders/textures/cloudNoise.bin` | binary | no match | none | - | UNKNOWN |
| `shaders/textures/milkyway_4k.png` | binary | no match | none | - | EXTERNAL_RESTRICTED |
| `shaders/textures/milkyway_4k.png.mcmeta` | - | - | - | 1.0 | LICENSED_REUSE |
| `shaders/textures/milkyway_8k.png` | binary | no match | none | - | EXTERNAL_RESTRICTED |
| `shaders/textures/milkyway_8k.png.mcmeta` | - | - | - | 1.0 | LICENSED_REUSE |
| `shaders/textures/moon_2k.png` | binary | no match | none | - | LICENSED_REUSE |
| `shaders/textures/moon_2k.png.mcmeta` | - | - | - | 0.833 | LICENSED_REUSE |
| `shaders/textures/moon_4k.png` | binary | no match | none | - | LICENSED_REUSE |
| `shaders/textures/moon_4k.png.mcmeta` | - | - | - | 0.833 | LICENSED_REUSE |
| `shaders/textures/perlinNoise.png` | binary | byte-identical | `shaders/textures/perlinNoise.png` | - | UNKNOWN |
| `shaders/textures/perlinNoise.png.mcmeta` | - | - | - | 1.0 | LICENSED_REUSE |
| `shaders/textures/starCatalog.bin` | binary | no match | none | - | UNKNOWN |
| `shaders/textures/tonyMcMapface.bin` | binary | byte-identical | `shaders/textures/tonyMcMapface.bin` | - | LICENSED_REUSE |
| `tools/nasa_night_sky.py` | 331 | 1% | none (boilerplate only) | 0.015 | OWNED_ORIGINAL |
| `tools/preview_clouds_gpu.py` | 173 | 6% | none (boilerplate only) | 0.034 | OWNED_ORIGINAL |
| `tools/preview_night_sky.py` | 241 | 2% | none (boilerplate only) | 0.026 | OWNED_ORIGINAL |

### 3.3 Notes on specific rows

- **Glimmer files whose code is unchanged** (code ≥ 97%; LICENSED_REUSE under Glimmer MIT). These are
  `TAA`, `debug`, `syntax`, `dhBlend`, `directionalLightmap`, `parallax`, `bloom`, `shadowSpace`, `sway`,
  `packing`, `screenSpaceRayTrace`, `spheremap`, `version`, `voxelData`, `voxelMap`, `tonemap`,
  `bloomUpsample`, `c0`, `c1`, `c51`, `c89`, `c90`, `clrwl_shadow`, `d1_dhAo`, `gbuffers_clrwl`,
  `gbuffers_glowing`, `gbuffers_line`, `gbuffers_weather`, `prepare3`, `setup.csh`, `setup1.csh`,
  `shadow`, `shadowcomp`, `colorwheel.properties` and `zh_CN.lang`. Halcyon's only changes are comments,
  or one or two lines (`tonemap`).
  - Several of these carry upstream code as well: `dhBlend` (Bayer dither from Shadertoy `7sfXDn`,
    licence unknown), `screenSpaceRayTrace` (Belmu gist reference, licence unknown), `gbuffers_line`
    (Base-150, Unlicense) and `directionalLightmap` (NinjaMike's method).
- **`spaceConversions.glsl`**: 100% Glimmer code, but Glimmer took it from Jessie-LC, whose repo is
  LGPL-3.0. Classed LICENSED_REUSE, but it carries LGPL obligations, not MIT ones.
- **`FXAA.glsl`** (EXTERNAL_RESTRICTED): 100% Glimmer code, which is the BSL implementation by capt.
  tatsu. BSL's terms were not verifiable, and Glimmer's MIT does not cover them.
- **`blocklightColors.glsl`** (EXTERNAL_RESTRICTED): its colour values come from a specific Complementary
  Reimagined commit. Complementary is not MIT.
- **`uniforms.glsl`** (MIXED_ORIGIN): the uniform list is credited to Complementary. A list of Iris
  uniform declarations has little expressive content, and Halcyon added its own custom uniforms.
- **`textRenderer.glsl`** (UNKNOWN): sixthsurge's debug text renderer with the Monocraft glyph set. The
  upstream licence was not verified.
- **`hillaireCommon.glsl`** (UNKNOWN): 94% Glimmer code, derived from Helmer's Shadertoy `slSXRW`, whose
  licence is not stated anywhere. The same applies to the Hillaire-derived parts of `sky.glsl`,
  `prepare.glsl`, `setup.csh` and `setup1.csh`. Those files are classed by their Glimmer ancestry, but
  they inherit this uncertainty.
- **`ggx.glsl`** (LICENSED_REUSE): a transcription of Heitz 2018's JCGT VNDF listing (credited), plus an
  orthonormal-basis routine that matches Duff et al. 2017 (JCGT), which is uncredited. Both are published
  algorithms; attribution is advisable.
- **Same-path rewrites classed MIXED_ORIGIN, though mostly new code**:
  - `waveNormals.glsl`: 14% Glimmer code.
  - `waterFog.glsl`: 16%.
  - `waterParallax.glsl`: 21%.
  - `puddles.glsl`: 24%. Also cites Lagarde 2013 for albedo darkening.
  - `endPortal.glsl`: 10%.
  - `processing.glsl`: 6%. Glimmer's `postProcess` scaffold, with white balance by Tanner Helland's fit
    and colour profiles.

  A Halcyon-only extraction of these files is possible, but the "new" parts call Glimmer functions and
  uniforms throughout.
- **`opaqueReflections.glsl`** (MIXED_ORIGIN, new path): 30% of its lines repeat Glimmer's SSR and
  sky-reflection call structure from `c3_translucents` and the old `composite1`.
- **New programs** `c52_depthOfField`, `d2`/`d3`/`d4` SSGI, `dc_volumetricClouds`, `prepare5` and
  `waterSim` (OWNED_ORIGINAL): the lines they share with Glimmer are only the full-screen template and
  the depth reconstruction idiom.
- **`util.glsl`** (MIXED_ORIGIN): Glimmer's utilities plus Halcyon's additions, including `hash33` and
  related functions from Dave Hoskins "Hash without Sine" (MIT, credited). The prioritised sky modules
  depend on these hashes.

---

## 4. Prioritised modules

Dependencies listed under "Glimmer coupling" come from Halcyon's include graph and `shaders.properties`.
Every module reaches `/lib/common.glsl`, which pulls in Glimmer's `uniforms.glsl`, `syntax.glsl` (macros
such as `pow2`, `clamp01`, `max0`, `rcp`), `util.glsl` (`rotate`, `sincos`, `luminance`,
`interleavedGradientNoise`, Hoskins hashes) and `settings.glsl`. It also relies on the `fsh` / `vsh` /
`csh` stage defines set in the dimension stubs.

### 4.1 `shaders/lib/water/waterSim.glsl` and `shaders/program/waterSim.glsl`

- **Classification: OWNED_ORIGINAL** for both.
- **Evidence (verified)**:
  - Code overlap with any Glimmer version is 1% (lib) and 2% (program). The shared lines are
    `#include "/lib/common.glsl"`, `void main()` and a workgroup declaration.
  - No Glimmer commit on any branch mentions a water sim, ripple or wake.
  - The README and CHANGELOG list interactive water as Halcyon's own feature (alpha.15) and say AI helped
    write it.
  - Published or standard techniques inside, all expressed in Halcyon's own code:
    - isotropic 9-point Laplacian (Patra & Karttunen 2006, cited);
    - semi-implicit Euler wave equation with a restoring "spring" term;
    - toroidal texel wrapping (`cell & (N-1)`) for a scrolling window;
    - fixed-timestep accumulator ("fix your timestep");
    - cubic B-spline reconstruction with derivative weights;
    - Gaussian source discs.
  - No distinctive third-party constants or comments were found. `WS_MAGIC` = "HALC" in ASCII.
- **Callers**:
  - `world0/prepare6.csh` runs the control pass (`WATER_SIM_CONTROL`), one thread.
  - `world0/prepare7`, `prepare8` and `prepare9.csh` run the step passes (`WATER_SIM_STEP` 0–2), with up
    to 3 sub-steps per frame.
  - `program/c3_translucents.glsl` samples the result through `waterSimSlope()`. `waterSimHeight()` has
    no caller found.
  - Overworld only.
- **Glimmer coupling**:
  - SSBO `bufferObject.3` (256 bytes) at `binding = 3`. Iris declares it in `shaders.properties`; Glimmer
    already uses buffers 0–2.
  - Two `image.waterSimA` / `waterSimB` RG16F images, with sizes set per `WATER_SIM_QUALITY` in
    `shaders.properties`.
  - Iris uniforms `feetInWater`, `isRiding`, `vehicleInWater`, `vehicleId`, `vehicleLookVector`,
    `relativeVehiclePosition`, `relativeEyePosition`, `isEyeInWater`, `frameTime`.
  - `cameraPositionInt` and `cameraPositionFract`, declared in Glimmer's `uniforms.glsl`.
  - `pow2`, from Glimmer's `syntax.glsl`.
  - Settings `WATER_SIM_QUALITY`, `WATER_SIM_STRENGTH`, `PLAYER_RIPPLE_STRENGTH`, `BOAT_WAKE_STRENGTH`.
  - `entity.properties` boat ID 2 (`WS_BOAT_ENTITY_ID`).
- **Standalone transplant**: feasible. The module is self-contained apart from about 10 uniforms, one SSBO,
  two images, four compute-stage stubs and `pow2`. It does not depend on Glimmer's G-buffer layout.
- **Caveat**: the AI-assistance admission. Ownership is "the user's, to the extent AI-assisted output is
  ownable". Inference.

### 4.2 `shaders/lib/water/waveNormals.glsl`

- **Classification: MIXED_ORIGIN.**
- **Inherited from Glimmer (14% of code lines)**: the afl_ext "Very fast procedural ocean" core, with
  its attribution and MIT URL kept. That is `wavedx()`, the drag-iteration body of `waveHeight()`
  (`DRAG_MULT` 0.2, `WAVE_E` 0.1, the frequency and time multipliers 1.18 and 1.07), the
  `PIXEL_LOCKED_LIGHTING` snap, and the `waveNormal(pos, faceNormal, heightmapFactor)` signature.
- **Halcyon changes to that core**:
  - a fixed 12-entry direction table, verified to differ from afl_ext's `sin/cos(iter)` sequence;
  - weight decay 0.27 instead of 0.2;
  - an `iterations` parameter, `WAVE_SCALE`, and `waveTime()`.
- **New in Halcyon (no Glimmer ancestry)**:
  - Seven Gerstner swells with deep-water dispersion. Normals follow GPU Gems ch. 1 (Finch 2004, cited).
  - Wave-group modulation `swellGroup`.
  - Per-pixel footprint filtering that tracks the removed slope variance.
  - Four capillary micro-waves with surface-tension dispersion.
  - Weather, biome and river multipliers.
  - Distance LOD.
  - Finite-difference slopes.
  - `waterRoughness`, `waterFootprint`, and `waterReflectionMasking`, a Smith-masking ratio after
    Heitz 2014 (cited).
- **Callers**:
  - `program/gbuffers_main.glsl`, `program/c3_translucents.glsl`, `program/shadow.glsl`,
    `program/clrwl_shadow.glsl`, `program/gbuffers_clrwl.glsl`.
  - `lib/sway.glsl`, `lib/water/waterParallax.glsl`, `lib/water/caustics.glsl`.
- **Glimmer coupling**:
  - `perlinNoiseTex` (UNKNOWN origin, see section 5) and `rotate()` from `util.glsl`.
  - `frameTimeCounter`, `gbufferProjection`, `viewHeight`, `wetness`, `thunderStrength`.
  - Custom uniforms `biomeCanPrecipitateSmooth`, `oceanBiomeSmooth` and `riverBiomeSmooth`, defined in
    `shaders.properties`. The last two are Halcyon additions.
  - Settings `WAVE_SPEED`, `WAVE_SCALE`, `WAVE_DEPTH`, `WAVE_SWELL`, `WAVE_DETAIL`, `WAVE_RIPPLES`,
    `WATER_STORM_WAVES`, `WATER_SWELLS`, `WATER_BIOME_WAVES`, `PIXEL_SIZE`.
- **Standalone transplant**: the Halcyon-only parts (swells, micro-waves, footprint filter, masking) can
  be separated from the afl_ext core with moderate effort. `waterSurfaceSlope()` mixes the two, so the
  file as a whole cannot be taken without the Glimmer/afl_ext part. That part is itself MIT and reusable
  with notices (section 7).

### 4.3 `shaders/lib/water/caustics.glsl`

- **Classification: OWNED_ORIGINAL.**
- **Evidence**:
  - Code overlap with Glimmer is 3%: only the include and one parameter line.
  - Every Glimmer version uses a tiled texture instead (`causticsTex`, `getCaustics()` in
    `shadows.glsl`), so the approach differs.
  - Halcyon's version computes the analytic Hessian of its own swell and caustic-wave sets, refracts the
    light with Snell's law (n = 1.33), and takes intensity as 1 / |det J| with a soft clamp. This
    Jacobian-of-refraction method is a published, generic technique. No distinctive third-party
    constants were found; the golden-angle phase offset 2.399 is generic.
- **Callers**: `lib/lighting/shadows.glsl` (MIXED_ORIGIN, Glimmer), gated by `CAUSTICS` /
  `CAUSTICS_MODE`. `CAUSTICS_MODE` 1 appears to keep Glimmer's texture path. Inference from the profiles.
- **Glimmer coupling**:
  - It includes `waveNormals.glsl` and uses `SWELL_COUNT`, `swellWavelength`, `swellAngle`,
    `swellSteepness`, `swellGroup`, `waterSwellMul` (all Halcyon parts) and `waveTime()`.
  - It uses `rotate()`, `pow2` and `clamp01`; the uniform `wetness`; and the settings
    `CAUSTICS_STRENGTH`, `WAVE_SCALE`, `WAVE_SWELL` and `WAVE_DEPTH`.
- **Standalone transplant**: possible together with the swell tables from 4.2. It does not need the
  afl_ext part.

### 4.4 `shaders/lib/atmosphere/sky/stars.glsl`

- **Classification: OWNED_ORIGINAL** for the code. The data it consumes is UNKNOWN or
  EXTERNAL_RESTRICTED (section 5).
- **Evidence**:
  - Code overlap is 0.4%; the single shared line is part of a Catmull-Rom weight sum.
  - Glimmer has no star rendering beyond turning vanilla stars off.
- **Known public pieces inside**:
  - A 5-tap Catmull-Rom bicubic. This is a well-known trick, commonly attributed to MJP's and Jimenez's
    write-ups. The comment admits "I copy-pasted it". It is uncredited, and its upstream licence was not
    checked.
  - The ICRS-to-galactic rotation matrix from Hipparcos Vol. 1 (a published constant).
  - The magnitude-to-flux law (`log2(100)/5`).
  - `hash33` (Hoskins, MIT).
- **Its own design**:
  - A cube-mapped, equi-angular star cell index into `starCatalogTex`.
  - Bit-packed magnitude and colour index.
  - A limiting magnitude driven by sun altitude, moon phase, aurora and eclipse.
  - Airmass scintillation with chromatic twinkle.
  - asinh latitude warp, footprint filtering and grading for the Milky Way.
  - The procedural End star layers `starLayer` and `galacticBand`.
- **Callers**:
  - `lib/atmosphere/sky/sky.glsl`, through `nightSky()` (overworld).
  - `lib/endPortal.glsl` and `blackHole.glsl`, through `starLayer()` (End).
  - `lib/common/settings.glsl`, for setting references.
- **Glimmer coupling**:
  - `worldSunDir` (Glimmer `common.glsl`), `sunPathRotation`, `worldDay`, `worldTime`,
    `frameTimeCounter`, `gbufferProjection`, `viewHeight`.
  - `moonPhaseBrightness()` from `celestial.glsl`, and `sincos`, `luminance`, `hash33` and `pow2` from
    Glimmer and Halcyon utilities.
  - `customTexture.starCatalogTex` (RGBA32F 1024×260) and `customTexture.milkyWayTex`.
  - Its constants must match `tools/nasa_night_sky.py`.
- **Standalone transplant**: feasible for the code, but useless without the catalogue texture and the
  Milky Way texture. The catalogue would have to be regenerated from the primary catalogues under their
  own terms. The Milky Way texture carries Gaia's NC licence.

### 4.5 `shaders/lib/atmosphere/sky/celestial.glsl`

- **Classification: OWNED_ORIGINAL.**
- **Evidence**:
  - Code overlap is 1.5%: one `dot(rayDir, worldSunDir)` line and two `return vec3(0.0)`.
  - No Glimmer commit mentions eclipses or Lommel-Seeliger shading. Glimmer only declares a constant
    `moonAngularRadius` and uses vanilla `moonPhase`.
- **Contents**:
  - Eclipse state from a scaled synodic/draconic month model.
  - Circle-overlap area, a standard geometric formula.
  - Solar limb darkening with per-channel coefficients. Their source was not identified.
  - A corona during totality.
  - Moon phase brightness from Allen's Astrophysical Quantities (credited, published formula).
  - A Lommel-Seeliger moon with height-map bumps, earthshine and umbra/penumbra tint.
  - `celestialHash`, which is the folklore sin-fract hash (public, unattributable).
- **Callers**: included from `lib/atmosphere/sky/hillaireCommon.glsl`, so every program that includes
  the Hillaire sky (`sky.glsl`, `prepare*.glsl`, `setup*.csh`, the fog and lighting code) sees it.
  `sunDiskRadiance` / `moonDiskRadiance` / `moonGlow` are used by the sky.
  `eclipseSunlightFactor` and `getEclipseState` feed lighting.
- **Glimmer coupling**:
  - `sunIrradiance`, defined in Glimmer's `hillaireCommon.glsl` (Helmer-derived; UNKNOWN licence chain).
  - `worldSunDir`, `moonPhase`, `worldDay`, `worldTime`, `wetness`.
  - `customTexture.moonTex` (NASA), and the `pow2` / `max0` / `clamp01` macros.
  - Settings `SUN_SIZE`, `MOON_SIZE`, `SUN_BRIGHTNESS`, `MOON_BRIGHTNESS`, `ECLIPSES`,
    `ECLIPSE_FREQUENCY`, `ECLIPSE_PREVIEW`, `CUSTOM_MOON`, `MOON_BUMP`, `WORLD_OVERWORLD`.
- **Standalone transplant**: easy. Replace `sunIrradiance` with your own constant and provide a moon
  texture with height in alpha. `tools/nasa_moon.py`, which built that texture, is missing.

### 4.6 `shaders/lib/atmosphere/sky/aurora.glsl`

- **Classification: OWNED_ORIGINAL.**
- **Evidence**:
  - Code overlap is 1%. No Glimmer history mentions aurora. Halcyon's CHANGELOG lists aurora from its
    first version.
- **Known public pieces**:
  - `auroraHash` uses the PCG multiplier 747796405u with the 277803737u xorshift-multiply output step.
    That is the "pcg" hash published by Jarzynski & Olano (JCGT 2020), derived from O'Neill's PCG. The
    added stream constant and the 12345u offset are Halcyon's. The snippet is short, published and widely
    copied; credit is advisable.
  - The rest is generic: noise-warped sine curtains, an exponential altitude profile and a colour ramp.
- **Callers**: `lib/atmosphere/sky/sky.glsl`, via `auroraActivity()` and `getAurora()`. `stars.glsl`
  also reads the activity level.
- **Glimmer coupling**:
  - `perlinNoiseTex` (UNKNOWN origin) and `interleavedGradientNoise` (Glimmer `util.glsl`).
  - `worldDay`, `worldTime`, `frameTimeCounter`, `frameCounter`, `rainStrength`, `worldSunDir`.
  - `clamp01`, and settings `AURORA`, `AURORA_FREQUENCY`, `AURORA_QUALITY`, `AURORA_BRIGHTNESS`.
- **Standalone transplant**: easy. It needs only a tiling 2D noise texture and IGN.

### 4.7 `shaders/lib/atmosphere/sky/blackHole.glsl`

- **Classification: OWNED_ORIGINAL.**
- **Evidence**:
  - Code overlap is 2%, only trivial `return` and initialisation lines. No Glimmer history mentions a
    black hole. The CHANGELOG lists it under alpha.13.
- **Method**:
  - RK4 integration of the Schwarzschild photon orbit equation u'' = 3u² − u, in the photon's plane.
  - Disk-plane crossing by sign change.
  - Disk temperature from a Shakura-Sunyaev-like profile normalised by a fitted 0.4879.
  - Doppler and gravitational redshift.
  - A blackbody colour from **Tanner Helland's fit** (credited, published approximation).
  - Rodrigues rotation; crossfaded flow-noise for the disk.
  - A cosmic background with nebulae, galaxies and `starLayer` stars.

  All of these are standard; this kind of black-hole renderer is common on Shadertoy. Inference: no
  specific Shadertoy source was identified, and none was diffed.
- **Callers**: `lib/atmosphere/sky/sky.glsl` (End sky, via `cosmicSky()`) and `lib/endPortal.glsl`.
- **Glimmer coupling**:
  - `worldLightDir` (Glimmer `common.glsl`), `frameTimeCounter`, `gbufferProjection`, `viewHeight`.
  - `cloudNoiseTex` (3D, UNKNOWN origin) and `perlinNoiseTex`.
  - `starLayer` and `hash33` (`stars.glsl` and `util.glsl`), `endAmbientSky` (Halcyon), and
    `luminance` / `clamp01` / `pow2`.
  - Settings `BH_*`, `NEBULA_*`, `END_STAR_*`, `COSMIC_*`.
- **Standalone transplant**: feasible. It needs the star-layer helper, a hash, and a 3D noise texture.

### 4.8 `shaders/lib/atmosphere/sky/rainbow.glsl`

- **Classification: OWNED_ORIGINAL.**
- **Evidence**:
  - Code overlap is 3%, a single `return 0.0`. Glimmer's only "rainbow" is a block-outline colour mode.
  - The content is heuristic: a smoothstep spectral ramp, primary bow at 40.6° and secondary at 50.3°,
    and Alexander's dark band. No physical Mie or Airy model, nothing distinctive.
- **Callers**: `lib/atmosphere/sky/sky.glsl`.
- **Glimmer coupling**: `worldSunDir`, `rainStrength`, `clamp01`, plus `surfaceWetness` and
  `biomeCanRainSmooth`. Those two are custom uniforms in `shaders.properties`; `surfaceWetness` is
  Halcyon's. Settings `RAINBOWS` and `RAINBOW_BRIGHTNESS`.
- **Standalone transplant**: trivial.

---

## 5. Textures and asset tools

### 5.1 Textures (`shaders/textures/`)

| File | Byte-identical to Glimmer? | Source and terms | Class |
|---|---|---|---|
| `tonyMcMapface.bin` (48³ RGBA32F LUT) | Yes. Added in Glimmer `e778fe0`, 2025-10-04. | Tony McMapface, Tomasz Stachowiak, MIT or Apache-2.0. Keep `LICENSE-MIT_tony_mc_mapface`. | LICENSED_REUSE |
| `LICENSE-MIT_tony_mc_mapface` | Code-identical; Halcyon prepended one jokey line | Licence notice | LICENSED_REUSE |
| `blueNoise.png` (4.2 MB) | Yes. In Glimmer since 2025-01-03 (`0c4d988`). | Upstream not documented in Glimmer. Common sources are Christoph Peters' free blue noise and Heitz et al.; not identified here. | UNKNOWN |
| `perlinNoise.png` | Yes | Not documented | UNKNOWN |
| `caustics.png`, `caustics_new.png` | Yes. In Glimmer since 2024-12-20 and 2025-10-04. | Not documented | UNKNOWN |
| `cloudNoise.bin` (64³ RGBA8, 3D) | No Glimmer match | The CHANGELOG claims "I just made myself". No generator script is in the repo. | UNKNOWN (claimed own) |
| `moon_2k.png`, `moon_4k.png` | No Glimmer match | NASA SVS 4720 CGI Moon Kit: LROC WAC colour, LOLA height in alpha. The generator `tools/nasa_moon.py` is missing. Credit: "NASA's Scientific Visualization Studio"; Ernie Wright (USRA), Noah Petro (NASA/GSFC); LROC WAC (NASA/GSFC/Arizona State University). Follow the NASA media guidelines and imply no endorsement. | LICENSED_REUSE (attribution) |
| `milkyway_4k.png`, `milkyway_8k.png` | No | Built from NASA SVS 4851 Deep Star Maps 2020, whose unresolved background is from **Gaia DR2**, plus Hipparcos-2 and Tycho-2. Gaia data are **CC BY-NC 3.0 IGO** (verified on ESA's page). Credit NASA/GSFC SVS and ESA/Gaia/DPAC. | EXTERNAL_RESTRICTED (non-commercial only; commercial use needs ESA permission) |
| `starCatalog.bin` (RGBA32F 1024×260) | No | Built by `nasa_night_sky.py` from the Hipparcos Main Catalogue (ESA 1997, VizieR I/239) and Yale BSC 5th ed. (VizieR V/50), plus a computed blackbody LUT. The terms of ESA's archive and CDS for redistributing derived catalogue data were not checked. | UNKNOWN (likely attribution-only; unverified) |
| `*.mcmeta` (6) | Trivial JSON (blur/clamp flags) | n/a | LICENSED_REUSE |
| `CREDITS-night-sky.md` | New | Halcyon's credits note | OWNED_ORIGINAL |

NASA SVS pages (verified): both state "Please give credit for this item to" the NASA SVS, and neither
states a licence. NASA imagery is generally not copyrighted in the US, but third-party data inside it
keeps its own terms. That is the case for Gaia in 4851.

### 5.2 Tools (`tools/`, not shipped in the zip)

- **`nasa_night_sky.py`** (OWNED_ORIGINAL; MIT per `CREDITS-night-sky.md`). It reads the SVS 4851 16k EXR
  layers and VizieR TSVs, cuts catalogue stars out of the hiptyc layer, warps latitude by asinh, and
  encodes 8-bit PNGs and the star bin. B−V to temperature uses Ballesteros (2012), a published formula.
  CIE matching functions are computed in code.
  - Code overlap with Glimmer is 0.6%.
  - The inputs are not redistributed. The outputs inherit the input terms (Gaia NC).
- **`preview_night_sky.py`** and **`preview_clouds_gpu.py`** (OWNED_ORIGINAL). These are developer
  preview harnesses. `preview_clouds_gpu.py` re-implements bits of shader code (an IGN call) for offline
  preview; its overlap with Glimmer is about 6%, all trivial.
- **Missing**: `tools/nasa_moon.py`, which `celestial.glsl` cites. The moon-texture processing cannot be
  audited.

---

## 6. Tonemapping

Verified:
- Halcyon `shaders/lib/post/tonemap.glsl` keeps 99% of Glimmer's code lines. `final.glsl` calls
  `tonemap()`, which `#define tonemap tonyMcMapface` maps to Tony McMapface by default. The other
  selectable options are `lottesTonemap`, `agxTonemap`, `jodieReinhardTonemap`,
  `uncharted2FilmicTonemap`, `hejlBurgessTonemap` and `ACESTonemap`.
- Glimmer's default operator by date:
  - 2024-12-17 (`dec1fde`): `jodieReinhardTonemap`.
  - 2024-12-23 (`4398b77`): `hejlBurgessTonemap`.
  - 2025-01-10 (`ba7fd92`, then `fe12c96`): `agxTonemap`, then `uncharted2FilmicTonemap`.
  - 2025-06-11 (`b18465e`): `lottesTonemap`. The `v2` and `aperture_compat` branches still default to
    Lottes.
  - 2025-10-04 (`e778fe0`, "reshuffle some stuff + new caustics"): `tonyMcMapface`, now on `main` and
    `deferred`.
- Halcyon changed only two lines against Glimmer `main`:
  - It removed Glimmer's `stimulus *= 3.0` pre-exposure.
  - It wraps the LUT result in a 1/2.2 power, so the output is display-encoded at that point.
- Operator sources:

  | Operator | Source | Licence |
  |---|---|---|
  | Tony McMapface | h3r2tic/tony-mc-mapface | MIT / Apache-2.0 (verified) |
  | Lottes | Copied from dmnsgn/glsl-tone-map (MIT, verified), which credits Lottes 2016 | MIT |
  | AgX | Polynomial sigmoid fit plus ASC-CDL Default/Golden/Punchy looks, matching Benjamin Wrensch's "Minimal AgX implementation" (Troy Sobotka's AgX). Glimmer does not credit it. | Not verified |
  | Jodie-Reinhard, Uncharted 2 (Hable), Hejl-Burgess, ACES (Narkowicz fit) | Short published formulas, in the same arrangement as dmnsgn/glsl-tone-map | MIT for that collection |

Inference: everything in Halcyon's tonemap file comes from Glimmer or its upstreams. None of it is the
user's own work, apart from the two-line change.

---

## 7. Implications for Belgium Shaders

### 7.1 May be reused (with obligations)

**OWNED_ORIGINAL modules.** Reusable only if the user confirms they wrote them, and with the AI caveat on
the water sim. Each needs a Belgium-side reimplementation of the Glimmer dependencies listed in section 4,
not a copy of Glimmer's `util.glsl`, `syntax.glsl` or `uniforms.glsl`. The modules:

- `lib/water/waterSim.glsl` and `program/waterSim.glsl`
- `lib/water/caustics.glsl`
- `lib/atmosphere/sky/stars.glsl`, `celestial.glsl`, `aurora.glsl`, `blackHole.glsl`, `rainbow.glsl`
- `cirrus.glsl`, `volumetricClouds.glsl`, `cloudComposite.glsl`, `rainRipples.glsl`,
  `underwaterShafts.glsl`, the SSGI / DOF / volumetric-cloud programs
- `tools/*.py`

Embedded published snippets need credit if reused:

- Patra & Karttunen stencil
- Finch / GPU Gems Gerstner
- Heitz 2014 masking, and Heitz 2018 VNDF (`ggx.glsl`)
- Duff et al. orthonormal basis (`ggx.glsl`, uncredited in Halcyon)
- PCG hash (Jarzynski & Olano)
- Helland blackbody fit
- Allen lunar magnitude
- Ballesteros B−V
- Catmull-Rom 5-tap (uncredited in Halcyon)
- Hoskins hashes: MIT, notice required

**Swell, micro-wave, footprint and masking parts of `waveNormals.glsl`.** Their Halcyon authorship is as
above, but they must be extracted away from the afl_ext core.

**LICENSED_REUSE.**
- Tony McMapface (ship its MIT or Apache licence text).
- NASA moon imagery (credit SVS, Wright and Petro, LROC/ASU). Belgium already builds its own from the
  NASA originals.
- `ggx.glsl` as published algorithms.
- Glimmer-MIT code is *legally* reusable if Glimmer's copyright and permission notice is kept. Doing so
  would end Belgium's "no Glimmer code" position, so under project policy it **must not** be used.

### 7.2 Must not be reused

- **MIXED_ORIGIN files as files.** Also anything that is only Glimmer code carrying Halcyon comments.
  Project policy, and the Glimmer notice obligation.
- **`FXAA.glsl`** (BSL) and **`blocklightColors.glsl`** (Complementary values).
- **`spaceConversions.glsl`**: LGPL-3.0; incompatible with Belgium's licensing intent unless complied
  with.
- **`milkyway_*.png`**: Gaia CC BY-NC 3.0 IGO. Non-commercial redistribution with credit is permitted,
  but they are Halcyon's processed files and Belgium's policy is to use its own processing.

### 7.3 Unknown, do not reuse until resolved

- `hillaireCommon.glsl` and the Helmer-derived sky LUT code (Shadertoy licence unknown).
- `textRenderer.glsl`.
- `blueNoise.png`, `perlinNoise.png`, `caustics*.png`.
- `cloudNoise.bin` (no generator).
- `starCatalog.bin` (ESA/CDS redistribution terms unchecked).
- The tonemapper AgX variant.
- Whether the "OWNED_ORIGINAL" code is the user's own or AI-generated. The user should confirm this per
  module.

### 7.4 What Halcyon has that Belgium lacks

Based on reading Belgium's `shaders/lib/water/`, `lib/sky/`, `lib/end/` and `lib/post/tonemap.glsl`:

- Belgium already covers:
  - water: interactive sim (player and vehicle sources, splash, idle sleep, sponge, 9-point Laplacian),
    analytic waves with a Hessian, capillary waves, footprint filtering, Jacobian caustics;
  - sky: scintillating stars, NASA moon with earthshine and limb darkening, eclipses and corona, a
    physically based aurora, a Descartes-angle rainbow;
  - End: Schwarzschild black hole with Doppler and a photon ring, nebulae and galaxies;
  - its own fitted filmic tonemap.
- The substantive differences:
  - **Real catalogue stars.** Belgium is procedural by design. Halcyon's 41k Hipparcos stars plus
    seasonal right ascension is the one capability Belgium lacks. It would have to be rebuilt from the
    primary catalogues, not from Halcyon's `starCatalog.bin`.
  - B-spline (C²) sampling of the sim height. Belgium stores gradients in the texture, which may make
    this moot.
  - Alexander's dark band in the rainbow. Trivial.
- Ideas and algorithms are not restricted by any of the above; code and data files are.

### 7.5 Related finding about Belgium itself (not Halcyon)

Belgium's own `shaders/textures/milkyway.png` is built by `tools/prep_milkyway.py` from the same SVS 4851
source. That script's docstring calls the data "Public domain". Two problems:

- SVS 4851's background is Gaia DR2, which is CC BY-NC 3.0 IGO (verified).
- `docs/THIRD_PARTY_ASSETS.md` says no sky-survey imagery is included.

Both statements should be reviewed. This audit did not edit them.

---

## 8. Not verified

- Upstream licences for BSL (site error), Complementary (licence URL 404), sixthsurge's text renderer,
  Helmer's `slSXRW` and afl_ext's `MdXyzX` (Shadertoy 403), Wrensch's AgX, the Belmu SSR gist and
  Shadertoy `7sfXDn`.
- The origin of Glimmer's `blueNoise.png`, `perlinNoise.png` and `caustics*.png`.
- ESA/CDS redistribution terms for Hipparcos and Yale BSC derived data.
- Whether the LUT file is covered by Tony McMapface's dual licence. The repo README does not say.
- Comparison against Eclipse, Bliss, Complementary, Photon, BSL or Shadertoy code. Only Glimmer, in all
  220 commits and 8 branches, was diffed.
- `tools/nasa_moon.py`, which is absent.
- Who actually wrote the OWNED_ORIGINAL code, and how much of it was AI-generated. The repository cannot
  establish this.

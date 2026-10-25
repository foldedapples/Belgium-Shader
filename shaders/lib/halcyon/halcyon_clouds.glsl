#ifndef HALCYON_CLOUDS_GLSL
#define HALCYON_CLOUDS_GLSL
// Halcyon's volumetric clouds (lib/halcyon/atmosphere/volumetricClouds.glsl, unmodified) inside
// Belgium's cloud passes (Cloud Source = Halcyon): deferred (reduced-resolution march),
// deferred1 (temporal reconstruction) and prepare (cloud shadow map) stay Belgium's; the density
// field, lighting and march are Halcyon's. Nubis-style: a weather map with coverage, cloud type
// and storm cells; per-type vertical profiles from flat stratus through cumulus to
// cumulonimbus towers with anvils; wind shear; Perlin-Worley base eroded by detail noise; four
// octaves of multiple scattering; adaptive near/far stepping with coarse empty-space skipping.
#include "/lib/halcyon/adapter_core.glsl"

#include "/lib/halcyon/hc_begin.glsl"
#include "/lib/halcyon/adapter_region.glsl"
// Glimmer's view-space dominant light and sun, compared by the march to tell day from night.
// Region-local to the clouds only: other Halcyon code uses `lightDir` as a parameter name.
#define lightDir (fsLightDir.xyz)
#define sunDir (fsSunDir.xyz)
#include "/lib/halcyon/atmosphere/volumetricClouds.glsl"
#undef lightDir
#undef sunDir

// In-scattered radiance (rgb) and transmittance (a) along `dir` (scene space) up to `maxDist`;
// `depth` is the transmittance-weighted cloud distance, or -1 when the ray met no cloud.
vec4 halcyonCloudMarch(vec3 dir, float maxDist, float jitter, out float depth) {
    vec3 transmittance;
    vec3 scattering = getVolumetricClouds(vec3(0.0), dir, VC_STEPS_Q, jitter, maxDist, transmittance, depth);
    return vec4(scattering, transmittance.x);
}

// Cloud transmittance toward the light for a scene-space point (Cloud Shadow Visibility mixes
// it toward 1, as in Halcyon).
float halcyonCloudShadow(vec3 scenePos) {
    return mix(1.0, getVolumetricCloudShadow(scenePos, 8).x, CLOUD_SHADOW_VISIBILITY);
}

// Bottom and top of Halcyon's cloud layer (world y), and its coverage, for Belgium's FrameState.
vec2 halcyonCloudLayer() { return vcLayer(); }
float halcyonCloudCoverage() { return vcCoverage(); }

#include "/lib/halcyon/adapter_region_end.glsl"
#include "/lib/halcyon/hc_end.glsl"

#endif

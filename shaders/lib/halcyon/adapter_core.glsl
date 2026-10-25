#ifndef HALCYON_ADAPTER_CORE_GLSL
#define HALCYON_ADAPTER_CORE_GLSL
// The interface the imported Halcyon modules expect (it used to come from Glimmer), written
// for Belgium Shaders' engine. Only names that are unique to Halcyon live here, so this file is
// safe to include anywhere; names that would clash with Belgium are defined in
// adapter_region.glsl and exist only between hc_begin.glsl and hc_end.glsl.
// See docs/HALCYON_INTEGRATION.md for the unit conventions.
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

// ---------------------------------------------------------------- small helpers
#define clamp01(x) clamp(x, 0.0, 1.0)
#define max0(x) max(x, 0.0)
float pow2(float x) { return x * x; }
vec2  pow2(vec2 x)  { return x * x; }
vec3  pow2(vec3 x)  { return x * x; }
float pow3(float x) { return x * x * x; }
vec3  pow3(vec3 x)  { return x * x * x; }
float rcp(float x)  { return 1.0 / x; }
vec2  sincos(float x) { return vec2(sin(x), cos(x)); }

// Interleaved gradient noise (Jimenez 2014), with the per-frame offset Halcyon expects.
float interleavedGradientNoise(vec2 coord) {
    return fract(52.9829189 * fract(dot(coord, vec2(0.06711056, 0.00583715))));
}
float interleavedGradientNoise(vec2 coord, int frame) {
    return interleavedGradientNoise(coord + 5.588238 * float(frame & 63));
}

// Halcyon's hash (Dave Hoskins, "Hash without Sine", MIT); Belgium's hash33 takes ivec3.
vec3 hash33(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Halcyon calls henyeyGreenstein(g, cosTheta); Belgium's takes (cosTheta, g). Inside the
// Halcyon region the name is mapped here (hc_begin.glsl).
float hc_henyeyGreenstein(float g, float cosTheta) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-6), 1.5));
}

// ---------------------------------------------------------------- resources
uniform sampler2D perlinNoiseTex;   // textures/perlin2d.png (ours, statistics-matched)
uniform sampler2D moonTex;          // Halcyon NASA moon disk (textures/halcyon)
uniform sampler2D milkyWayTex;      // Halcyon NASA Milky Way, galactic, asinh-warped
uniform sampler2D starCatalogTex;   // Halcyon Hipparcos + Yale BSC catalogue (RGBA32F)
uniform float hc_surfaceWetness;    // Halcyon's custom uniform (shaders.properties)

// ---------------------------------------------------------------- units
// Halcyon's night-sky constants were tuned against Glimmer's moonlight, whose luminance
// (0.00268) matches Belgium's full-moon irradiance (SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO);
// night objects are rescaled by the ratio so they keep their look under Belgium's exposure.
const float HC_NIGHT_SCALE = (SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO) / 0.00268;
// Halcyon's sun disk uses the solar spectrum tint below at Belgium's solar irradiance.
const vec3 HC_SUN_IRRADIANCE = vec3(1.0, 0.949, 0.937) * SUN_IRRADIANCE;

#endif

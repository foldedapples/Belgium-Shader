#ifndef CORE_BLUE_NOISE_GLSL
#define CORE_BLUE_NOISE_GLSL
#include "/lib/core/noise.glsl"
#include "/lib/core/uniforms.glsl"

// 128x128 RGBA blue noise (tools/gen_noise.py), animated over time with an additive
// low-discrepancy offset so successive frames stay well distributed for TAA to integrate.
uniform sampler2D blueNoiseTex;

vec4 blueNoiseStatic(ivec2 pixel) { return texelFetch(blueNoiseTex, pixel & 127, 0); }

vec4 blueNoise(ivec2 pixel) {
    vec4 n = blueNoiseStatic(pixel);
    vec2 o = r2Sequence(frameCounter & 1023);
    return fract(n + vec4(o, o.yx));
}

#endif

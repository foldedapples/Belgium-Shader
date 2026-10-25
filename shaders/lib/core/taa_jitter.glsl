#ifndef CORE_TAA_JITTER_GLSL
#define CORE_TAA_JITTER_GLSL
#include "/lib/core/uniforms.glsl"

// Sub-pixel projection jitter for temporal anti-aliasing: 8-point Halton(2,3) sequence,
// centred, in pixels. Every geometry program applies it so the G-buffer is consistent.
const vec2 HALTON_23[8] = vec2[8](
    vec2(0.500000, 0.333333), vec2(0.250000, 0.666667), vec2(0.750000, 0.111111),
    vec2(0.125000, 0.444444), vec2(0.625000, 0.777778), vec2(0.375000, 0.222222),
    vec2(0.875000, 0.555556), vec2(0.062500, 0.888889));

vec2 taaJitterPixels(int frame) {
    #ifdef TAA
        return HALTON_23[frame & 7] - 0.5;
    #else
        return vec2(0.0);
    #endif
}

void applyTaaJitter(inout vec4 clipPos) {
    #ifdef TAA
        clipPos.xy += taaJitterPixels(frameCounter) * 2.0 / vec2(viewWidth, viewHeight) * clipPos.w;
    #endif
}

#endif

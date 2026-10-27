#ifndef MERIDIAN_JITTER
#define MERIDIAN_JITTER

// Sub-pixel projection jitter for temporal anti-aliasing: an 8-point Halton(2,3) sequence,
// centred on zero, in pixels. Applied in clip space by every geometry program (not the sky).
vec2 taaJitterPixels(int frame) {
    const vec2 halton[8] = vec2[8](
        vec2(0.500000, 0.333333), vec2(0.250000, 0.666667), vec2(0.750000, 0.111111), vec2(0.125000, 0.444444),
        vec2(0.625000, 0.777778), vec2(0.375000, 0.222222), vec2(0.875000, 0.555556), vec2(0.062500, 0.888889));
    return halton[frame & 7] - 0.5;
}

vec4 applyJitter(vec4 clip) {
    #ifdef TAA
    clip.xy += taaJitterPixels(frameCounter) * 2.0 / vec2(viewWidth, viewHeight) * clip.w;
    #endif
    return clip;
}

#endif

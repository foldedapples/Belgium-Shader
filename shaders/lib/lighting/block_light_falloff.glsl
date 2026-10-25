#ifndef LIGHTING_BLOCK_LIGHT_FALLOFF_GLSL
#define LIGHTING_BLOCK_LIGHT_FALLOFF_GLSL
#include "/lib/core/math.glsl"

// Irradiance from a vanilla light level (15 at the emitter, one less per block of travel).
// A softened inverse square in the travelled distance (16 - level), tapered to zero over the
// last seven levels. Vanilla light stops abruptly at level 0 and spreads in a diamond, so a
// tail that is still bright at level 1 (as before: ~9x moonlight 14 blocks from a torch) shows
// as a hard-edged geometric patch at night; the taper lets it fade into the ambient instead.
// Shared by the lightmap (surface.glsl) and the hand light so both fall off identically.
float blockLightFalloff(float level) {
    level = clamp(level, 0.0, 15.0);
    float inverseSquare = pow(1.0 / (16.0 - level), 1.65);
    float taper = smoothstep(0.0, 7.0, level);
    return inverseSquare * taper * taper;
}

#endif

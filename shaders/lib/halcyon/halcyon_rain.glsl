#ifndef HALCYON_RAIN_GLSL
#define HALCYON_RAIN_GLSL
// Halcyon's rain ripples (lib/halcyon/water/rainRipples.glsl, unmodified) on Belgium's water
// and puddles (Rain Ripple Source = Halcyon). Each drop lives for one cycle at a fresh random
// position, the number of drops follows the rain intensity, and a splash marks the impact;
// two layers at different scales and a distance fade.
#include "/lib/halcyon/adapter_core.glsl"

#include "/lib/halcyon/hc_begin.glsl"
#include "/lib/halcyon/adapter_region.glsl"
#include "/lib/halcyon/water/rainRipples.glsl"

// Slope (dh/dx, dh/dz) of rain ripples at world position xz, `dist` blocks from the camera,
// under vanilla sky light `skyLight` (0..1).
vec2 halcyonRainRippleSlope(vec2 worldXZ, float dist, float skyLight) {
    return rainRippleSlope(worldXZ, rainRippleIntensity(skyLight), dist);
}

#include "/lib/halcyon/adapter_region_end.glsl"
#include "/lib/halcyon/hc_end.glsl"

#endif

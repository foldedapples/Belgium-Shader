#ifndef HALCYON_WATER_SIM_GLSL
#define HALCYON_WATER_SIM_GLSL
// Halcyon's interactive water (Water Source = Halcyon): its simulation (stepped by Halcyon's own
// program, shaders/program/halcyon/waterSim.glsl, as prepare_a..d) sampled on Belgium's water,
// and Halcyon's Gerstner ocean swells added to Belgium's wave spectrum.
#include "/lib/halcyon/adapter_core.glsl"

#include "/lib/halcyon/hc_begin.glsl"
#include "/lib/halcyon/adapter_region.glsl"
#include "/lib/halcyon/water/waterSim.glsl"
#include "/lib/halcyon/water/halcyon_waves.glsl"

// Slope / height of the simulated water at a scene-space point (zero outside the window).
vec2 halcyonWaterSimSlope(vec3 scenePos) { return waterSimSlope(scenePos); }
float halcyonWaterSimHeight(vec3 scenePos) { return waterSimHeight(scenePos); }

// Swell slope, band-limited by the pixel footprint (along / across the view direction).
vec2 halcyonSwellSlope(vec2 worldXZ, float openness, vec2 viewXZ, vec2 footprint) {
    #ifdef WATER_SWELLS
        float variance = 0.0;
        float amp = WAVE_SWELL * waterSwellMul() * mix(0.12, 1.0, openness);
        return swellSlope(worldXZ, amp, viewXZ, footprint, variance);
    #else
        return vec2(0.0);
    #endif
}

#include "/lib/halcyon/adapter_region_end.glsl"
#include "/lib/halcyon/hc_end.glsl"
#endif

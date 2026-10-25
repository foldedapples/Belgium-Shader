#ifndef END_END_SKY_GLSL
#define END_END_SKY_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/end/end_params.glsl"
#include "/lib/end/black_hole.glsl"
#include "/lib/end/planets.glsl"

// End sky and fog: the lensed deep-space backdrop with the black hole, and a dark violet
// haze over the islands lit by the accretion disk.

vec3 endSkyRadiance(vec3 dir, float pixelAngle) {
    #ifdef END_BLACK_HOLE
        vec3 sky = blackHoleSky(dir, pixelAngle);
    #else
        vec3 sky = spaceBackground(dir, pixelAngle);
    #endif
    #ifdef END_PLANETS
        // Planets lie between the observer and the hole: drawn over the lensed sky.
        vec4 pl = endPlanets(dir, pixelAngle, endBlackHoleDir(), endLightIrradiance(), endAmbientIrradiance());
        sky = pl.rgb + sky * (1.0 - pl.a);
    #endif
    return sky;
}

vec3 endFog(vec3 color, vec3 scenePos, float dist) {
    float t = 1.0 - exp(-dist * 0.0035 * END_FOG_DENSITY);
    vec3 dir = safeNormalize(scenePos);
    // Haze glows faintly toward the disk.
    float toward = pow(saturate(dot(dir, endBlackHoleDir()) * 0.5 + 0.5), 6.0);
    vec3 fogCol = endAmbientIrradiance() * INV_PI * 1.4 + endLightIrradiance() * toward * 0.004;
    return mix(color, fogCol, t);
}

#endif

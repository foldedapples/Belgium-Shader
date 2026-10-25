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
    float t = 1.0 - exp(-dist * endHazeExtinction());
    // Ambient light scattered by the haze (isotropic, haze albedo). The directional glow toward
    // the black hole is the volumetric-light pass's job when it is on (shadowed there).
    vec3 fogCol = endAmbientIrradiance() * INV_PI * END_HAZE_ALBEDO * 4.0;
    #ifndef VOLUMETRIC_LIGHT
        vec3 dir = safeNormalize(scenePos);
        float cosT = dot(dir, endBlackHoleDir());
        fogCol += endLightIrradiance() * END_HAZE_ALBEDO * mix(henyeyGreenstein(cosT, 0.6), 0.25 * INV_PI, 0.35);
    #endif
    return mix(color, fogCol, t);
}

#endif

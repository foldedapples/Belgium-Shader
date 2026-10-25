#ifndef END_PARAMS_GLSL
#define END_PARAMS_GLSL
#include "/lib/core/common.glsl"

// The End's light comes from the accretion disk of the black hole drawn in its sky. Its
// direction is fixed in the world so shadows and the sky agree; the disk's integrated colour
// is a ~6500 K blend of the hot inner disk and cooler outer disk.

vec3 endBlackHoleDir() {
    float azDeg = END_BH_AZIMUTH, elDeg = END_BH_ELEVATION;
    #ifdef END_BH_DRIFT
        // Slow deterministic drift around the chosen position (light and shadows follow).
        // Periods divide the 3600 s wrap of frameTimeCounter, so the path is continuous;
        // at most ~0.03 deg/s, too slow for shadow edges to crawl visibly.
        float w = TAU * frameTimeCounter / 3600.0;
        azDeg += 18.0 * sin(w);
        elDeg += 5.0 * sin(2.0 * w + 1.1);
    #endif
    float az = azDeg * (PI / 180.0);
    float el = elDeg * (PI / 180.0);
    return normalize(vec3(cos(el) * sin(az), sin(el), -cos(el) * cos(az)));
}

vec3 endLightIrradiance() {
    return blackbody(6200.0) * (0.55 * END_LIGHT_INTENSITY);
}

vec3 endAmbientIrradiance() {
    return vec3(0.32, 0.26, 0.44) * 0.045 * END_LIGHT_INTENSITY;
}

#endif

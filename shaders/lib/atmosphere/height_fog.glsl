#ifndef ATMOSPHERE_HEIGHT_FOG_GLSL
#define ATMOSPHERE_HEIGHT_FOG_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/core/phase_functions.glsl"

// Low ground fog: exponential height profile k*exp(-(y - y0)/H) whose optical depth along a
// ray has the closed form k H (e^{-a} - e^{-b}) / dy. Density comes from three sources:
// morning mist around sunrise, rain haze, and a small baseline that lets light shafts show.
// The same medium is used by the volumetric-light pass (heightFogDensityAt).

const float FOG_BASE_Y = 62.0;

struct FogMedium { float k; float h; };

// Two layers: shallow morning mist and a deep rain haze.
FogMedium morningFog() {
    float t = fsTime.z;                                   // day fraction, 0 = sunrise
    float d = min(abs(t), abs(1.0 - t));                  // distance to sunrise in days
    float m = exp(-sq(d / 0.06)) * MORNING_FOG * (0.4 + 0.6 * biomePrecipSmooth);
    return FogMedium(0.02 * m, 10.0);
}
FogMedium rainFog() {
    float r = fsWeather.z * 0.6 + fsWeather.y * 0.4;
    return FogMedium(0.006 * r * WEATHER_FOG + 0.0006 * VOLUMETRIC_FOG_BASELINE, 70.0);
}

float layerDensity(FogMedium f, float y) {
    return f.k * exp(-max(y - FOG_BASE_Y, -20.0) / f.h);
}
float heightFogDensityAt(float y) { return layerDensity(morningFog(), y) + layerDensity(rainFog(), y); }

float layerOpticalDepth(FogMedium f, float y0, float dy, float dist) {
    float a = max(y0 - FOG_BASE_Y, -20.0) / f.h;
    if (abs(dy) < 1e-4) return f.k * exp(-a) * dist;
    float b = max(y0 + dy * dist - FOG_BASE_Y, -20.0) / f.h;
    return max(f.k * f.h * (exp(-a) - exp(-b)) / dy, 0.0);
}

// Applies the ground fog to `color` seen at `dist` along `dir`. With volumetric light on, the
// directional sun term is left to that pass (it is shadowed there); otherwise it is added
// here unshadowed.
vec3 applyHeightFog(vec3 color, vec3 dir, float dist, vec3 ambientE, vec3 lightE, vec3 lightDir) {
    float y0 = cameraPosition.y;
    float tau = layerOpticalDepth(morningFog(), y0, dir.y, dist) + layerOpticalDepth(rainFog(), y0, dir.y, dist);
    if (tau <= 1e-5) return color;
    float T = exp(-tau);
    vec3 inscatter = ambientE * (0.25 * INV_PI) * 0.9;
    #ifndef VOLUMETRIC_LIGHT
        inscatter += lightE * mix(henyeyGreenstein(dot(dir, lightDir), 0.55), 0.25 * INV_PI, 0.5);
    #endif
    return color * T + inscatter * (1.0 - T);
}

#endif

#ifndef WEATHER_LIGHTNING_GLSL
#define WEATHER_LIGHTNING_GLSL
#include "/lib/core/common.glsl"

// Lightning illumination. Iris exposes the active bolt's position relative to the camera
// (lightningBoltPosition, w = 1 while a bolt exists). The bolt is treated as a vertical line
// source from the ground to the cloud base: irradiance falls off with the inverse horizontal
// distance (line source), plus a sky-wide flash that lights everything under open sky.

vec3 lightningIrradiance(vec3 scenePos, vec3 n, float skyLight) {
    if (lightningBoltPosition.w <= 0.0 || LIGHTNING_BRIGHTNESS <= 0.0) return vec3(0.0);
    vec2 d = lightningBoltPosition.xz - scenePos.xz;
    float r = max(length(d), 1.0);
    vec3 toBolt = normalize(vec3(d.x, 12.0, d.y));
    float facing = saturate(dot(n, toBolt) * 0.7 + 0.3);
    vec3 colour = vec3(0.78, 0.84, 1.0);
    float local = 40.0 / (1.0 + r / 6.0) * facing;
    float sky = 0.6 * pow(saturate(skyLight), 3.0);
    return colour * (local + sky) * LIGHTNING_BRIGHTNESS;
}

#endif

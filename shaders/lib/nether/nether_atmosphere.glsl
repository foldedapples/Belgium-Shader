#ifndef NETHER_ATMOSPHERE_GLSL
#define NETHER_ATMOSPHERE_GLSL
#include "/lib/core/common.glsl"

// Nether atmosphere: no sky, a dense biome-coloured haze lit from below by lava seas.
// fogColor carries the biome tint (crimson, warped, soul sand valley, basalt deltas, wastes).

vec3 netherHazeColor() {
    return srgbToLinear(fogColor) * 0.9 + vec3(0.02, 0.006, 0.0);
}

vec3 netherSkyRadiance(vec3 dir) {
    // Brighter toward the horizon and below, where lava light scatters in the haze.
    float below = saturate(-dir.y * 0.5 + 0.55);
    return netherHazeColor() * (0.35 + 0.65 * below) * NETHER_BRIGHTNESS;
}

// Ambient irradiance: haze from all around plus warm lava bounce from below.
vec3 netherAmbientIrradiance(vec3 n) {
    vec3 haze = netherHazeColor() * 0.55;
    vec3 lavaBounce = blackbody(1500.0) * 0.06 * saturate(-n.y * 0.6 + 0.4);
    return (haze + lavaBounce) * NETHER_BRIGHTNESS;
}

// Smoke: the haze density is modulated by slowly drifting 3-D noise sampled at a few points
// along the view ray, so the fog has billowing structure instead of a uniform wall.
float netherSmoke(vec3 scenePos, float dist) {
    #ifdef NETHER_SMOKE
        vec3 dir = scenePos / max(dist, 1e-3);
        float sum = 0.0;
        vec3 drift = vec3(0.6, 0.25, 0.4) * frameTimeCounter;
        for (int i = 0; i < 4; i++) {
            float t = dist * (float(i) + 0.5) / 4.0;
            vec3 p = (mod(cameraPosition, 512.0) + dir * t + drift) / 14.0;
            sum += valueNoise(p) * 0.65 + valueNoise(p * 2.7) * 0.35;
        }
        return mix(0.55, 1.6, smoothstep(0.35, 0.75, sum / 4.0));
    #else
        return 1.0;
    #endif
}

vec3 netherFog(vec3 color, vec3 scenePos, float dist) {
    float density = 0.012 * NETHER_FOG_DENSITY * netherSmoke(scenePos, dist);
    float t = 1.0 - exp(-dist * density);
    return mix(color, netherSkyRadiance(safeNormalize(scenePos)), t);
}

#endif

#ifndef MATERIAL_WAVING_GLSL
#define MATERIAL_WAVING_GLSL
#include "/lib/core/common.glsl"
#include "/lib/material/material_ids.glsl"

// Wind sway for plants and leaves, evaluated in world space so the gbuffer and shadow passes
// move every vertex identically (shadows stay attached). Plants pivot at their base: only
// vertices above the block's centre move (decided from the texture coordinate relative to the
// tile centre, which is the top half of the sprite). Wind follows the water/cloud wind
// direction and strengthens with rain and storms.

vec3 waveOffset(vec3 worldPos, int material, bool topVertex, float skyLight) {
    #ifdef WAVING_PLANTS
    if (!isFoliage(material) || material == MAT_LILY_PAD) return vec3(0.0);
    float a = radians(WATER_WIND_ANGLE);
    vec2 wind = vec2(cos(a), sin(a));
    float t = frameTimeCounter;
    float gust = 0.6 + 0.4 * sin(dot(worldPos.xz, wind) * 0.07 - t * 0.9);
    float strength = WAVING_STRENGTH * (0.6 + 0.8 * rainStrength + 0.8 * thunderStrength) * gust;
    // Sheltered plants (under roofs, in caves) barely move.
    strength *= smoothstep(0.3, 0.9, skyLight);
    vec3 p = mod(worldPos, 256.0);
    float phase = p.x * 0.73 + p.z * 0.61 + p.y * 0.37;
    float sway = sin(t * 2.1 + phase) * 0.7 + sin(t * 3.7 + phase * 1.9) * 0.3;
    vec3 offset = vec3(wind.x, 0.0, wind.y) * sway * 0.06 * strength;
    if (material == MAT_LEAVES || material == MAT_VINE) {
        // Leaves rustle in place in all directions with a smaller amplitude.
        offset = vec3(sin(t * 2.7 + phase), sin(t * 3.3 + phase * 1.3) * 0.5, cos(t * 2.3 + phase * 0.7)) * 0.025 * strength;
        return offset;
    }
    if (material == MAT_PLANT_TALL_HIGH) return offset * 2.0;            // whole upper half moves
    if (material == MAT_PLANT_TALL_LOW) return topVertex ? offset : vec3(0.0);
    if (material == MAT_WATER_PLANT) return topVertex ? offset * 0.6 : vec3(0.0);
    return topVertex ? offset : vec3(0.0);
    #else
    return vec3(0.0);
    #endif
}

#endif

#ifndef MERIDIAN_EMITTERS
#define MERIDIAN_EMITTERS
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/material/ids.glsl"


// Emission colours (linear, max component 1) by material ID. Chosen from the emitters' physical
// character: flames ~1900-2100 K blackbody, soul fire copper-chloride cyan, redstone a deep red,
// sea lanterns and end rods cool white, etc. Brightness comes from the block's vanilla light level.

vec3 blackbody(float kelvin) {
    // Fit of CIE 1931 blackbody chromaticity converted to linear Rec.709, normalised to max = 1.
    float t = kelvin / 100.0;
    vec3 c;
    c.r = t <= 66.0 ? 1.0 : 1.29293618 * pow(t - 60.0, -0.1332047592);
    c.g = t <= 66.0 ? 0.39008157 * log(t) - 0.63184144 : 1.12989086 * pow(t - 60.0, -0.0755148492);
    c.b = t >= 66.0 ? 1.0 : (t <= 19.0 ? 0.0 : 0.54320678 * log(t - 10.0) - 1.19625408);
    c = srgbToLinear(saturate(c));
    return c / max(maxOf(c), 1e-4);
}

vec3 emitterColor(int id) {
    if (id == MAT_TORCH || id == MAT_FIRE || id == MAT_CAMPFIRE || id == MAT_CANDLE || id == MAT_FURNACE_LIT) return blackbody(1900.0);
    if (id == MAT_LANTERN)        return blackbody(2200.0);
    if (id == MAT_SOUL_TORCH || id == MAT_SOUL_LANTERN || id == MAT_SOUL_FIRE || id == MAT_SOUL_CAMPFIRE)
                                  return vec3(0.12, 0.75, 1.0);
    if (id == MAT_LAVA)           return vec3(1.0, 0.32, 0.06);
    if (id == MAT_MAGMA)          return vec3(1.0, 0.28, 0.05);
    if (id == MAT_GLOWSTONE)      return blackbody(2600.0);
    if (id == MAT_SEA_LANTERN)    return vec3(0.70, 0.90, 1.0);
    if (id == MAT_REDSTONE_TORCH || id == MAT_REDSTONE_ORE || id == MAT_REDSTONE_WIRE) return vec3(1.0, 0.06, 0.02);
    if (id == MAT_REDSTONE_LAMP)  return blackbody(2700.0);
    if (id == MAT_JACK_O_LANTERN) return blackbody(2000.0);
    if (id == MAT_SHROOMLIGHT)    return vec3(1.0, 0.55, 0.25);
    if (id == MAT_FROG_OCHRE)     return vec3(1.0, 0.80, 0.40);
    if (id == MAT_FROG_VERDANT)   return vec3(0.55, 1.0, 0.45);
    if (id == MAT_FROG_PEARL)     return vec3(1.0, 0.65, 0.95);
    if (id == MAT_END_ROD)        return vec3(0.95, 0.88, 1.0);
    if (id == MAT_BEACON)         return vec3(0.75, 0.95, 1.0);
    if (id == MAT_CRYING_OBSIDIAN)return vec3(0.55, 0.12, 1.0);
    if (id == MAT_AMETHYST)       return vec3(0.75, 0.40, 1.0);
    if (id == MAT_GLOW_LICHEN || id == MAT_GLOW_BERRIES) return vec3(0.85, 1.0, 0.55);
    if (id == MAT_COPPER_BULB)    return blackbody(3000.0);
    if (id == MAT_RESPAWN_ANCHOR) return vec3(0.55, 0.20, 1.0);
    if (id == MAT_END_PORTAL || id == MAT_END_GATEWAY) return vec3(0.35, 0.55, 1.0);
    if (id == MAT_NETHER_PORTAL)  return vec3(0.60, 0.15, 1.0);
    if (id == MAT_CONDUIT)        return vec3(0.55, 0.85, 1.0);
    if (id == MAT_SCULK)          return vec3(0.15, 0.75, 0.90);
    if (id == MAT_SEA_PICKLE)     return vec3(0.65, 1.0, 0.65);
    if (id == MAT_ENCHANT_TABLE)  return vec3(0.65, 0.45, 1.0);
    if (id == MAT_FIREFLY_BUSH)   return vec3(1.0, 0.95, 0.45);
    if (id == MAT_CREAKING_HEART) return vec3(1.0, 0.45, 0.10);
    if (id == MAT_TRIAL_SPAWNER)  return vec3(1.0, 0.60, 0.25);
    if (id == MAT_BREWING_STAND)  return vec3(1.0, 0.85, 0.55);
    if (id == MAT_LIGHT_BLOCK)    return blackbody(3200.0);
    return blackbody(float(BLOCKLIGHT_TEMPERATURE));
}

// How a voxel affects propagating block light: x = extra attenuation in light levels
// (0 = transparent), y = 1 when it blocks completely; tint for stained glass is separate.
vec2 voxelOpacity(int id) {
    if (id == 0) return vec2(0.0, 0.0);
    if (isPlant(id) || id == MAT_LILY_PAD || id == MAT_PLANT_HANGING) return vec2(0.0, 0.0);
    if (id == MAT_LEAVES) return vec2(1.0, 0.0);
    if (id == MAT_WATER) return vec2(1.0, 0.0);
    if (id == MAT_GLASS || id == MAT_GLASS_PANE || id == MAT_STAINED_GLASS || id == MAT_ICE ||
        id == MAT_SLIME_HONEY || id == MAT_NETHER_PORTAL) return vec2(0.0, 0.0);
    if (id >= MAT_EMITTER_FIRST && id <= MAT_EMITTER_LAST) {
        // Full-cube emitters are solid; small ones (torches, lanterns, candles, rods...) are not.
        bool cube = id == MAT_GLOWSTONE || id == MAT_SEA_LANTERN || id == MAT_REDSTONE_LAMP ||
                    id == MAT_REDSTONE_ORE || id == MAT_JACK_O_LANTERN || id == MAT_SHROOMLIGHT ||
                    (id >= MAT_FROG_OCHRE && id <= MAT_FROG_PEARL) || id == MAT_CRYING_OBSIDIAN ||
                    id == MAT_COPPER_BULB || id == MAT_RESPAWN_ANCHOR || id == MAT_FURNACE_LIT || id == MAT_BEACON;
        return cube ? vec2(0.0, 1.0) : vec2(0.0, 0.0);
    }
    if (id == MAT_FIRE || id == MAT_SOUL_FIRE || id == MAT_CAMPFIRE || id == MAT_LAVA) return vec2(0.0, 0.0);
    if (id == MAT_CARPET || id == MAT_NO_PUDDLE || id == MAT_IRON_THIN) return vec2(0.0, 0.0);
    return vec2(0.0, 1.0);
}

#endif

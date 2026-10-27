#ifndef MERIDIAN_FALLBACK
#define MERIDIAN_FALLBACK

// Hardcoded materials for blocks whose resource pack provides no specular map. The result is
// written in LabPBR encoding (bytes / 255) so the deferred passes treat both paths alike.
//
// `albedo` is the sRGB texture colour, `lightLevel` the block's own emission 0..15
// (at_midBlock.w; 0 when unknown).

float emissiveMask(vec3 albedo, float threshold) {
    float l = maxOf(albedo);
    return saturate((l - threshold) / max(1.0 - threshold, 1e-3));
}

vec4 fallbackSpecular(int id, vec3 albedo, float lightLevel) {
    float smooth_ = 0.0;   // perceptual smoothness
    float f0 = 10.0;       // byte: 10/255 ~ 4 % (common dielectrics)
    float b = 0.0;         // porosity (0-64) or SSS (65-255) byte
    float emission = 0.0;  // 0..1
    float lum = luminance(albedo);

    if (id == MAT_IRON || id == MAT_IRON_THIN) { f0 = 230.0; smooth_ = 0.62 + 0.25 * lum; }
    else if (id == MAT_GOLD)                  { f0 = 231.0; smooth_ = 0.78 + 0.15 * lum; }
    else if (id >= MAT_COPPER && id <= MAT_COPPER_OXIDIZED) {
        // Bare copper is a conductor; verdigris (green-blue patina) is a rough dielectric.
        float bare = saturate((albedo.r - albedo.g) * 5.0 + 0.2);
        float age = float(id - MAT_COPPER) / 3.0;
        bare *= 1.0 - age * 0.85;
        f0 = bare > 0.5 ? 234.0 : 12.0;
        smooth_ = mix(0.25, 0.72, bare);
        b = bare > 0.5 ? 0.0 : 10.0;
    }
    else if (id == MAT_NETHERITE)   { f0 = 255.0; smooth_ = 0.55; }
    else if (id == MAT_DIAMOND_BLOCK) { f0 = 44.0; smooth_ = 0.82; }
    else if (id == MAT_EMERALD_BLOCK) { f0 = 15.0; smooth_ = 0.80; }
    else if (id == MAT_ICE)         { f0 = 5.0;  smooth_ = 0.96; }
    else if (id == MAT_PACKED_ICE)  { f0 = 5.0;  smooth_ = 0.72; }
    else if (id == MAT_GLASS || id == MAT_GLASS_PANE || id == MAT_STAINED_GLASS) { f0 = 10.0; smooth_ = 0.97; }
    else if (id == MAT_SLIME_HONEY) { f0 = 9.0;  smooth_ = 0.85; b = 65.0 + 190.0 * 0.6; }
    else if (id == MAT_POLISHED)    { f0 = 10.0; smooth_ = 0.45 + 0.2 * lum; }
    else if (id == MAT_OBSIDIAN || id == MAT_CRYING_OBSIDIAN) { f0 = 12.0; smooth_ = 0.82; }
    else if (id == MAT_PURPUR || id == MAT_PRISMARINE) { f0 = 10.0; smooth_ = 0.4; }
    else if (id == MAT_STONE || id == MAT_DEEPSLATE || id == MAT_BRICKS) { smooth_ = 0.18 + 0.15 * lum; b = 6.0; }
    else if (id == MAT_BASALT || id == MAT_BLACKSTONE) { smooth_ = 0.25; b = 4.0; }
    else if (id == MAT_SAND)        { smooth_ = 0.10; b = 64.0; }
    else if (id == MAT_GRAVEL)      { smooth_ = 0.10; b = 50.0; }
    else if (id == MAT_DIRT || id == MAT_GRASS_BLOCK || id == MAT_FARMLAND || id == MAT_PATH) { smooth_ = 0.08; b = 40.0; }
    else if (id == MAT_MUD)         { smooth_ = 0.35; b = 52.0; }
    else if (id == MAT_CLAY)        { smooth_ = 0.25; b = 30.0; }
    else if (id == MAT_TERRACOTTA)  { smooth_ = 0.22; b = 18.0; }
    else if (id == MAT_WOOL || id == MAT_CARPET) { smooth_ = 0.02; b = 38.0; }
    else if (id == MAT_WOOD)        { smooth_ = 0.22; b = 12.0; }
    else if (id == MAT_NETHERRACK)  { smooth_ = 0.15; b = 20.0; }
    else if (id == MAT_SOUL_SOIL)   { smooth_ = 0.05; b = 60.0; }
    else if (id == MAT_END_STONE)   { smooth_ = 0.2;  b = 14.0; }
    else if (id == MAT_NYLIUM)      { smooth_ = 0.2;  b = 65.0 + 190.0 * 0.25; }
    else if (id == MAT_WARPED_WART || id == MAT_NETHER_WART_BLOCK) { smooth_ = 0.3; b = 65.0 + 190.0 * 0.5; }
    else if (id == MAT_SNOW)        { smooth_ = 0.35; b = 65.0 + 190.0 * 0.65; }
    else if (id == MAT_LEAVES)      { smooth_ = 0.38; b = 65.0 + 190.0 * 0.85; }
    else if (isPlant(id))           { smooth_ = 0.30; b = 65.0 + 190.0 * 0.75; }
    else if (id == MAT_LILY_PAD)    { smooth_ = 0.45; b = 65.0 + 190.0 * 0.5; }

    // Emission. Whole-block emitters glow everywhere; others only on their bright texels.
    if (id == MAT_LAVA || id == MAT_GLOWSTONE || id == MAT_SEA_LANTERN || id == MAT_SHROOMLIGHT ||
        (id >= MAT_FROG_OCHRE && id <= MAT_FROG_PEARL) || id == MAT_FIRE || id == MAT_SOUL_FIRE ||
        id == MAT_END_PORTAL || id == MAT_END_GATEWAY || id == MAT_NETHER_PORTAL) {
        emission = 0.35 + 0.65 * emissiveMask(albedo, 0.25);
    } else if (id == MAT_MAGMA) {
        emission = emissiveMask(albedo, 0.45);
    } else if (id == MAT_REDSTONE_LAMP || id == MAT_COPPER_BULB) {
        emission = emissiveMask(albedo, 0.55);
    } else if (id == MAT_REDSTONE_TORCH || id == MAT_REDSTONE_ORE || id == MAT_REDSTONE_WIRE) {
        emission = saturate((albedo.r - max(albedo.g, albedo.b)) * 2.5) * step(0.4, albedo.r);
    } else if (id == MAT_SOUL_TORCH || id == MAT_SOUL_LANTERN || id == MAT_SOUL_CAMPFIRE) {
        emission = saturate((albedo.b + albedo.g * 0.5 - albedo.r) * 2.0) * emissiveMask(albedo, 0.45);
    } else if (id == MAT_CRYING_OBSIDIAN || id == MAT_AMETHYST || id == MAT_GLOW_LICHEN ||
               id == MAT_SCULK || id == MAT_CONDUIT || id == MAT_ENCHANT_TABLE) {
        emission = emissiveMask(albedo, 0.5) * 0.8;
    } else if (isEmitter(id) || lightLevel > 0.5) {
        emission = emissiveMask(albedo, 0.62);
    }
    emission *= lightLevel > 0.5 || isEmitter(id) ? 1.0 : 0.0;

    return vec4(smooth_, f0 / 255.0, b / 255.0, emission > 0.004 ? emission * 254.0 / 255.0 : 1.0);
}

#endif

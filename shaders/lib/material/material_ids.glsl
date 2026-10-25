#ifndef MATERIAL_IDS_GLSL
#define MATERIAL_IDS_GLSL
#include "/lib/core/color.glsl"
// Compact material classes. block.properties assigns block.(10000 + class); the class is stored
// in colortex1.a. Entity classes come from entity.properties (20000 + n).

#define MAT_NONE            0
#define MAT_WATER           1
#define MAT_LAVA            2
#define MAT_LEAVES          3
#define MAT_PLANT_SHORT     4
#define MAT_PLANT_TALL_LOW  5
#define MAT_PLANT_TALL_HIGH 6
#define MAT_VINE            7
#define MAT_GLASS           8
#define MAT_GLASS_STAINED   9
#define MAT_ICE             10
#define MAT_SLIME           11
#define MAT_METAL_IRON      12
#define MAT_METAL_GOLD      13
#define MAT_METAL_COPPER    14
#define MAT_POLISHED        15
#define MAT_SNOW            16
#define MAT_SAND            17
#define MAT_EMIT_TORCH      18
#define MAT_EMIT_LANTERN    19
#define MAT_EMIT_COOL       20
#define MAT_EMIT_SOUL       21
#define MAT_EMIT_REDSTONE   22
#define MAT_EMIT_PURPLE     23
#define MAT_EMIT_MAGMA      24
#define MAT_NETHER_PORTAL   25
#define MAT_END_PORTAL      26
#define MAT_WATER_PLANT     27
#define MAT_METAL_DARK      28
#define MAT_LILY_PAD        29
#define MAT_EMIT_WHITE      30
#define MAT_EMIT_GREEN      31
// Non-block classes written by entity / hand programs.
#define MAT_ENTITY          40
#define MAT_HAND            41
#define MAT_LOD             42
#define MAT_PARTICLE        43

#define ENTITY_BOAT      2       // shared with Halcyon's water sim (WS_BOAT_ENTITY_ID)
#define ENTITY_PLAYER    20002
#define ENTITY_LIGHTNING 20003

int materialFromBlockId(int id) {
    return (id >= 10000 && id < 10256) ? id - 10000 : MAT_NONE;
}

bool isFoliage(int m)  { return m >= MAT_LEAVES && m <= MAT_VINE || m == MAT_WATER_PLANT || m == MAT_LILY_PAD; }
bool isEmitter(int m)  { return m >= MAT_EMIT_TORCH && m <= MAT_EMIT_MAGMA || m == MAT_EMIT_WHITE || m == MAT_EMIT_GREEN || m == MAT_LAVA || m == MAT_NETHER_PORTAL; }
bool isMetalId(int m)  { return m == MAT_METAL_IRON || m == MAT_METAL_GOLD || m == MAT_METAL_COPPER || m == MAT_METAL_DARK; }

// Vanilla light level of each emitter class, used when Iris cannot provide the per-block
// emission attribute (BLOCK_EMISSION_ATTRIBUTE, Iris >= 1.7).
int emitterDefaultLevel(int m) {
    if (m == MAT_LAVA || m == MAT_EMIT_LANTERN || m == MAT_EMIT_COOL || m == MAT_EMIT_GREEN) return 15;
    if (m == MAT_EMIT_TORCH || m == MAT_EMIT_WHITE) return 14;
    if (m == MAT_NETHER_PORTAL) return 11;
    if (m == MAT_EMIT_SOUL) return 10;
    if (m == MAT_EMIT_REDSTONE) return 7;
    if (m == MAT_EMIT_PURPLE) return 5;
    if (m == MAT_EMIT_MAGMA) return 3;
    return 0;
}

// Linear-RGB tint of light emitted by each emitter class (unit luminance).
vec3 emitterColor(int m) {
    if (m == MAT_EMIT_TORCH)    return blackbody(1900.0);
    if (m == MAT_EMIT_LANTERN)  return blackbody(2500.0);
    if (m == MAT_EMIT_COOL)     return blackbody(7500.0);
    if (m == MAT_EMIT_SOUL)     return vec3(0.18, 0.95, 1.25);
    if (m == MAT_EMIT_REDSTONE) return vec3(3.6, 0.22, 0.05);
    if (m == MAT_EMIT_PURPLE)   return vec3(1.45, 0.55, 2.6);
    if (m == MAT_EMIT_MAGMA)    return blackbody(1500.0);
    if (m == MAT_LAVA)          return blackbody(1400.0);
    if (m == MAT_NETHER_PORTAL) return vec3(1.4, 0.4, 2.8);
    if (m == MAT_EMIT_GREEN)    return vec3(0.5, 1.25, 0.35);
    return blackbody(5200.0);
}

#endif

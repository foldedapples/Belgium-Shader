#ifndef MERIDIAN_IDS
#define MERIDIAN_IDS

// Material IDs assigned in block.properties (mc_Entity.x), entity.properties and item.properties.
// They are stored as 8 bits in the G-buffer, so every ID is < 256. Keep in sync with block.properties.

const int MAT_DEFAULT        = 0;   // unlisted solid block
const int MAT_UNLIT          = 1;   // drawn as-is (selection outline, debug)
const int MAT_EMISSIVE_FLAT  = 2;   // beacon beam, spider eyes, lightning: albedo is radiance
const int MAT_ENTITY         = 3;
const int MAT_HAND           = 4;
const int MAT_PARTICLE       = 5;

// Vegetation 10-19
const int MAT_LEAVES         = 10;
const int MAT_PLANT_GROUND   = 11;  // short grass, flowers, ferns, saplings: sway, base fixed
const int MAT_PLANT_TALL_LOW = 12;  // lower half of tall plants
const int MAT_PLANT_TALL_TOP = 13;  // upper half of tall plants
const int MAT_PLANT_HANGING  = 14;  // vines, hanging roots, weeping vines
const int MAT_CROP           = 15;
const int MAT_LILY_PAD       = 16;
const int MAT_GRASS_BLOCK    = 17;
const int MAT_NETHER_PLANT   = 18;
const int MAT_SUGAR_CANE     = 19;

// Translucent and fluids 20-29
const int MAT_WATER          = 20;
const int MAT_ICE            = 21;
const int MAT_GLASS          = 22;
const int MAT_STAINED_GLASS  = 23;
const int MAT_SLIME_HONEY    = 24;
const int MAT_NETHER_PORTAL  = 25;
const int MAT_GLASS_PANE     = 26;

// Hot 30-34
const int MAT_LAVA           = 30;
const int MAT_FIRE           = 31;
const int MAT_SOUL_FIRE      = 32;
const int MAT_MAGMA          = 33;
const int MAT_CAMPFIRE       = 34;

// Light emitters 40-79. Colour table in lib/lighting/emitters.glsl.
const int MAT_EMITTER_FIRST  = 40;
const int MAT_TORCH          = 40;
const int MAT_SOUL_TORCH     = 41;
const int MAT_LANTERN        = 42;
const int MAT_SOUL_LANTERN   = 43;
const int MAT_GLOWSTONE      = 44;
const int MAT_SEA_LANTERN    = 45;
const int MAT_REDSTONE_TORCH = 46;
const int MAT_REDSTONE_LAMP  = 47;
const int MAT_REDSTONE_ORE   = 48;
const int MAT_JACK_O_LANTERN = 49;
const int MAT_SHROOMLIGHT    = 50;
const int MAT_FROG_OCHRE     = 51;
const int MAT_FROG_VERDANT   = 52;
const int MAT_FROG_PEARL     = 53;
const int MAT_END_ROD        = 54;
const int MAT_BEACON         = 55;
const int MAT_SOUL_CAMPFIRE  = 56;
const int MAT_CANDLE         = 57;
const int MAT_CRYING_OBSIDIAN= 58;
const int MAT_AMETHYST       = 59;
const int MAT_GLOW_LICHEN    = 60;
const int MAT_GLOW_BERRIES   = 61;
const int MAT_COPPER_BULB    = 62;
const int MAT_RESPAWN_ANCHOR = 63;
const int MAT_END_PORTAL     = 64;
const int MAT_CONDUIT        = 65;
const int MAT_SCULK          = 66;
const int MAT_LIGHT_BLOCK    = 67;
const int MAT_FURNACE_LIT    = 68;
const int MAT_SEA_PICKLE     = 69;
const int MAT_ENCHANT_TABLE  = 70;
const int MAT_REDSTONE_WIRE  = 71;
const int MAT_FIREFLY_BUSH   = 72;
const int MAT_CREAKING_HEART = 73;
const int MAT_TRIAL_SPAWNER  = 74;
const int MAT_END_GATEWAY    = 75;
const int MAT_BREWING_STAND  = 76;
const int MAT_EMITTER_LAST   = 79;

// Metals 90-99 (used when the resource pack has no specular map)
const int MAT_IRON           = 90;
const int MAT_GOLD           = 91;
const int MAT_COPPER         = 92;
const int MAT_COPPER_EXPOSED = 93;
const int MAT_COPPER_WEATHERED = 94;
const int MAT_COPPER_OXIDIZED= 95;
const int MAT_NETHERITE      = 96;
const int MAT_IRON_THIN      = 97;  // bars, chains, rails
const int MAT_DIAMOND_BLOCK  = 98;
const int MAT_EMERALD_BLOCK  = 99;

// Surfaces 100-139
const int MAT_SAND           = 100;
const int MAT_SNOW           = 101;
const int MAT_WOOL           = 102;
const int MAT_WOOD           = 103;
const int MAT_STONE          = 104;
const int MAT_POLISHED       = 105; // polished stone, quartz, concrete, glazed terracotta
const int MAT_DIRT           = 106;
const int MAT_OBSIDIAN       = 107;
const int MAT_NETHERRACK     = 108;
const int MAT_BASALT         = 109;
const int MAT_BLACKSTONE     = 110;
const int MAT_SOUL_SOIL      = 111;
const int MAT_END_STONE      = 112;
const int MAT_NYLIUM         = 113;
const int MAT_TERRACOTTA     = 114;
const int MAT_MUD            = 115;
const int MAT_GRAVEL         = 116;
const int MAT_CLAY           = 117;
const int MAT_PACKED_ICE     = 118;
const int MAT_PURPUR         = 119;
const int MAT_DEEPSLATE      = 120;
const int MAT_ORE            = 129;   // overworld, deepslate and nether ores
const int MAT_BRICKS         = 121;
const int MAT_PRISMARINE     = 122;
const int MAT_WARPED_WART    = 123;
const int MAT_NETHER_WART_BLOCK = 124;
const int MAT_FARMLAND       = 125;
const int MAT_PATH           = 126;
const int MAT_CARPET         = 127; // thin, no puddles
const int MAT_NO_PUDDLE      = 128; // generic non-full block (slabs are fine; fences, rails...)

// Entities (entity.properties) are stored as MAT_ENTITY in the G-buffer; these drive shading.
const int ENT_LIGHTNING      = 1;
const int ENT_BOAT           = 2;
const int ENT_END_CRYSTAL    = 3;
const int ENT_ITEM_FRAME     = 4;
const int ENT_PLAYER         = 5;
const int ENT_GLOWING        = 6;   // glow squid, allay, blaze, magma cube, vex
const int ENT_DRAGON         = 7;

bool isPlant(int id)    { return id >= 10 && id <= 19 && id != MAT_GRASS_BLOCK; }
bool isFoliage(int id)  { return id >= 10 && id <= 19; }
bool isEmitter(int id)  { return (id >= MAT_EMITTER_FIRST && id <= MAT_EMITTER_LAST) || (id >= 30 && id <= 34); }
bool isMetalId(int id)  { return id >= 90 && id <= 97; }

#endif

#ifndef CORE_COMMON_GLSL
#define CORE_COMMON_GLSL
// Included first by every program implementation.
#include "/lib/core/settings.glsl"
#include "/lib/core/math.glsl"
#include "/lib/core/uniforms.glsl"
#include "/lib/core/transforms.glsl"
#include "/lib/core/encoding.glsl"
#include "/lib/core/color.glsl"
#include "/lib/core/noise.glsl"

// Debug view identifiers (keep in sync with lang/en_US.lang value.DEBUG_VIEW.*).
#define DBG_OFF            0
#define DBG_ALBEDO         1
#define DBG_NORMALS        2
#define DBG_ROUGHNESS      3
#define DBG_METAL          4
#define DBG_EMISSION       5
#define DBG_SHADOW         6
#define DBG_DIRECT         7
#define DBG_INDIRECT       8
#define DBG_REFLECTIONS    9
#define DBG_CLOUD_SCATTER  10
#define DBG_CLOUD_TRANS    11
#define DBG_WATER_HEIGHT   12
#define DBG_WATER_VELOCITY 13
#define DBG_TAA_REJECT     14
#define DBG_MOTION         15
#define DBG_EXPOSURE       16
#define DBG_LOD            17
#define DBG_DEPTH          18
#define DBG_AO             19
#define DBG_LIGHT_VOLUME   20
#define DBG_GI             21
#define DBG_LIGHTMAP       22

#endif

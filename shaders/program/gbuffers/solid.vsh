// Opaque geometry -> G-buffer. Variants (defined by the wrapper): GBUF_TERRAIN, GBUF_ENTITIES,
// GBUF_BLOCK, GBUF_HAND, GBUF_TEXTURED (opaque particles), GBUF_BASIC (lines), GBUF_EMISSIVE
// (beacon beam, spider eyes, lightning).

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/jitter.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/material/ids.glsl"

in vec2 mc_Entity;
in vec2 mc_midTexCoord;
in vec4 at_tangent;
in vec4 at_midBlock;

out vec2 vUv;
out vec2 vLightmap;
out vec4 vColor;
out vec3 vNormal;      // player space
out vec4 vTangent;     // player space, w = handedness
out vec3 vPlayerPos;
flat out int vId;
flat out vec4 vTile;   // atlas tile: xy min corner, zw size (for parallax wrapping)
flat out float vLightLevel;

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightmap = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;

    vec3 viewNormal = normalize(gl_NormalMatrix * gl_Normal);
    vec3 viewTangent = normalize(gl_NormalMatrix * (at_tangent.xyz + vec3(1e-6)));
    mat3 viewToPlayer = mat3(gbufferModelViewInverse);
    vNormal = viewToPlayer * viewNormal;
    vTangent = vec4(viewToPlayer * viewTangent, at_tangent.w < 0.0 ? -1.0 : 1.0);

    #ifdef GBUF_TERRAIN
    vId = int(mc_Entity.x + 0.5);
    if (mc_Entity.x < 0.0) vId = MAT_DEFAULT;
    vLightLevel = at_midBlock.w;
    #elif defined GBUF_ENTITIES
    vId = MAT_ENTITY;
    vLightLevel = entityId == ENT_GLOWING ? 8.0 : 0.0;
    #elif defined GBUF_HAND
    vId = MAT_HAND;
    vLightLevel = 0.0;
    #elif defined GBUF_TEXTURED
    vId = MAT_PARTICLE;
    vLightLevel = 0.0;
    #elif defined GBUF_BASIC
    vId = MAT_UNLIT;
    vLightLevel = 0.0;
    #elif defined GBUF_EMISSIVE
    vId = MAT_EMISSIVE_FLAT;
    vLightLevel = 15.0;
    #elif defined GBUF_BLOCK
    // Block entities: Iris applies block.properties to them through blockEntityId (the End portal
    // and gateway need it; everything else is a plain surface).
    vId = (blockEntityId == MAT_END_PORTAL || blockEntityId == MAT_END_GATEWAY) ? blockEntityId : MAT_DEFAULT;
    vLightLevel = 0.0;
    #else
    vId = MAT_DEFAULT;
    vLightLevel = 0.0;
    #endif

    vec2 halfTile = abs(vUv - mc_midTexCoord);
    vTile = vec4(mc_midTexCoord - halfTile, max(halfTile * 2.0, vec2(1e-6)));

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;

    #ifdef GBUF_HAND
    vPlayerPos = viewToPlayer * viewPos.xyz;
    gl_Position = applyJitter(gl_ProjectionMatrix * viewPos);
    #else
    vec3 playerPos = (gbufferModelViewInverse * viewPos).xyz;

    #ifdef GBUF_TERRAIN
    vec3 worldPos = playerPos + cameraPosition;
    float t = frameTimeCounter;
    // at_midBlock.y is the offset to the block centre in 1/64 block: negative above the centre.
    float upper = saturate(0.5 - at_midBlock.y / 64.0);
    if (vId == MAT_LEAVES) {
        playerPos += leafFlutter(worldPos, t);
    } else if (vId == MAT_PLANT_GROUND || vId == MAT_CROP || vId == MAT_NETHER_PLANT) {
        playerPos += plantSway(worldPos, upper, vId == MAT_CROP ? 1.6 : 1.0, t);
    } else if (vId == MAT_PLANT_TALL_LOW) {
        playerPos += plantSway(worldPos, upper * 0.5, 1.0, t);
    } else if (vId == MAT_PLANT_TALL_TOP) {
        playerPos += plantSway(worldPos - vec3(0.0, 1.0, 0.0), 0.5 + upper * 0.5, 1.0, t);
    } else if (vId == MAT_PLANT_HANGING) {
        playerPos += plantSway(worldPos, 1.0, 2.5, t);
    } else if (vId == MAT_LILY_PAD) {
        playerPos.y += 0.015 * sin(t * 1.3 + dot(worldPos.xz, vec2(0.7, 1.1)));
    }
    #endif

    vPlayerPos = playerPos;
    gl_Position = applyJitter(gl_ProjectionMatrix * (gbufferModelView * vec4(playerPos, 1.0)));
    #endif
}

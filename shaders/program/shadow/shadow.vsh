// Shadow pass, vertex stage. Variants: SHADOW_TERRAIN (also voxelises for coloured light),
// SHADOW_WATER, SHADOW_ENTITIES. The geometry stage places each triangle into the cascades.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/state.glsl"

#include "/lib/common/wind.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/lighting/shadow_proj.glsl"

in vec2 mc_Entity;
in vec4 at_midBlock;

out vec2 gUv;
out vec4 gColor;
out vec3 gLightPos;    // light-space position relative to the camera (rotation only)
out vec3 gPlayerPos;
out vec3 gNormal;      // player space
flat out int gId;
flat out vec4 gMidBlock;

void main() {
    gUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    gColor = gl_Color;
    #if defined SHADOW_TERRAIN || defined SHADOW_WATER
    gId = mc_Entity.x < 0.0 ? MAT_DEFAULT : int(mc_Entity.x + 0.5);
    gMidBlock = at_midBlock;
    #else
    gId = MAT_ENTITY;
    gMidBlock = vec4(0.0);
    #endif

    vec3 playerPos = (shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    #ifdef SHADOW_TERRAIN
    vec3 worldPos = playerPos + cameraPosition;
    float t = frameTimeCounter;
    float upper = saturate(0.5 - at_midBlock.y / 64.0);
    if (gId == MAT_LEAVES) playerPos += leafFlutter(worldPos, t);
    else if (gId == MAT_PLANT_GROUND || gId == MAT_CROP || gId == MAT_NETHER_PLANT) playerPos += plantSway(worldPos, upper, gId == MAT_CROP ? 1.6 : 1.0, t);
    else if (gId == MAT_PLANT_TALL_LOW) playerPos += plantSway(worldPos, upper * 0.5, 1.0, t);
    else if (gId == MAT_PLANT_TALL_TOP) playerPos += plantSway(worldPos - vec3(0.0, 1.0, 0.0), 0.5 + upper * 0.5, 1.0, t);
    else if (gId == MAT_PLANT_HANGING) playerPos += plantSway(worldPos, 1.0, 2.5, t);
    #endif

    gPlayerPos = playerPos;
    gNormal = mat3(shadowModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
    gLightPos = shadowLightRotation() * playerPos;
    gl_Position = vec4(0.0, 0.0, 0.0, 1.0);   // set per cascade in the geometry stage
}

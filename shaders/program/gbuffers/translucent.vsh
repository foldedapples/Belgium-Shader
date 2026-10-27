// Translucent terrain (water, glass, ice, slime, portals) -> translucent G-buffer (colortex4/5).
// Lighting, refraction and reflection happen in the composite translucency pass.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/jitter.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/water/waves.glsl"

in vec2 mc_Entity;
in vec2 mc_midTexCoord;
in vec4 at_tangent;
in vec4 at_midBlock;

out vec2 vUv;
out vec2 vLightmap;
out vec4 vColor;
out vec3 vNormal;
out vec4 vTangent;
out vec3 vPlayerPos;
flat out int vId;

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightmap = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;
    vId = mc_Entity.x < 0.0 ? MAT_GLASS : int(mc_Entity.x + 0.5);
    #ifdef GBUF_HAND_WATER
    vId = MAT_GLASS;
    #endif

    mat3 viewToPlayer = mat3(gbufferModelViewInverse);
    vNormal = viewToPlayer * normalize(gl_NormalMatrix * gl_Normal);
    vTangent = vec4(viewToPlayer * normalize(gl_NormalMatrix * (at_tangent.xyz + vec3(1e-6))), at_tangent.w < 0.0 ? -1.0 : 1.0);

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    #ifdef GBUF_HAND_WATER
    vPlayerPos = viewToPlayer * viewPos.xyz;
    gl_Position = applyJitter(gl_ProjectionMatrix * viewPos);
    #else
    vec3 playerPos = (gbufferModelViewInverse * viewPos).xyz;
    #ifdef WATER_WAVES
    // Large swells displace the top surface of still water downwards only, so the surface never
    // rises through blocks at the shore. Flowing water and side faces stay put.
    if (vId == MAT_WATER && vNormal.y > 0.99) {
        WaterParams wp = waterParamsAt(vNormal, saturate((vLightmap.y - 0.5 / 16.0) * 16.0 / 15.0));
        vec3 worldPos = playerPos + cameraPosition;
        float amp = waveSwellAmplitude(wp);
        float h = waveSwellHeight(worldPos.xz, frameTimeCounter, wp);
        playerPos.y += min(h - amp, 0.0) * 0.6;
    }
    #endif
    vPlayerPos = playerPos;
    gl_Position = applyJitter(gl_ProjectionMatrix * (gbufferModelView * vec4(playerPos, 1.0)));
    #endif
}

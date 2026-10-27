// Forward-lit geometry drawn after the deferred pass: translucent particles (smoke, splashes,
// bubbles), and with GBUF_WEATHER the rain/snow layer (into colortex13, composited after fog).

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/jitter.glsl"
#include "/lib/common/wind.glsl"

out vec2 vUv;
out vec2 vLightmap;
out vec4 vColor;
out vec3 vPlayerPos;
out vec3 vNormal;

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightmap = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;
    vec3 playerPos = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    vNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
    #ifdef GBUF_WEATHER
    // Lean the precipitation columns with the wind: displacement grows with height above the
    // player's feet, as for drops that fall at terminal speed through moving air.
    vec2 w = windDirection();
    float lean = (0.25 + 0.55 * windStrength()) * RAIN_WIND_LEAN;
    playerPos.xz += w * (playerPos.y + 1.6) * lean;
    #endif
    vPlayerPos = playerPos;
    gl_Position = applyJitter(gl_ProjectionMatrix * (gbufferModelView * vec4(playerPos, 1.0)));
}

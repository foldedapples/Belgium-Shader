// Distant Horizons terrain into the shadow map (dh_shadow, enabled by dhShadow.enabled when the
// LOD_SHADOWS option is on). Uses the same light matrix and distortion as shadow.glsl so DH
// mountains inside the shadow distance cast shadows that line up with vanilla shadows. Iris
// rewrites gl_Vertex / gl_ModelViewMatrix for DH and injects `int dhMaterialId`.
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/lighting/shadow_space.glsl"

#ifdef STAGE_VERTEX
flat out int vWater;
out float vHorizDist;

void main() {
    vec4 irisView = gl_ModelViewMatrix * gl_Vertex;
    vec3 scenePos = (shadowModelViewInverse * irisView).xyz;
    #ifdef DISTANT_HORIZONS
        vWater = dhMaterialId == DH_BLOCK_WATER ? 1 : 0;
    #else
        vWater = 0;
    #endif
    vHorizDist = length(scenePos.xz);
    vec3 clip = sceneToShadowClip(scenePos);
    clip.xy = distortShadowXY(clip.xy);
    gl_Position = vec4(clip, 1.0);
}
#endif

#ifdef STAGE_FRAGMENT
flat in int vWater;
in float vHorizDist;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outTint;
layout(location = 1) out vec4 outFlags;

void main() {
    // Vanilla chunks cast their own (detailed) shadows; coarse LOD casters there would offset
    // or double them. Same boundary as the start of the hand-off in dh_terrain.
    if (vHorizDist < far * 0.78) discard;
    outTint = vec4(1.0);
    outFlags = vec4(float(vWater), 0.0, 0.0, 1.0);
}
#endif

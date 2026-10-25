// Distant Horizons terrain -> the same G-buffer as vanilla terrain, flagged as LOD.
// Iris rewrites gl_Vertex / gl_Color / gl_Normal / gl_MultiTexCoord1 for DH and injects the
// global `int dhMaterialId` (DH_BLOCK_* values). DH meshes have no texture: the vertex colour
// is the block's average colour.
#include "/lib/core/common.glsl"
#include "/lib/core/taa_jitter.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/material/gbuffer.glsl"
#include "/lib/material/labpbr.glsl"

int materialFromDh(int id) {
    #ifdef DISTANT_HORIZONS
    if (id == DH_BLOCK_LEAVES) return MAT_LEAVES;
    if (id == DH_BLOCK_WATER) return MAT_WATER;
    if (id == DH_BLOCK_LAVA) return MAT_LAVA;
    if (id == DH_BLOCK_ILLUMINATED) return MAT_EMIT_LANTERN;
    if (id == DH_BLOCK_SNOW) return MAT_SNOW;
    if (id == DH_BLOCK_SAND) return MAT_SAND;
    if (id == DH_BLOCK_METAL) return MAT_METAL_IRON;
    if (id == DH_BLOCK_GRASS) return MAT_PLANT_SHORT;
    #endif
    return MAT_LOD;
}

#ifdef STAGE_VERTEX
out vec4 vColor;
out vec2 vLightmap;
out vec3 vScenePos;
out vec3 vNormal;
flat out int vMaterial;

void main() {
    vColor = gl_Color;
    vLightmap = saturate(gl_MultiTexCoord1.xy);
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vScenePos = viewToScene(viewPos.xyz);
    vNormal = safeNormalize(viewToSceneDir(gl_NormalMatrix * gl_Normal));
    #ifdef DISTANT_HORIZONS
        vMaterial = materialFromDh(dhMaterialId);
    #else
        vMaterial = MAT_LOD;
    #endif
    gl_Position = gl_ProjectionMatrix * viewPos;
    applyTaaJitter(gl_Position);
}
#endif

#ifdef STAGE_FRAGMENT
#include "/lib/core/blue_noise.glsl"

in vec4 vColor;
in vec2 vLightmap;
in vec3 vScenePos;
in vec3 vNormal;
flat in int vMaterial;

/* RENDERTARGETS: 1,2,3,4 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormals;
layout(location = 2) out vec4 outSpecular;
layout(location = 3) out vec4 outLight;

void main() {
    // Vanilla chunks own the near field; LODs fade in with a dithered band before `far`.
    float d = length(vScenePos.xz);
    float handoff = smoothstep(far * 0.78, far * 0.92, d);
    if (handoff < blueNoiseStatic(ivec2(gl_FragCoord.xy)).x) discard;

    GBufferData g;
    // DH stores one colour per block face; a subtle per-block variation keeps distant
    // forests and hills from reading as flat colour fields (no texture data exists).
    ivec3 block;
    sceneToWorldFract(vScenePos - vNormal * 0.01, block);
    float variation = 0.9 + 0.2 * hash13(block);
    g.albedo = srgbToLinear(vColor.rgb) * variation;
    g.material = vMaterial;
    g.flags = GB_FLAG_LOD | (isFoliage(vMaterial) ? GB_FLAG_SSS : 0);
    g.normal = vNormal;
    g.geoNormal = vNormal;
    g.specular = synthesizeSpecular(vMaterial, vColor.rgb, 0.0);
    g.lightmap = vLightmap;
    g.ao = 1.0;
    encodeGBuffer(g, outAlbedo, outNormals, outSpecular, outLight);
}
#endif

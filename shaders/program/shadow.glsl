// Shadow pass. Vertices are re-projected with our own light matrix (FrameState) and radial
// distortion instead of Iris' matrix; shadow.culling = false keeps Iris from culling with its
// own light direction. Outputs:
//   shadowcolor0: transmitted tint of translucent casters (white for opaque)
//   shadowcolor1: r = 1 for water casters
// The vertex stage also voxelises terrain for coloured block light (lib/lighting/floodfill.glsl).
// In the Nether there is no light to cast shadows, so the pass only voxelises.
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/lighting/shadow_space.glsl"
#include "/lib/lighting/floodfill.glsl"
#include "/lib/material/waving.glsl"

#ifdef STAGE_VERTEX
in vec4 mc_Entity;
in vec4 at_midBlock;
in vec2 mc_midTexCoord;

uniform sampler2D gtexture;
#ifdef COLORED_LIGHTING
layout(r32ui) uniform writeonly uimage3D voxelMap;
#endif

out vec2 vUv;
out vec4 vColor;
flat out int vMaterial;

void voxelise(vec3 scenePos) {
    #ifdef COLORED_LIGHTING
    bool terrain = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
                || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED || renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT;
    // One vertex per face is enough; the others would write the same voxel.
    if (!terrain || (gl_VertexID & 3) != 0) return;
    vec3 centre = scenePos + at_midBlock.xyz / 64.0;
    ivec3 block;
    sceneToWorldFract(centre, block);
    ivec3 v = block - lightVolumeOrigin(cameraPositionInt);
    if (any(lessThan(v, ivec3(0))) || any(greaterThanEqual(v, LV_SIZE))) return;

    #ifdef IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
        int level = int(at_midBlock.w + 0.5);
    #else
        int level = emitterDefaultLevel(vMaterial);   // Iris < 1.7: no per-block emission data
    #endif
    // A full cube has every vertex on its corners: |offset| = 0.5 block on all axes.
    bool fullCube = all(greaterThan(abs(at_midBlock.xyz), vec3(31.0)));
    uint flags = 0u;
    vec3 tint = vec3(1.0);
    if (vMaterial == MAT_GLASS || vMaterial == MAT_GLASS_STAINED || vMaterial == MAT_ICE || vMaterial == MAT_SLIME) {
        flags = LV_GLASS;
        tint = srgbToLinear(textureLod(gtexture, mc_midTexCoord, 4.0).rgb * gl_Color.rgb);
    } else if (vMaterial == MAT_LEAVES) {
        flags = LV_FOLIAGE;
    } else if (fullCube && vMaterial != MAT_WATER && level == 0) {
        flags = LV_OPAQUE;
    }
    if (flags == 0u && level == 0) return;   // air-like: nothing to store
    if (level > 0 && fullCube) flags |= LV_OPAQUE;
    imageStore(voxelMap, v, uvec4(packVoxel(flags, vMaterial, level, tint)));
    #endif
}

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    vMaterial = materialFromBlockId(int(mc_Entity.x + 0.5));

    // Iris' shadow model-view maps scene space to its light space; undo it to get scene space.
    vec4 irisView = gl_ModelViewMatrix * gl_Vertex;
    vec3 scenePos = (shadowModelViewInverse * irisView).xyz;
    voxelise(scenePos);
    // Same sway as the gbuffer pass so shadows stay attached to moving plants.
    vec2 uv0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 lm = saturate(((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy - 1.0 / 32.0) * (16.0 / 15.0));
    scenePos += waveOffset(cameraPosition + scenePos, vMaterial, uv0.y < mc_midTexCoord.y, lm.y);

    #ifdef DIM_NETHER
        gl_Position = vec4(-2.0, -2.0, -2.0, 1.0);   // voxelise only, rasterise nothing
    #else
        vec3 clip = sceneToShadowClip(scenePos);
        clip.xy = distortShadowXY(clip.xy);
        gl_Position = vec4(clip, 1.0);
    #endif
}
#endif

#ifdef STAGE_FRAGMENT
uniform sampler2D gtexture;

in vec2 vUv;
in vec4 vColor;
flat in int vMaterial;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outTint;
layout(location = 1) out vec4 outFlags;

void main() {
    if (vMaterial == MAT_WATER) {
        // Water attenuation and caustics are computed analytically from the water depth along
        // the light, so the caster itself is untinted.
        outTint = vec4(1.0);
        outFlags = vec4(1.0, 0.0, 0.0, 1.0);
        return;
    }
    vec4 base = texture(gtexture, vUv) * vColor;
    if (base.a < 0.1) discard;
    bool translucent = vMaterial == MAT_GLASS || vMaterial == MAT_GLASS_STAINED || vMaterial == MAT_ICE || vMaterial == MAT_SLIME;
    vec3 tint = vec3(1.0);
    if (translucent) {
        // Light through tinted glass: the glass colour weighted by its coverage.
        tint = mix(vec3(1.0), srgbToLinear(base.rgb), saturate(base.a * 1.25));
    }
    outTint = vec4(tint, 1.0);
    outFlags = vec4(0.0, 0.0, 0.0, 1.0);
}
#endif

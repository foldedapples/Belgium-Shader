// Opaque geometry -> G-buffer. Used by terrain, block entities, entities, hand, generic lit
// geometry, untextured basic geometry and the block-breaking overlay.
#include "/lib/core/common.glsl"
#include "/lib/core/taa_jitter.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/material/gbuffer.glsl"
#include "/lib/material/labpbr.glsl"
#include "/lib/material/waving.glsl"

// =====================================================================================
#ifdef STAGE_VERTEX
in vec4 mc_Entity;
in vec4 at_tangent;
in vec2 mc_midTexCoord;

out vec2 vUv;
out vec2 vLightmap;
out vec4 vColor;
out vec3 vScenePos;
out vec3 vNormal;
out vec4 vTangent;
out vec2 vMidUv;
out vec2 vTileHalf;
flat out int vMaterial;

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    // Every corner of a block face is half a tile away from the tile centre.
    vMidUv = mc_midTexCoord;
    vTileHalf = abs(vUv - mc_midTexCoord);
    // Vanilla lightmap coordinates span [1/32, 31/32]; remap to [0, 1].
    vec2 lm = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vLightmap = saturate((lm - 1.0 / 32.0) * (16.0 / 15.0));
    vColor = gl_Color;

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vScenePos = viewToScene(viewPos.xyz);

    vNormal = safeNormalize(viewToSceneDir(gl_NormalMatrix * gl_Normal));
    vTangent = vec4(safeNormalize(viewToSceneDir(gl_NormalMatrix * at_tangent.xyz), vec3(1.0, 0.0, 0.0)),
                    at_tangent.w < 0.0 ? -1.0 : 1.0);

    #if defined PROG_TERRAIN
        vMaterial = materialFromBlockId(int(mc_Entity.x + 0.5));
    #elif defined PROG_BLOCK
        vMaterial = blockEntityId == 10026 ? MAT_END_PORTAL : MAT_NONE;
    #elif defined PROG_ENTITY
        vMaterial = MAT_ENTITY;
    #elif defined PROG_HAND
        vMaterial = MAT_HAND;
    #else
        vMaterial = MAT_NONE;
    #endif

    #ifdef PROG_TERRAIN
        // Sprites are laid out top-down in the atlas: the top half has v below the tile centre.
        bool topVertex = vUv.y < mc_midTexCoord.y;
        vScenePos += waveOffset(cameraPosition + vScenePos, vMaterial, topVertex, vLightmap.y);
        viewPos = vec4(sceneToView(vScenePos), 1.0);
    #endif

    gl_Position = gl_ProjectionMatrix * viewPos;

    applyTaaJitter(gl_Position);
}
#endif

// =====================================================================================
#ifdef STAGE_FRAGMENT
#include "/lib/material/parallax.glsl"

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;

in vec2 vUv;
in vec2 vLightmap;
in vec4 vColor;
in vec3 vScenePos;
in vec3 vNormal;
in vec4 vTangent;
in vec2 vMidUv;
in vec2 vTileHalf;
flat in int vMaterial;

/* RENDERTARGETS: 1,2,3,4 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormals;
layout(location = 2) out vec4 outSpecular;
layout(location = 3) out vec4 outLight;

void main() {
    // Geometric normal: derivative-based face normal is exact for flat Minecraft faces and
    // immune to bad vertex normals on some modded models.
    vec3 faceN = safeNormalize(cross(dFdx(vScenePos), dFdy(vScenePos)), vNormal);
    if (dot(faceN, vNormal) < 0.0) faceN = -faceN;
    vec3 n = safeNormalize(vNormal, faceN);
    vec3 tan = safeNormalize(vTangent.xyz - n * dot(n, vTangent.xyz), basisFromNormal(n)[0]);
    vec3 bit = cross(n, tan) * vTangent.w;
    mat3 tbn = mat3(tan, bit, n);

    vec2 uv = vUv;
    vec2 gradX = dFdx(vUv), gradY = dFdy(vUv);
    #if defined PROG_TERRAIN && defined PARALLAX && defined MC_NORMAL_MAP && defined NORMAL_MAPPING
    {
        float dist = length(vScenePos);
        float fade = 1.0 - smoothstep(PARALLAX_DISTANCE * 0.7, PARALLAX_DISTANCE, dist);
        vec3 viewTs = normalize(transpose(tbn) * (-vScenePos / max(dist, 1e-4)));
        vec2 tileSize = max(vTileHalf * 2.0, vec2(1e-6));
        uv = parallaxUv(normals, vUv, vMidUv - vTileHalf, tileSize, viewTs, fade);
    }
    #endif

    #ifdef PROG_BASIC
        vec4 base = vColor;
    #else
        vec4 base = textureGrad(gtexture, uv, gradX, gradY);
        #ifdef PROG_TERRAIN
            // separateAo: vertex colour rgb is the biome tint, alpha is vanilla AO.
            base.rgb *= vColor.rgb;
        #else
            base *= vColor;
        #endif
    #endif
    if (base.a < 0.1) discard;

    #ifdef PROG_ENTITY
        base.rgb = mix(base.rgb, entityColor.rgb, entityColor.a);
    #endif

    GBufferData g;
    g.albedo = srgbToLinear(base.rgb);
    g.material = vMaterial;
    g.flags = 0;
    #ifdef PROG_HAND
        g.flags |= GB_FLAG_HAND;
    #endif
    #ifdef PROG_ENTITY
        g.flags |= GB_FLAG_ENTITY;
    #endif
    if (isFoliage(vMaterial)) g.flags |= GB_FLAG_SSS;

    #ifdef PROG_BASIC
        g.geoNormal = n;
    #else
        g.geoNormal = faceN;
    #endif

    float textureAo = 1.0;
    vec3 mapped = n;
    #if defined MC_NORMAL_MAP && defined NORMAL_MAPPING && !defined PROG_BASIC
    {
        vec4 nm = textureGrad(normals, uv, gradX, gradY);
        if (dot(nm.xy, nm.xy) == 0.0) nm = vec4(0.5, 0.5, 1.0, 1.0); // no normal data bound
        vec2 xy = nm.xy * 2.0 - 1.0;
        // A texel of (0.5, 0.5) or an absent map (Iris default) yields the flat normal.
        float z = sqrt(saturate(1.0 - dot(xy, xy)));
        mapped = safeNormalize(tbn * vec3(xy, z), n);
        textureAo = nm.b > 0.0 ? nm.b : 1.0;
    }
    #endif
    g.normal = mapped;

    vec4 spec = vec4(0.0);
    #if defined MC_SPECULAR_MAP && defined SPECULAR_MAPPING && !defined PROG_BASIC
        spec = textureGrad(specular, uv, gradX, gradY);
    #endif
    #ifdef VANILLA_METALS
        const float vanillaMetals = 1.0;
    #else
        const float vanillaMetals = 0.0;
    #endif
    if (!hasLabSpecular(spec)) spec = synthesizeSpecular(vMaterial, base.rgb, vanillaMetals);
    g.specular = spec;

    g.lightmap = vLightmap;
    #ifdef PROG_TERRAIN
        g.ao = vColor.a * textureAo;
    #else
        g.ao = textureAo;
    #endif

    encodeGBuffer(g, outAlbedo, outNormals, outSpecular, outLight);
}
#endif

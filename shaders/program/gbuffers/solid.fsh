#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/tangent.glsl"
#include "/lib/common/gbuffer.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/material/labpbr.glsl"
#include "/lib/material/fallback.glsl"
#if defined GBUF_BLOCK || (defined DISTANT_HORIZONS && defined GBUF_TERRAIN)
#include "/lib/common/noise.glsl"
#endif
#ifdef GBUF_BLOCK
#include "/lib/material/end_portal.glsl"
#endif

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;

in vec2 vUv;
in vec2 vLightmap;
in vec4 vColor;
in vec3 vNormal;
in vec4 vTangent;
in vec3 vPlayerPos;
flat in int vId;
flat in vec4 vTile;
flat in float vLightLevel;

/* RENDERTARGETS: 1,2,3 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outMaterial;

vec2 wrapTile(vec2 uv) {
    return vTile.xy + fract((uv - vTile.xy) / vTile.zw) * vTile.zw;
}

#if defined GBUF_TERRAIN && defined PARALLAX_ACTIVE
// Steep parallax with a linear search then one secant refinement, inside the atlas tile.
// LabPBR height: 1 = surface, 0 = POM_DEPTH below it.
vec2 parallaxUv(vec2 uv, vec3 viewTS, vec2 dx, vec2 dy, out float depthAtHit) {
    depthAtHit = 0.0;
    float lod = log2(max(dot(dx * vec2(atlasSize), dx * vec2(atlasSize)), dot(dy * vec2(atlasSize), dy * vec2(atlasSize)))) * 0.5;
    if (lod > 3.0) return uv;
    float fade = saturate(3.0 - lod);
    int steps = int(mix(8.0, float(POM_SAMPLES), saturate(1.0 - viewTS.z)));
    vec2 delta = viewTS.xy / max(viewTS.z, 0.15) * (POM_DEPTH * fade) * vTile.zw / float(steps);
    float layer = 1.0 / float(steps);
    float depth = 0.0;
    vec2 p = uv;
    float h = textureGrad(normals, wrapTile(p), dx, dy).a;
    float prevH = h, prevDepth = 0.0;
    for (int i = 0; i < 64; i++) {
        if (i >= steps || 1.0 - h <= depth) break;
        prevH = h; prevDepth = depth;
        p -= delta;
        depth += layer;
        h = textureGrad(normals, wrapTile(p), dx, dy).a;
    }
    // Secant refinement between the last two samples.
    float a = (1.0 - prevH) - prevDepth;
    float b = (1.0 - h) - depth;
    float t = a / max(a - b, 1e-4);
    float hitDepth = mix(prevDepth, depth, saturate(t));
    depthAtHit = hitDepth;
    return uv - delta * (hitDepth / layer);
}

float parallaxShadow(vec2 uv, float depthAtHit, vec3 lightTS, vec2 dx, vec2 dy) {
    #ifdef POM_SELF_SHADOW
    if (lightTS.z <= 0.0) return 0.0;
    if (depthAtHit <= 0.002) return 1.0;
    vec2 delta = lightTS.xy / max(lightTS.z, 0.2) * POM_DEPTH * vTile.zw / 12.0;
    float layer = depthAtHit / 12.0;
    float d = depthAtHit;
    vec2 p = uv;
    for (int i = 0; i < 12; i++) {
        p += delta;
        d -= layer;
        if (d <= 0.0) break;
        float h = textureGrad(normals, wrapTile(p), dx, dy).a;
        if (1.0 - h < d - 0.01) return 0.0;
    }
    #endif
    return 1.0;
}
#endif

void main() {
    vec2 uv = vUv;
    vec2 dx = dFdx(vUv), dy = dFdy(vUv);
    vec3 n = normalize(vNormal);
    if (!gl_FrontFacing) n = -n;
    #ifdef GBUF_TERRAIN
    #if defined DISTANT_HORIZONS && defined DH_CHUNK_FADE
    // Hand-over to Distant Horizons: over 0.82..0.98 of the render distance vanilla fragments are
    // discarded with rising probability (temporal dither, resolved by TAA), revealing the DH terrain
    // drawn underneath from 0.8 x far (dh_terrain / dh_water), so there is no hard line, hole or
    // doubled geometry. Shadows are unaffected (the shadow pass keeps all vanilla geometry).
    {
        float fade = smoothstep(far * 0.82, far * 0.98, length(vPlayerPos.xz));
        if (fade > 0.0 && interleavedGradient(gl_FragCoord.xy + float(frameCounter % 64) * 5.588238) < fade) discard;
    }
    #endif
    #endif

    #ifdef GBUF_BLOCK
    if (vId == MAT_END_PORTAL || vId == MAT_END_GATEWAY) {
        // Self-lit starfield (lib/material/end_portal.glsl), unaffected by light and shadow.
        outAlbedo = encodeGB1(endPortalColor(vPlayerPos, n), 1.0);
        outNormal = encodeGB2(n, n, normalizeLightmap(vLightmap));
        outMaterial = encodeGB3(vec4(0.0, 10.0 / 255.0, 0.0, 1.0), MAT_EMISSIVE_FLAT, FLAG_ENTITY | FLAG_NO_PUDDLE, 1.0);
        return;
    }
    #endif
    mat3 tbn = textureTangentFrame(n, vPlayerPos, vUv, vTangent);

    float pomShadow = 1.0;
    #if defined GBUF_TERRAIN && defined PARALLAX_ACTIVE
    vec3 viewDirP = normalize(-vPlayerPos);
    vec3 viewTS = viewDirP * tbn;
    if (viewTS.z > 0.0 && vId != MAT_WATER) {
        float depthAtHit;
        uv = wrapTile(parallaxUv(vUv, viewTS, dx, dy, depthAtHit));
        vec3 lightP = celestialDirection(shadowLightPosition);
        pomShadow = parallaxShadow(uv, depthAtHit, lightP * tbn, dx, dy);
    }
    #endif

    vec4 albedo = textureGrad(gtexture, uv, dx, dy);
    #if defined GBUF_BASIC || defined GBUF_EMISSIVE
    albedo = vec4(1.0);
    #ifdef GBUF_EMISSIVE
    albedo = textureGrad(gtexture, uv, dx, dy);
    if (renderStage == MC_RENDER_STAGE_NONE && albedo.a < 0.01) albedo = vec4(1.0);
    #endif
    #endif
    if (albedo.a < 0.1) discard;

    #ifdef GBUF_TERRAIN
    // With separateAo the vertex colour carries the biome tint in rgb and vanilla AO in alpha.
    vec3 tint = vColor.rgb;
    float vanillaAo = vColor.a;
    #else
    vec3 tint = vColor.rgb;
    float vanillaAo = 1.0;
    albedo.a *= vColor.a;
    #endif
    albedo.rgb *= tint;

    #ifdef GBUF_ENTITIES
    albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
    #endif

    vec4 normalTex = textureGrad(normals, uv, dx, dy);
    vec4 specTex = textureGrad(specular, uv, dx, dy);

    vec3 shadingNormal = n;
    float materialAo = 1.0;
    #ifdef NORMAL_MAPS_ACTIVE
    vec4 nt = decodeLabNormal(normalTex, NORMAL_MAP_STRENGTH);
    shadingNormal = normalize(tbn * nt.xyz);
    materialAo = nt.w;
    #endif

    vec4 spec;
    #if PBR_MODE == 1
    bool hasSpec = dot(specTex, specTex) > 1e-5;
    spec = specTex;
    #ifdef HARDCODED_MATERIALS
    if (!hasSpec) spec = fallbackSpecular(vId, albedo.rgb, vLightLevel);
    #else
    if (!hasSpec) spec = vec4(0.0, 10.0 / 255.0, 0.0, 1.0);
    #endif
    #else
    #ifdef HARDCODED_MATERIALS
    spec = fallbackSpecular(vId, albedo.rgb, vLightLevel);
    #else
    spec = vec4(0.0, 10.0 / 255.0, 0.0, 1.0);
    #endif
    #endif

    int flags = 0;
    #ifdef GBUF_HAND
    flags |= FLAG_HAND;
    #endif
    #if defined GBUF_ENTITIES || defined GBUF_BLOCK
    flags |= FLAG_ENTITY;
    #endif
    #if defined GBUF_BASIC
    flags |= FLAG_UNLIT;
    #endif
    if (isFoliage(vId) && vId != MAT_GRASS_BLOCK) flags |= FLAG_PLANT | FLAG_NO_PUDDLE;
    if (vId == MAT_CARPET || vId == MAT_NO_PUDDLE || vId == MAT_SNOW || vId == MAT_SAND ||
        vId == MAT_ICE || vId == MAT_PACKED_ICE || vId == MAT_GLASS || vId == MAT_LAVA ||
        vId == MAT_MAGMA || isEmitter(vId)) flags |= FLAG_NO_PUDDLE;
    #if defined GBUF_ENTITIES || defined GBUF_HAND || defined GBUF_TEXTURED || defined GBUF_BLOCK
    flags |= FLAG_NO_PUDDLE;
    #endif

    vec2 lm = normalizeLightmap(vLightmap);
    #ifdef GBUF_EMISSIVE
    spec.a = 254.0 / 255.0;
    #endif

    outAlbedo = encodeGB1(albedo.rgb, vanillaAo * materialAo);
    outNormal = encodeGB2(shadingNormal, n, lm);
    outMaterial = encodeGB3(spec, vId, flags, pomShadow);
}

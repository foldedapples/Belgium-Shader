#ifndef MERIDIAN_GBUFFER
#define MERIDIAN_GBUFFER

// G-buffer layout (see docs/ARCHITECTURE.md, "Buffers"):
//   colortex1 RGBA8   rgb albedo (sRGB, as sampled), a ambient occlusion (vanilla x material)
//   colortex2 RGBA16  xy octahedral shading normal, z packed octahedral geometry normal,
//                     w packed lightmap (block, sky)
//   colortex3 RGBA16  x packed (smoothness, F0) bytes, y packed (porosity/SSS, emission) bytes,
//                     z packed (material ID, flags), w packed (parallax shadow, spare)

const int FLAG_HAND      = 1;
const int FLAG_ENTITY    = 2;
const int FLAG_NO_PUDDLE = 4;
const int FLAG_PLANT     = 8;
const int FLAG_LOD       = 16;  // written by Distant Horizons / Voxy terrain
const int FLAG_UNLIT     = 32;

struct GBufferData {
    vec3  albedo;     // linear
    float ao;
    vec3  normal;     // player space, normal-mapped
    vec3  geoNormal;  // player space, geometric
    vec2  lightmap;   // x block light, y sky light, both 0..1
    vec4  spec;       // LabPBR specular bytes as 0..1
    int   id;
    int   flags;
    float parallaxShadow;
};

vec4 encodeGB1(vec3 albedoSrgb, float ao) { return vec4(albedoSrgb, ao); }

vec4 encodeGB2(vec3 normal, vec3 geoNormal, vec2 lightmap) {
    return vec4(octEncode(normal), pack2x8(octEncode(geoNormal)), pack2x8(lightmap));
}

vec4 encodeGB3(vec4 spec, int id, int flags, float parallaxShadow) {
    return vec4(pack2x8(spec.rg), pack2x8(spec.ba), pack2x8u(uint(id), uint(flags)), pack2x8(vec2(parallaxShadow, 0.0)));
}

GBufferData decodeGBuffer(vec4 g1, vec4 g2, vec4 g3) {
    GBufferData d;
    d.albedo = srgbToLinear(g1.rgb);
    d.ao = g1.a;
    d.normal = octDecode(g2.xy);
    d.geoNormal = octDecode(unpack2x8(g2.z));
    d.lightmap = unpack2x8(g2.w);
    d.spec = vec4(unpack2x8(g3.x), unpack2x8(g3.y));
    uvec2 idf = unpack2x8u(g3.z);
    d.id = int(idf.x);
    d.flags = int(idf.y);
    d.parallaxShadow = unpack2x8(g3.w).x;
    return d;
}

bool hasFlag(int flags, int f) { return (flags & f) != 0; }

// Vanilla lightmap coordinates arrive as (level + 0.5) / 16 after the lightmap texture matrix.
vec2 normalizeLightmap(vec2 lm) {
    return saturate((lm - 0.5 / 16.0) * (16.0 / 15.0));
}

#endif

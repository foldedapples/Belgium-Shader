#ifndef MATERIAL_GBUFFER_GLSL
#define MATERIAL_GBUFFER_GLSL
#include "/lib/core/encoding.glsl"
#include "/lib/core/color.glsl"

// G-buffer layout (ORIGINAL_ARCHITECTURE.md sec. 2.1 / sec. 3)
//   colortex1 RGBA8  : albedo sRGB-encoded rgb, material class (a)
//   colortex2 RGBA16 : mapped normal oct (rg), geometric normal oct (ba)   [scene space]
//   colortex3 RGBA8  : LabPBR specular bytes
//   colortex4 RGBA8  : block light, sky light, AO, flags

#define GB_FLAG_HAND     1
#define GB_FLAG_ENTITY   2
#define GB_FLAG_SSS      4
#define GB_FLAG_LOD      8
#define GB_FLAG_POM_SHADOW 16
#define GB_FLAG_NO_WET   64

struct GBufferData {
    vec3  albedo;      // linear
    int   material;
    vec3  normal;      // scene space, includes normal map
    vec3  geoNormal;   // scene space, face normal
    vec4  specular;    // LabPBR bytes 0..1
    vec2  lightmap;    // block, sky (0..1)
    float ao;
    int   flags;
};

void encodeGBuffer(GBufferData g, out vec4 t1, out vec4 t2, out vec4 t3, out vec4 t4) {
    t1 = vec4(linearToSrgb(saturate(g.albedo)), encodeByte(g.material));
    t2 = vec4(encodeUnitVector(g.normal), encodeUnitVector(g.geoNormal));
    t3 = saturate(g.specular);
    t4 = vec4(saturate(g.lightmap), saturate(g.ao), encodeByte(g.flags));
}

GBufferData decodeGBuffer(vec4 t1, vec4 t2, vec4 t3, vec4 t4) {
    GBufferData g;
    g.albedo = srgbToLinear(t1.rgb);
    g.material = decodeByte(t1.a);
    g.normal = decodeUnitVector(t2.rg);
    g.geoNormal = decodeUnitVector(t2.ba);
    g.specular = t3;
    g.lightmap = t4.rg;
    g.ao = t4.b;
    g.flags = decodeByte(t4.a);
    return g;
}

#endif

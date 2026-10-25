// Voxy LOD terrain -> the same G-buffer as vanilla terrain (voxy.json: opaqueDrawBuffers
// 1,2,3,4). Voxy calls voxy_emitFragment instead of main() and declares the uniforms and
// samplers listed in voxy.json itself, so only uniform-free modules are included here.
// Voxy provides no normal or derivatives: the normal comes from the face index, which in
// Voxy's quad encoding is (axis << 1) | positive with axis 0 = Y, 1 = Z, 2 = X.
#include "/lib/core/settings.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/material/gbuffer.glsl"
#include "/lib/material/labpbr.glsl"

layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormals;
layout(location = 2) out vec4 outSpecular;
layout(location = 3) out vec4 outLight;

vec3 voxyFaceNormal(uint face) {
    uint axis = face >> 1u;
    float s = (face & 1u) != 0u ? 1.0 : -1.0;
    return vec3(axis == 2u ? s : 0.0, axis == 0u ? s : 0.0, axis == 1u ? s : 0.0);
}

void voxy_emitFragment(VoxyFragmentParameters p) {
    // Vanilla chunks already drew this pixel: they take priority over the LOD.
    if (texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r < 1.0) discard;
    vec4 base = p.sampledColour * p.tinting;
    if (base.a < 0.1) discard;
    int material = materialFromBlockId(int(p.customId));
    vec3 n = voxyFaceNormal(p.face);

    GBufferData g;
    g.albedo = srgbToLinear(base.rgb);
    g.material = material;
    g.flags = GB_FLAG_LOD | (isFoliage(material) ? GB_FLAG_SSS : 0);
    g.normal = n;
    g.geoNormal = n;
    g.specular = synthesizeSpecular(material, base.rgb, 0.0);
    g.lightmap = saturate((p.lightMap - 1.0 / 32.0) * (16.0 / 15.0));
    // Voxy stores sky light 0 for a whole section when the section had no sky-light data at
    // ingest (VoxelIngestService), which vanilla omits for sections open to the sky. A visible
    // LOD face with sky light 0 is therefore almost always missing data, not a cave: treat it
    // as open sky, except downward faces (overhang undersides). Seen in game: black LODs at
    // night, dark shaded sides by day.
    if (g.lightmap.y < 0.5 / 15.0 && n.y > -0.5) g.lightmap.y = 1.0;
    g.ao = 1.0;
    encodeGBuffer(g, outAlbedo, outNormals, outSpecular, outLight);
}

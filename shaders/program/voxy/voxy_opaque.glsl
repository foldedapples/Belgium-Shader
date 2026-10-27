// Voxy LOD terrain -> Meridian G-buffer (colortex1/2/3), same encoding as gbuffers_terrain
// (lib/common/gbuffer.glsl). Voxy compiles this into its own #version 460 core fragment shader,
// so it cannot use #include: the few helpers it needs are restated here and must stay in sync
// with lib/common/encoding.glsl and lib/common/gbuffer.glsl.
//
// Voxy provides: sampled albedo, biome tint, the block.properties ID (customId), vanilla light
// (lightMap) and the face index (Minecraft Direction order: down, up, north, south, west, east).
// It provides no normal or specular maps, so materials use simple per-ID values.

layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outMaterial;

vec2 mrd_octEncode(vec3 n) {
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    vec2 p = n.xy;
    if (n.z < 0.0) p = (1.0 - abs(p.yx)) * vec2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
    return p * 0.5 + 0.5;
}
float mrd_pack2x8(vec2 v) {
    vec2 b = floor(clamp(v, 0.0, 1.0) * 255.0 + 0.5);
    return (b.x * 256.0 + b.y) / 65535.0;
}
float mrd_pack2x8u(uint hi, uint lo) { return float((hi << 8u) | lo) / 65535.0; }

vec3 mrd_faceNormal(uint face) {
    if (face == 0u) return vec3(0.0, -1.0, 0.0);
    if (face == 1u) return vec3(0.0, 1.0, 0.0);
    if (face == 2u) return vec3(0.0, 0.0, -1.0);
    if (face == 3u) return vec3(0.0, 0.0, 1.0);
    if (face == 4u) return vec3(-1.0, 0.0, 0.0);
    return vec3(1.0, 0.0, 0.0);
}

void voxy_emitFragment(VoxyFragmentParameters p) {
    vec4 albedo = p.sampledColour * p.tinting;
    vec3 n = mrd_faceNormal(p.face);
    // Light map arrives in vanilla lightmap UV form ((level + 0.5) / 16).
    vec2 lm = clamp((p.lightMap - 0.5 / 16.0) * (16.0 / 15.0), 0.0, 1.0);
    // Voxy stores sky light 0 for sections it ingested without sky-light data; at LOD distances
    // almost every visible face is open to the sky, so 0 is read as "unknown" and treated as open
    // (otherwise distant terrain turns black at night and its shaded sides go dark by day, as
    // observed in game with an earlier pack).
    if (lm.y < 0.5 / 15.0) lm.y = 1.0;
    uint id = p.customId & 255u;
    // Specular bytes in LabPBR encoding: smoothness, F0, porosity/SSS, emission (255 = none).
    vec4 spec = vec4(0.1, 10.0 / 255.0, 8.0 / 255.0, 1.0);
    if (id == 10u || (id >= 11u && id <= 19u)) spec = vec4(0.35, 10.0 / 255.0, (65.0 + 150.0) / 255.0, 1.0);
    if (id == 30u || id == 44u || id == 45u || id == 50u || (id >= 51u && id <= 53u)) spec.a = 0.8;
    // Metals: 255 = albedo as F0 (matches lib/material/fallback.glsl; 230-237 would tint twice).
    if (id == 90u) spec = vec4(0.7, 1.0, 0.0, 1.0);
    if (id == 91u) spec = vec4(0.8, 1.0, 0.0, 1.0);
    uint flags = 16u | 4u;   // FLAG_LOD | FLAG_NO_PUDDLE
    outAlbedo = vec4(albedo.rgb, 1.0);
    outNormal = vec4(mrd_octEncode(n), mrd_pack2x8(mrd_octEncode(n)), mrd_pack2x8(lm));
    outMaterial = vec4(mrd_pack2x8(spec.rg), mrd_pack2x8(spec.ba), mrd_pack2x8u(id, flags), mrd_pack2x8(vec2(1.0, 0.0)));
}

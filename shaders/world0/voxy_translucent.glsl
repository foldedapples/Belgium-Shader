// Voxy LOD translucents (water, glass) -> Meridian translucent G-buffer (colortex4/5), same
// encoding as gbuffers_water. Waves are not evaluated here (no time or position uniforms are
// requested); distant water is shaded with its flat surface normal.

layout(location = 0) out vec4 outSurface;
layout(location = 1) out vec4 outTint;

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

void voxy_emitFragment(VoxyFragmentParameters p) {
    vec3 n = p.face == 0u ? vec3(0.0, -1.0, 0.0) : p.face == 1u ? vec3(0.0, 1.0, 0.0) :
             p.face == 2u ? vec3(0.0, 0.0, -1.0) : p.face == 3u ? vec3(0.0, 0.0, 1.0) :
             p.face == 4u ? vec3(-1.0, 0.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec2 lm = clamp((p.lightMap - 0.5 / 16.0) * (16.0 / 15.0), 0.0, 1.0);
    if (lm.y < 0.5 / 15.0) lm.y = 1.0;   // unknown sky light (see voxy_opaque.glsl)
    uint id = p.customId & 255u;
    if (id == 0u) id = 22u;   // unlisted translucent: treat as glass
    vec4 c = p.sampledColour * p.tinting;
    outSurface = vec4(mrd_octEncode(n), mrd_pack2x8(lm), mrd_pack2x8u(id, 16u));
    outTint = id == 20u ? vec4(p.tinting.rgb, 1.0) : c;
}

// Voxy LOD translucents (voxy.json: translucentDrawBuffers 5,6).
// Water writes the water surface record (face normal; composite adds Fresnel, refraction and
// absorption). Other translucent LODs (distant stained glass, ice) get a lightmap-only
// estimate because Voxy patches cannot reach the pack's lighting state; documented in
// docs/COMPATIBILITY.md.
#include "/lib/core/settings.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/core/encoding.glsl"
#include "/lib/core/color.glsl"
#include "/lib/water/water_record.glsl"

layout(location = 0) out vec4 outTranslucent;
layout(location = 1) out vec4 outWater;

vec3 voxyFaceNormalT(uint face) {
    uint axis = face >> 1u;
    float s = (face & 1u) != 0u ? 1.0 : -1.0;
    return vec3(axis == 2u ? s : 0.0, axis == 0u ? s : 0.0, axis == 1u ? s : 0.0);
}

void voxy_emitFragment(VoxyFragmentParameters p) {
    if (texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r < 1.0) discard;
    int material = materialFromBlockId(int(p.customId));
    vec2 lm = clamp((p.lightMap - 1.0 / 32.0) * (16.0 / 15.0), 0.0, 1.0);
    if (material == MAT_WATER) {
        // Voxy cannot run the wave model (no pack state in its patch): composite adds waves.
        outWater = vec4(encodeUnitVector(voxyFaceNormalT(p.face)), packWaterLight(lm, voxyFaceNormalT(p.face).y > 0.5), 1.0);
        outTranslucent = vec4(0.0);
        return;
    }
    vec4 base = p.sampledColour * p.tinting;
    if (base.a < 0.02) discard;
    vec3 albedo = srgbToLinear(base.rgb);
    vec3 radiance = albedo * (0.35 * lm.y * lm.y + 0.4 * lm.x * lm.x * lm.x);
    outTranslucent = vec4(radiance, base.a);
    outWater = vec4(0.0);
}

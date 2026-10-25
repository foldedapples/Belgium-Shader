#ifndef DEBUG_DEBUG_GLSL
#define DEBUG_DEBUG_GLSL
// Debug visualisations evaluated in final. Views that need data only available in an earlier
// pass read colortex11, which that pass fills when DEBUG_VIEW selects it.
#include "/lib/core/common.glsl"
#include "/lib/material/gbuffer.glsl"
#include "/lib/material/labpbr.glsl"

vec3 debugHeat(float t) {
    t = saturate(t);
    return saturate(vec3(1.5 - abs(4.0 * t - 3.0), 1.5 - abs(4.0 * t - 2.0), 1.5 - abs(4.0 * t - 1.0)));
}

// Returns true and writes `display` (display-referred, 0..1) when a debug view is active.
bool debugGBufferView(int view, vec4 t1, vec4 t2, vec4 t3, vec4 t4, float depth, out vec3 display) {
    display = vec3(0.0);
    if (view == DBG_OFF) return false;
    GBufferData g = decodeGBuffer(t1, t2, t3, t4);
    Material m = decodeMaterial(g.albedo, g.specular, g.ao, g.material);
    bool sky = depth >= 1.0;
    if (view == DBG_ALBEDO)      display = sky ? vec3(0.0) : linearToSrgb(m.albedo);
    else if (view == DBG_NORMALS)   display = sky ? vec3(0.0) : g.normal * 0.5 + 0.5;
    else if (view == DBG_ROUGHNESS) display = sky ? vec3(0.0) : vec3(sqrt(m.roughness));
    else if (view == DBG_METAL)     display = sky ? vec3(0.0) : (m.metal ? vec3(1.0, 0.75, 0.2) * (0.5 + 0.5 * luminance(m.f0)) : vec3(m.f0.g * 4.0));
    else if (view == DBG_EMISSION)  display = sky ? vec3(0.0) : vec3(m.emission);
    else if (view == DBG_DEPTH)     display = vec3(sky ? 1.0 : pow(saturate(linearizeDepth(depth, near, far) / far), 0.5));
    else if (view == DBG_AO)        display = sky ? vec3(1.0) : vec3(m.ao);
    else return false;
    return true;
}

#endif

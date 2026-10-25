// deferred3 - SSGI denoise at half resolution (scale.deferred3) into colortex13 (persistent).
// 1. Spatial: 3x3 bilateral blur of this frame's trace, weighted by depth and normal
//    similarity (no light bleeds across silhouettes or around corners).
// 2. Temporal: reproject last frame's accumulation; reject it where the stored surface
//    distance disagrees (disocclusion) or the reprojection leaves the screen.
// colortex13: accumulated irradiance (rgb), view distance of the surface (a).
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/frame_state.glsl"
#include "/lib/material/gbuffer.glsl"

uniform sampler2D colortex2;
uniform sampler2D colortex12;
uniform sampler2D colortex13;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 13 */
layout(location = 0) out vec4 outHistory;

void main() {
    vec2 halfSize = vec2(viewWidth, viewHeight) * 0.5;
    vec2 uv = gl_FragCoord.xy / halfSize;
    outHistory = vec4(0.0);
    #ifdef SSGI
    if (any(greaterThan(uv, vec2(1.0)))) return;
    ivec2 hp = ivec2(gl_FragCoord.xy);
    ivec2 fullPx = ivec2(uv * vec2(viewWidth, viewHeight));
    float depth = texelFetch(depthtex0, fullPx, 0).r;
    if (depth >= 1.0) { outHistory = vec4(0.0, 0.0, 0.0, 6e4); return; }   // finite in fp16
    vec3 viewPos = screenToView(uv, depth);
    float dist = length(viewPos);
    vec3 n = decodeUnitVector(texelFetch(colortex2, fullPx, 0).ba);

    // Spatial bilateral filter.
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    vec3 lo = vec3(1e4), hi = vec3(-1e4);
    for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        ivec2 q = clamp(hp + ivec2(x, y), ivec2(0), ivec2(halfSize) - 1);
        ivec2 qf = ivec2((vec2(q) + 0.5) * 2.0);
        float qd = texelFetch(depthtex0, qf, 0).r;
        if (qd >= 1.0) continue;
        float qdist = length(screenToView((vec2(qf) + 0.5) / vec2(viewWidth, viewHeight), qd));
        vec3 qn = decodeUnitVector(texelFetch(colortex2, qf, 0).ba);
        float w = exp(-abs(qdist - dist) / max(dist * 0.03, 0.05)) * pow(saturate(dot(qn, n)), 8.0);
        w *= (x == 0 && y == 0) ? 2.0 : 1.0;
        vec3 c = texelFetch(colortex12, q, 0).rgb;
        sum += c * w;
        wsum += w;
        if (w > 0.05) { lo = min(lo, c); hi = max(hi, c); }
    }
    vec3 current = sum / max(wsum, 1e-4);

    // Temporal accumulation.
    vec3 scenePos = viewToScene(viewPos);
    vec2 prevUv = reprojectScene(scenePos).xy;
    float prevDistExpected = length(scenePos + (cameraPosition - previousCameraPosition));
    float blend = 1.0;
    vec3 history = vec3(0.0);
    if (all(greaterThan(prevUv, vec2(0.0))) && all(lessThan(prevUv, vec2(1.0))) && frameStateValid() && fsHeader.y > 2) {
        vec4 h = texture(colortex13, prevUv * 0.5);
        float rel = abs(h.a - prevDistExpected) / max(prevDistExpected, 0.5);
        if (rel < 0.08) {
            // Clamp to the neighbourhood range, widened because one ray per pixel is noisy:
            // limits ghosting when lighting changes without rejecting converged history.
            vec3 pad = (hi - lo) + abs(current) * 0.25 + 0.02;
            history = lo.x <= hi.x ? clamp(h.rgb, lo - pad, hi + pad) : h.rgb;
            blend = SSGI_TEMPORAL;
        }
    }
    vec3 result = mix(history, current, blend);
    if (!isFiniteVec(result)) result = vec3(0.0);
    outHistory = vec4(result, dist);   // signed (see deferred_ssgi)
    #endif
}
#endif

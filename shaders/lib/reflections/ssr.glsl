#ifndef REFLECTIONS_SSR_GLSL
#define REFLECTIONS_SSR_GLSL
#include "/lib/core/common.glsl"

// Screen-space reflection trace (ORIGINAL_ARCHITECTURE.md sec. 8.3 / 18).
// The ray is marched in screen space, where NDC depth varies linearly along a projected line,
// so interpolating (uv, ndc depth) is perspective-correct. Hits require the ray to be behind
// the depth buffer by less than a thickness that grows with the step length, then a binary
// search refines the hit. Rays leaving the screen or facing the camera fade out so the
// caller can blend toward its environment fallback.

struct SsrResult {
    bool  hit;
    vec2  uv;
    float confidence;   // 0..1: edge fade x facing fade
};

float ssrLinearDepth(float ndcDepth01) { return linearizeDepth(ndcDepth01, near, far); }

SsrResult traceScreenSpace(vec3 viewPos, vec3 viewDir, sampler2D depthTex, int steps, float jitter) {
    SsrResult r;
    r.hit = false; r.uv = vec2(0.0); r.confidence = 0.0;

    // Clip the ray before it passes the near plane.
    float rayLength = far * 1.2;
    if (viewDir.z > 0.0) rayLength = min(rayLength, (-near * 1.5 - viewPos.z) / viewDir.z);
    if (rayLength <= 0.0) return r;
    vec3 endPos = viewPos + viewDir * rayLength;

    vec3 s0 = viewToScreen(viewPos);
    vec3 s1 = viewToScreen(endPos);
    // Clip the screen-space segment to the viewport.
    vec2 d = s1.xy - s0.xy;
    float tMax = 1.0;
    if (d.x > 0.0) tMax = min(tMax, (1.0 - s0.x) / d.x); else if (d.x < 0.0) tMax = min(tMax, -s0.x / d.x);
    if (d.y > 0.0) tMax = min(tMax, (1.0 - s0.y) / d.y); else if (d.y < 0.0) tMax = min(tMax, -s0.y / d.y);
    s1 = mix(s0, s1, max(tMax, 0.0));

    vec3 delta = (s1 - s0) / float(steps);
    // Too-short rays (reflection pointing almost straight at the camera) are unreliable.
    float pixels = length((s1.xy - s0.xy) * vec2(viewWidth, viewHeight));
    if (pixels < 2.0) return r;

    vec3 p = s0 + delta * jitter;
    vec3 prev = s0;
    for (int i = 0; i < steps; i++) {
        p += delta;
        float sceneDepth = texture(depthTex, p.xy).r;
        if (p.z > sceneDepth && sceneDepth < 1.0) {
            float rayLin = ssrLinearDepth(p.z);
            float sceneLin = ssrLinearDepth(sceneDepth);
            float stepLin = abs(rayLin - ssrLinearDepth(prev.z)) + 0.05 * rayLin;
            if (rayLin - sceneLin < max(stepLin * 1.5, 0.25)) {
                // Binary refinement between prev and p.
                vec3 lo = prev, hi = p;
                for (int j = 0; j < 6; j++) {
                    vec3 mid = 0.5 * (lo + hi);
                    if (mid.z > texture(depthTex, mid.xy).r) hi = mid; else lo = mid;
                }
                r.hit = true;
                r.uv = hi.xy;
                vec2 edge = smoothstep(vec2(0.0), vec2(0.06), hi.xy) * (1.0 - smoothstep(vec2(0.94), vec2(1.0), hi.xy));
                float facing = 1.0 - smoothstep(0.55, 0.95, viewDir.z);
                r.confidence = edge.x * edge.y * facing;
                return r;
            }
        }
        prev = p;
    }
    return r;
}

#endif

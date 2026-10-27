#ifndef MERIDIAN_SSR
#define MERIDIAN_SSR

// Screen-space reflections: march the reflected ray in screen space (perspective-correct depth),
// accept a hit when the ray passes behind the depth buffer by less than a thickness that grows
// with distance, refine with a binary search, and fade near screen edges and for rays towards the
// camera. Only what is on screen can be reflected; misses fall back to the sky (with sky-light
// occlusion), never to black. Requires transform.glsl.

struct SSRHit {
    vec2 uv;
    float confidence;   // 0 = no hit (use fallback)
    float dist;         // view-space length to the hit
};

SSRHit traceSSR(vec3 viewPos, vec3 viewDir, sampler2D depthTex, float noise, int steps) {
    SSRHit h;
    h.uv = vec2(0.0);
    h.confidence = 0.0;
    h.dist = 0.0;
    // Rays pointing at the camera cannot hit anything visible.
    if (viewDir.z > 0.0 && viewPos.z + viewDir.z * 2.0 > -near) return h;

    // Clip the ray to the near plane and a maximum length.
    float maxLen = 384.0;
    if (viewDir.z > 0.0) maxLen = min(maxLen, (-near * 1.5 - viewPos.z) / viewDir.z);
    vec3 endView = viewPos + viewDir * maxLen;
    vec3 s0 = viewToScreen(viewPos, gbufferProjection);
    vec3 s1 = viewToScreen(endView, gbufferProjection);
    // Clip the screen-space segment to the viewport.
    vec2 d = s1.xy - s0.xy;
    float tMax = 1.0;
    if (d.x > 0.0) tMax = min(tMax, (1.0 - s0.x) / d.x); else if (d.x < 0.0) tMax = min(tMax, -s0.x / d.x);
    if (d.y > 0.0) tMax = min(tMax, (1.0 - s0.y) / d.y); else if (d.y < 0.0) tMax = min(tMax, -s0.y / d.y);
    tMax = max(tMax, 0.0);

    // Interpolate 1/z for perspective-correct depth along the screen segment.
    float invZ0 = 1.0 / viewPos.z, invZ1 = 1.0 / endView.z;
    float prevT = 0.0;
    float stepScale = 1.0 / float(steps);
    for (int i = 1; i <= 64; i++) {
        if (i > steps) break;
        // Steps grow quadratically: fine near the surface, coarse far away.
        float t = tMax * sq((float(i) - 1.0 + noise) * stepScale);
        vec2 uv = s0.xy + d * t;
        float rayZ = 1.0 / mix(invZ0, invZ1, t);       // view-space z (negative)
        float sceneD = texture(depthTex, uv).r;
        if (sceneD >= 1.0) { prevT = t; continue; }
        float sceneZ = screenToView(uv, sceneD, gbufferProjectionInverse).z;
        float behind = sceneZ - rayZ;                   // > 0 when the ray is behind the surface
        float thickness = 0.25 + abs(rayZ) * 0.04;
        if (behind > 0.0 && behind < thickness) {
            // Binary refinement between prevT and t.
            float a = prevT, b = t;
            for (int k = 0; k < 5; k++) {
                float m = 0.5 * (a + b);
                vec2 muv = s0.xy + d * m;
                float mz = 1.0 / mix(invZ0, invZ1, m);
                float sz = screenToView(muv, texture(depthTex, muv).r, gbufferProjectionInverse).z;
                if (sz - mz > 0.0) b = m; else a = m;
            }
            h.uv = s0.xy + d * b;
            vec2 edge = smoothstep(0.0, 0.08, h.uv) * smoothstep(0.0, 0.08, 1.0 - h.uv);
            h.confidence = edge.x * edge.y * saturate(1.0 - viewDir.z * 2.0);
            h.dist = length(screenToView(h.uv, texture(depthTex, h.uv).r, gbufferProjectionInverse) - viewPos);
            return h;
        }
        prevT = t;
    }
    return h;
}

#endif

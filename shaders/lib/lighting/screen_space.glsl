#ifndef LIGHTING_SCREEN_SPACE_GLSL
#define LIGHTING_SCREEN_SPACE_GLSL
#include "/lib/core/common.glsl"

// Screen-space ambient occlusion and contact shadows, traced against the depth buffer in view
// space. Both are short-range corrections to the shadow map and the sky-light lightmap, which
// cannot resolve small creases or the gap under small objects.

// Cosine-weighted hemisphere AO: occluders are depth-buffer points closer to the camera than
// the sample and within the sample radius (range check stops distant geometry from darkening).
float screenSpaceAO(vec3 viewPos, vec3 viewNormal, sampler2D depthTex, vec2 noise) {
    const int SAMPLES = SSAO_SAMPLES;
    const float RADIUS = 0.65;
    mat3 basis = basisFromNormal(viewNormal);
    float occlusion = 0.0;
    for (int i = 0; i < SAMPLES; i++) {
        float fi = (float(i) + noise.x) / float(SAMPLES);
        float phi = float(i) * GOLDEN_ANGLE + noise.y * TAU;
        float cosT = sqrt(1.0 - fi), sinT = sqrt(fi);
        vec3 h = basis * vec3(cos(phi) * sinT, sin(phi) * sinT, cosT);
        float scale = mix(0.15, 1.0, sq(fract(fi * 7.31 + noise.x)));
        vec3 p = viewPos + h * RADIUS * scale;
        vec3 s = viewToScreen(p);
        if (any(lessThan(s.xy, vec2(0.0))) || any(greaterThan(s.xy, vec2(1.0)))) continue;
        float d = texture(depthTex, s.xy).r;
        if (d >= 1.0) continue;
        float sceneZ = screenToView(s.xy, d).z;
        float diff = sceneZ - p.z;                        // > 0: depth buffer is in front
        float range = smoothstep(0.0, 1.0, RADIUS / max(abs(viewPos.z - sceneZ), 1e-3));
        occlusion += step(0.02, diff) * range;
    }
    return 1.0 - occlusion / float(SAMPLES) * SSAO_STRENGTH;
}

// Short march toward the light: catches contact shadows below the shadow map's resolution.
float contactShadow(vec3 viewPos, vec3 viewLightDir, sampler2D depthTex, float noise) {
    const int STEPS = 10;
    const float LENGTH = 0.55;
    float dt = LENGTH / float(STEPS);
    vec3 p = viewPos + viewLightDir * dt * noise;
    for (int i = 0; i < STEPS; i++) {
        p += viewLightDir * dt;
        vec3 s = viewToScreen(p);
        if (any(lessThan(s.xy, vec2(0.0))) || any(greaterThan(s.xy, vec2(1.0))) || s.z >= 1.0) return 1.0;
        float d = texture(depthTex, s.xy).r;
        float sceneZ = screenToView(s.xy, d).z;
        float diff = sceneZ - p.z;
        if (diff > 0.01 && diff < 0.25) return 0.0;
    }
    return 1.0;
}

#endif

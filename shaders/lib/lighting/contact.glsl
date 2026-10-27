#ifndef MERIDIAN_CONTACT
#define MERIDIAN_CONTACT

// Contact shadows: a short screen-space ray from the surface towards the light, catching the
// fine occlusion (grass on blocks, items on tables, small gaps) that the shadow map is too coarse
// to resolve. Requires transform.glsl and depthtex1.

float contactShadow(vec3 viewPos, vec3 viewLight, float noise) {
    #ifdef CONTACT_SHADOWS
    const int STEPS = 8;
    float len = 0.35 + 0.004 * -viewPos.z;            // blocks; grows slightly with distance
    vec3 stepV = viewLight * (len / float(STEPS));
    vec3 p = viewPos + stepV * noise;
    for (int i = 0; i < STEPS; i++) {
        p += stepV;
        vec3 s = viewToScreen(p, gbufferProjection);
        if (any(lessThan(s.xy, vec2(0.0))) || any(greaterThan(s.xy, vec2(1.0)))) break;
        float d = texture(depthtex1, s.xy).r;
        if (d >= 1.0) continue;
        float sceneZ = screenToView(s.xy, d, gbufferProjectionInverse).z;
        float behind = sceneZ - p.z;                  // > 0: the ray is behind the depth buffer
        if (behind > 0.01 && behind < 0.25 + 0.01 * -p.z) {
            // Fade with distance along the ray so the shadow softens away from the contact.
            return mix(0.0, 1.0, float(i) / float(STEPS) * 0.6);
        }
    }
    #endif
    return 1.0;
}

#endif

#ifndef MERIDIAN_TRANSFORM
#define MERIDIAN_TRANSFORM

#include "/lib/common/jitter.glsl"

vec3 projectAndDivide(mat4 m, vec3 p) {
    vec4 h = m * vec4(p, 1.0);
    return h.xyz / h.w;
}

vec3 screenToView(vec2 uv, float depth, mat4 projInv) {
    return projectAndDivide(projInv, vec3(uv, depth) * 2.0 - 1.0);
}

vec3 viewToScreen(vec3 viewPos, mat4 proj) {
    return projectAndDivide(proj, viewPos) * 0.5 + 0.5;
}

// Every geometry program draws with the TAA jitter added in clip space (jitter.glsl), but the
// Iris matrices are unjittered. A pixel of this frame's depth buffer therefore shows the point
// whose unjittered screen position is uv - jitterUv(). Reconstructing without removing it moves
// every reconstructed position by up to half a pixel per frame (0.1 block at 100 blocks), which
// made shadows, fog and reprojection swim with the camera.
vec2 jitterUv() {
    #ifdef TAA
    return taaJitterPixels(frameCounter) / vec2(viewWidth, viewHeight);
    #else
    return vec2(0.0);
    #endif
}

// This frame's (jittered) vanilla depth buffers <-> view space.
vec3 sceneToView(vec2 uv, float depth) {
    return screenToView(uv - jitterUv(), depth, gbufferProjectionInverse);
}
vec3 viewToScene(vec3 viewPos) {
    vec3 s = viewToScreen(viewPos, gbufferProjection);
    s.xy += jitterUv();
    return s;
}

// Hand geometry is drawn with its depth scaled by MC_HAND_DEPTH in NDC.
vec3 screenToViewHand(vec2 uv, float depth) {
    vec3 ndc = vec3(uv - jitterUv(), depth) * 2.0 - 1.0;
    ndc.z /= MC_HAND_DEPTH;
    return projectAndDivide(gbufferProjectionInverse, ndc);
}

vec3 viewToPlayer(vec3 v) { return mat3(gbufferModelViewInverse) * v + gbufferModelViewInverse[3].xyz; }
vec3 playerToView(vec3 p) { return mat3(gbufferModelView) * p + gbufferModelView[3].xyz; }

float linearizeDepth(float d, float n, float f) {
    float z = d * 2.0 - 1.0;
    return 2.0 * n * f / (f + n - z * (f - n));
}

// Angular size of one pixel at the screen centre (radians), from the projection matrix.
float pixelAngularSize() {
    return 2.0 / (gbufferProjection[1][1] * viewHeight);
}

#endif

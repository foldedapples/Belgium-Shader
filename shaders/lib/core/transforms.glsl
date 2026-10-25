#ifndef CORE_TRANSFORMS_GLSL
#define CORE_TRANSFORMS_GLSL
#include "/lib/core/math.glsl"
#include "/lib/core/uniforms.glsl"

// Space conversions (see ORIGINAL_ARCHITECTURE.md sec. 0). "screen" = [0,1]^2 uv + [0,1] depth.

vec3 projectAndDivide(mat4 m, vec3 p) {
    vec4 h = m * vec4(p, 1.0);
    return h.xyz / (abs(h.w) > EPSILON ? h.w : EPSILON);
}

vec3 screenToView(vec2 uv, float depth, mat4 projInv) {
    return projectAndDivide(projInv, vec3(uv, depth) * 2.0 - 1.0);
}
vec3 screenToView(vec2 uv, float depth) { return screenToView(uv, depth, gbufferProjectionInverse); }

vec3 viewToScreen(vec3 viewPos, mat4 proj) {
    return projectAndDivide(proj, viewPos) * 0.5 + 0.5;
}
vec3 viewToScreen(vec3 viewPos) { return viewToScreen(viewPos, gbufferProjection); }

vec3 viewToScene(vec3 viewPos)   { return mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz; }
vec3 sceneToView(vec3 scenePos)  { return mat3(gbufferModelView) * scenePos + gbufferModelView[3].xyz; }
vec3 viewToSceneDir(vec3 d)      { return mat3(gbufferModelViewInverse) * d; }
vec3 sceneToViewDir(vec3 d)      { return mat3(gbufferModelView) * d; }

// Linear view-space distance from a [0,1] depth value for the vanilla projection.
float linearizeDepth(float depth, float n, float f) {
    float z = depth * 2.0 - 1.0;
    return 2.0 * n * f / max(f + n - z * (f - n), EPSILON);
}

// Previous-frame screen position of a scene-space point that is static in the world.
vec3 reprojectScene(vec3 scenePos) {
    vec3 prevScene = scenePos + (cameraPosition - previousCameraPosition);
    vec3 prevView = mat3(gbufferPreviousModelView) * prevScene + gbufferPreviousModelView[3].xyz;
    return viewToScreen(prevView, gbufferPreviousProjection);
}

// Camera-relative world position split into integer block + fraction, so noise and grids
// stay precise far from the origin.
vec3 sceneToWorldFract(vec3 scenePos, out ivec3 blockPos) {
    vec3 p = cameraPositionFract + scenePos;
    vec3 fl = floor(p);
    blockPos = cameraPositionInt + ivec3(fl);
    return p - fl;
}

vec2 screenSize() { return vec2(viewWidth, viewHeight); }
vec2 pixelSize()  { return 1.0 / vec2(viewWidth, viewHeight); }

#endif

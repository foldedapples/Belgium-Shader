#ifndef MERIDIAN_TRANSFORM
#define MERIDIAN_TRANSFORM

vec3 projectAndDivide(mat4 m, vec3 p) {
    vec4 h = m * vec4(p, 1.0);
    return h.xyz / h.w;
}

vec3 screenToView(vec2 uv, float depth, mat4 projInv) {
    return projectAndDivide(projInv, vec3(uv, depth) * 2.0 - 1.0);
}

// Hand geometry is drawn with its depth scaled by MC_HAND_DEPTH in NDC.
vec3 screenToViewHand(vec2 uv, float depth) {
    vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
    ndc.z /= MC_HAND_DEPTH;
    return projectAndDivide(gbufferProjectionInverse, ndc);
}

vec3 viewToScreen(vec3 viewPos, mat4 proj) {
    return projectAndDivide(proj, viewPos) * 0.5 + 0.5;
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

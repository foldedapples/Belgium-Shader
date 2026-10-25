#ifndef LIGHTING_SHADOW_SPACE_GLSL
#define LIGHTING_SHADOW_SPACE_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"

// Our own light-space transform (ORIGINAL_ARCHITECTURE.md sec. 4). The orthographic light view is
// built in begin.csh and stored in FrameState; Iris' shadowModelView is used only to undo the
// transform Iris applies to shadow-pass vertices.

const float SHADOW_DEPTH_HALF = 512.0; // blocks either side of the camera along the light

// Hyperbolic radial distortion p' = p(1+k)/(|p|+k): resolution near the camera is boosted by
// (1+k)/k, the edge of the map keeps unit scale.
vec2 distortShadowXY(vec2 p) {
    const float k = SHADOW_DISTORTION;
    return p * ((1.0 + k) / (length(p) + k));
}

// d|p'|/d|p| - the smaller (radial) of the two stretch factors, so texel sizes derived from it
// are conservative.
float shadowRadialStretch(float r) {
    const float k = SHADOW_DISTORTION;
    return (1.0 + k) * k / sq(r + k);
}

// World size of one shadow texel at undistorted clip position p.
float shadowTexelWorld(vec2 clipXY) {
    return (2.0 * shadowDistance / float(shadowMapResolution)) / shadowRadialStretch(length(clipXY));
}

// Centre texel size used for snapping the light view.
float shadowCentreTexelWorld() {
    const float k = SHADOW_DISTORTION;
    return (2.0 * shadowDistance / float(shadowMapResolution)) * k / (1.0 + k);
}

vec3 sceneToShadowClip(vec3 scenePos) {
    vec4 lv = fsShadowView * vec4(scenePos, 1.0);
    return (fsShadowProj * lv).xyz;
}
// Undistorted clip -> distorted texture coordinates + depth in [0,1].
vec3 shadowClipToTexture(vec3 clip) {
    return vec3(distortShadowXY(clip.xy), clip.z) * 0.5 + 0.5;
}

// Builds the light view and projection. `cam` is the camera's world position, `anchor` the
// world position the map is centred on (begin.csh keeps it within SHADOW_ANCHOR_RADIUS of the
// camera). The radial distortion is centred on the anchor, so between re-anchorings every static
// point keeps the same distorted texel and its shadow does not move. Centring the distortion on
// the camera itself (as before) moved every point through the warp as the player walked, so
// shadow edges crawled continuously (up to a texel per frame; ~10 cm at 40 m on HIGH).
void buildShadowMatrices(vec3 lightDir, vec3 axis, vec3 cam, vec3 anchor, out mat4 view, out mat4 proj) {
    vec3 L = safeNormalize(lightDir);
    vec3 right = cross(axis, L);
    if (dot(right, right) < 1e-6) right = cross(vec3(0.0, 0.0, 1.0), L);
    if (dot(right, right) < 1e-6) right = vec3(1.0, 0.0, 0.0);
    right = normalize(right);
    vec3 up = cross(L, right);

    // Anchor the texel grid to the world: translation = R*cam - snap(R*anchor). Depth stays
    // centred on the camera (the +-512 block range is not distorted).
    float texel = shadowCentreTexelWorld();
    vec2 camL = vec2(dot(right, cam), dot(up, cam));
    vec2 anchorL = vec2(dot(right, anchor), dot(up, anchor));
    vec2 snapped = floor(anchorL / texel) * texel;
    vec3 t = vec3(camL - snapped, 0.0);

    view = mat4(vec4(right.x, up.x, L.x, 0.0),
                vec4(right.y, up.y, L.y, 0.0),
                vec4(right.z, up.z, L.z, 0.0),
                vec4(t, 1.0));
    proj = mat4(vec4(1.0 / shadowDistance, 0.0, 0.0, 0.0),
                vec4(0.0, 1.0 / shadowDistance, 0.0, 0.0),
                vec4(0.0, 0.0, -1.0 / SHADOW_DEPTH_HALF, 0.0),
                vec4(0.0, 0.0, 0.0, 1.0));
}

#endif

#ifndef CLOUDS_CLOUD_SHADOW_GLSL
#define CLOUDS_CLOUD_SHADOW_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"

// Cloud shadow map layout: CLOUD_SHADOW_RES^2 texels covering CLOUD_SHADOW_RANGE blocks on the
// cloud-base plane, centred on the camera and snapped to whole texels in world space.

float cloudShadowTexelSize() { return CLOUD_SHADOW_RANGE / float(CLOUD_SHADOW_RES); }

// World-snapped grid origin expressed relative to the camera (scene space).
vec2 cloudShadowOriginScene() {
    float ts = cloudShadowTexelSize();
    vec2 snapped = floor(cameraPosition.xz / ts) * ts;
    return snapped - cameraPosition.xz - 0.5 * CLOUD_SHADOW_RANGE;
}

vec2 cloudShadowTexelToScene(ivec2 px) {
    return cloudShadowOriginScene() + (vec2(px) + 0.5) * cloudShadowTexelSize();
}

#ifdef CLOUD_SHADOW_READ
uniform sampler2D cloudShadowTex;

// Transmittance of the clouds above a scene-space point along the light direction.
float cloudShadow(vec3 scenePos) {
    #if defined VOLUMETRIC_CLOUDS && defined CLOUD_SHADOWS
        if (fsLightDir.w < 0.0) return 1.0;
        vec3 l = fsLightDir.xyz;
        float ly = max(l.y, 0.08);
        float rise = fsCloud.z - (cameraPosition.y + scenePos.y);
        vec2 onBase = scenePos.xz + l.xz / ly * max(rise, 0.0);
        vec2 uv = (onBase - cloudShadowOriginScene()) / CLOUD_SHADOW_RANGE;
        float t = texture(cloudShadowTex, uv).r;
        // Beyond the map, fade to the average sky cover.
        float edge = maxOf(abs(uv - 0.5)) * 2.0;
        float fallback = 1.0 - fsCloud.x * 0.6;
        float v = mix(t, fallback, smoothstep(0.85, 1.0, edge));
        // Above the cloud base the layer no longer shades.
        return mix(v, 1.0, smoothstep(-50.0, 50.0, -rise));
    #else
        return 1.0;
    #endif
}
#endif

#endif

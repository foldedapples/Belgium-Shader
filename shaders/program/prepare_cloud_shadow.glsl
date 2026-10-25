// prepare.csh - cloud shadow map: transmittance of the cloud layer along the light for a
// camera-centred grid on the cloud-base plane (texel-snapped so shadows do not swim).
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/clouds/clouds.glsl"
#include "/lib/clouds/cloud_shadow.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
// Iris reads workGroups as literal integers (no arithmetic): CLOUD_SHADOW_RES / 16.
#if CLOUD_SHADOW_RES == 256
    const ivec3 workGroups = ivec3(16, 16, 1);
#elif CLOUD_SHADOW_RES == 1024
    const ivec3 workGroups = ivec3(64, 64, 1);
#else
    const ivec3 workGroups = ivec3(32, 32, 1);
#endif

layout(r16f) uniform writeonly image2D cloudShadowMap;

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(px, ivec2(CLOUD_SHADOW_RES)))) return;
    float t = 1.0;
    if (frameStateValid() && fsLightDir.w >= 0.0) {
        vec2 xz = cloudShadowTexelToScene(px);
        vec3 basePoint = vec3(xz.x, fsCloud.z - cameraPosition.y, xz.y);
        t = cloudShadowTransmittance(basePoint, fsLightDir.xyz);
    }
    imageStore(cloudShadowMap, px, vec4(t));
}
#endif

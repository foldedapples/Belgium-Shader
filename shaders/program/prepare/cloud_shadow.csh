// prepare: cloud shadow map. For each texel of a 256^2 grid covering CLOUD_SHADOW_EXTENT metres
// around a texel-snapped centre, integrates the cloud extinction vertically through the layer.
// Consumers convert this optical depth to transmittance along the actual light direction.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/state.glsl"
#define CLOUD_PRODUCER
#include "/lib/clouds/clouds_common.glsl"

layout(local_size_x = 16, local_size_y = 16) in;
const ivec3 workGroups = ivec3(16, 16, 1);
layout(r16f) uniform writeonly image2D cloudShadow;

void main() {
    #ifndef CLOUD_SHADOWS_ACTIVE
    return;
    #endif
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    float texel = CLOUD_SHADOW_EXTENT / float(CLOUD_SHADOW_RES);
    vec2 center = floor(cameraPosition.xz / texel) * texel;
    if (px == ivec2(0)) state.misc.zw = center;
    vec2 xz = center + ((vec2(px) + 0.5) / float(CLOUD_SHADOW_RES) - 0.5) * CLOUD_SHADOW_EXTENT;
    CloudWeather w = cloudWeatherAt(xz);
    float od = 0.0;
    if (w.coverage > 0.02) {
        // Through this column's own cloud (its type sets base and top).
        const int N = 10;
        float dy = (w.top - w.base) / float(N);
        for (int i = 0; i < N; i++) {
            vec3 p = vec3(xz.x, 62.0 + w.base + (float(i) + 0.5) * dy, xz.y);
            od += cloudExtinction(cloudDensity(p, w, 1)) * dy;
        }
    }
    if (w.anvil > 0.01) {
        // Cumulonimbus anvil spreading above the column.
        const int NA = 4;
        float dy = (CLOUD_TOP_STORM - ANVIL_BASE) / float(NA);
        for (int i = 0; i < NA; i++) {
            vec3 p = vec3(xz.x, 62.0 + ANVIL_BASE + (float(i) + 0.5) * dy, xz.y);
            if (p.y - 62.0 >= w.top) od += cloudExtinction(cloudDensity(p, w, 1)) * dy;
        }
    }
    imageStore(cloudShadow, px, vec4(od));
}

// setup.csh - transmittance LUT (256x64): exp(-optical depth) from (altitude, view zenith) to
// the top of the atmosphere. Static for the pipeline's lifetime.
#include "/lib/core/common.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const ivec3 workGroups = ivec3(32, 8, 1);

layout(rgba16f) uniform writeonly image2D transmittanceLut;

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(px, ivec2(TRANSMITTANCE_LUT_SIZE)))) return;
    vec2 uv = (vec2(px) + 0.5) / TRANSMITTANCE_LUT_SIZE;
    float r, mu;
    transmittanceLutParams(uv, r, mu);
    vec3 t = exp(-opticalDepthToTop(r, mu, 64));
    imageStore(transmittanceLut, px, vec4(t, 1.0));
}
#endif

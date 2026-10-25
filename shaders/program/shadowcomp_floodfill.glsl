// shadowcomp.csh, shadowcomp_a.csh, shadowcomp_b.csh - three propagation steps of coloured
// block light per frame through the voxel grid (LV_STEP 0..2).
// Wavefront flood fill, as vanilla light spreads: L' = max over the 6 neighbours (per channel)
// lowered by one light level, plus emission; zero in opaque voxels, filtered by glass tint,
// damped in foliage. Light travels one block per step, so 15 blocks are reached in 5 frames and
// removed lights fade as fast. (Before: one diffusion step per frame, mean of the neighbours x
// 0.97, which needs ~distance^2 steps - about 3 s for light to settle 15 blocks from a torch.)
// The first step of a frame re-aligns last frame's volume to this frame's origin.
#include "/lib/core/common.glsl"
#include "/lib/lighting/floodfill.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
const ivec3 workGroups = ivec3(16, 8, 16);

layout(r32ui) uniform readonly uimage3D voxelMap;
layout(rgba16f) uniform image3D lightVolA;
layout(rgba16f) uniform image3D lightVolB;

bool readA;
ivec3 shift;

vec3 loadPrevious(ivec3 v) {
    ivec3 q = v + shift;
    if (any(lessThan(q, ivec3(0))) || any(greaterThanEqual(q, LV_SIZE))) return vec3(0.0);
    return readA ? imageLoad(lightVolA, q).rgb : imageLoad(lightVolB, q).rgb;
}

void main() {
    ivec3 v = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(v, LV_SIZE))) return;
    // Step s = 3 * frame + LV_STEP reads A when even and writes the other volume, so the last
    // step of a frame writes B on even frames and A on odd ones (see sampleLightVolume).
    readA = ((frameCounter * 3 + LV_STEP) & 1) == 0;
    // Voxel v of this frame is voxel v + shift of last frame's volume (first step only).
    shift = LV_STEP == 0 ? lightVolumeOrigin(cameraPositionInt) - lightVolumeOrigin(previousCameraPositionInt) : ivec3(0);

    uint word = imageLoad(voxelMap, v).r;
    vec3 result = vec3(0.0);
    int level = voxelLevel(word);
    bool opaque = (word & LV_OPAQUE) != 0u;
    if (!opaque || level > 0) {
        vec3 m = max(max(max(loadPrevious(v + ivec3(1, 0, 0)), loadPrevious(v - ivec3(1, 0, 0))),
                         max(loadPrevious(v + ivec3(0, 1, 0)), loadPrevious(v - ivec3(0, 1, 0)))),
                     max(loadPrevious(v + ivec3(0, 0, 1)), loadPrevious(v - ivec3(0, 0, 1))));
        // Lower by one level (1/15 of full) while keeping the hue: scale all channels so the
        // brightest one drops by 1/15.
        float peak = maxOf(m);
        result = peak > 1.0 / 15.0 ? m * ((peak - 1.0 / 15.0) / peak) : vec3(0.0);
        if ((word & LV_GLASS) != 0u) result *= voxelTint(word);
        if ((word & LV_FOLIAGE) != 0u) result *= 0.7;
        if (level > 0) result = max(result, emitterColor(voxelMaterial(word)) * float(level) / 15.0);
    }
    if (!isFiniteVec(result)) result = vec3(0.0);
    result = min(result, vec3(64.0));
    if (readA) imageStore(lightVolB, v, vec4(result, 1.0));
    else imageStore(lightVolA, v, vec4(result, 1.0));
}
#endif

// shadowcomp.csh - one diffusion step of coloured block light through the voxel grid.
// L' = decay * mean(6 neighbours of last frame's volume, re-aligned to this frame's origin)
//      + emission, zeroed in opaque voxels, filtered by glass tint, damped in foliage.
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
    // Even frames read A and write B; odd frames the reverse (see blockLightChroma).
    readA = (frameCounter & 1) == 0;
    // Voxel v of this frame is voxel v + shift of last frame's volume.
    shift = lightVolumeOrigin(cameraPositionInt) - lightVolumeOrigin(previousCameraPositionInt);

    uint word = imageLoad(voxelMap, v).r;
    vec3 result = vec3(0.0);
    int level = voxelLevel(word);
    bool opaque = (word & LV_OPAQUE) != 0u;
    if (!opaque || level > 0) {
        vec3 sum = loadPrevious(v + ivec3(1, 0, 0)) + loadPrevious(v - ivec3(1, 0, 0))
                 + loadPrevious(v + ivec3(0, 1, 0)) + loadPrevious(v - ivec3(0, 1, 0))
                 + loadPrevious(v + ivec3(0, 0, 1)) + loadPrevious(v - ivec3(0, 0, 1));
        result = sum * (0.97 / 6.0);
        if ((word & LV_GLASS) != 0u) result *= voxelTint(word);
        if ((word & LV_FOLIAGE) != 0u) result *= 0.7;
        if (level > 0) result += emitterColor(voxelMaterial(word)) * float(level) / 15.0;
    }
    if (!isFiniteVec(result)) result = vec3(0.0);
    result = min(result, vec3(64.0));
    if (readA) imageStore(lightVolB, v, vec4(result, 1.0));
    else imageStore(lightVolA, v, vec4(result, 1.0));
}
#endif

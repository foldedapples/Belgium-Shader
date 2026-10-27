#ifndef MERIDIAN_LIGHT_VOLUME
#define MERIDIAN_LIGHT_VOLUME

// Coloured block-light volume. The shadow pass voxelises terrain into voxelImg (R16UI):
//   bit 15 occupied, bits 8..11 the block's own light level (at_midBlock.w), bits 0..7 material ID.
// shadowcomp flood-fills light into lightImgA/B (RGBA8): rgb = chromaticity (max = 1),
// a = light level / 15, with the same per-block decrement as vanilla light so the colour field
// matches where vanilla light reaches. Addressing is toroidal around a world-anchored origin.

#if CL_VOLUME == 0
const ivec3 VOXEL_SIZE = ivec3(128, 64, 128);
#elif CL_VOLUME == 1
const ivec3 VOXEL_SIZE = ivec3(192, 96, 192);
#else
const ivec3 VOXEL_SIZE = ivec3(256, 128, 256);
#endif

ivec3 voxelIndex(ivec3 blockPos) { return ((blockPos % VOXEL_SIZE) + VOXEL_SIZE) % VOXEL_SIZE; }

// Origin (min corner, world block coordinates) of the volume for a camera block position.
ivec3 voxelOriginFor(ivec3 cameraBlock) { return cameraBlock - VOXEL_SIZE / 2; }

bool insideVolume(ivec3 blockPos, ivec3 origin) {
    ivec3 r = blockPos - origin;
    return all(greaterThanEqual(r, ivec3(0))) && all(lessThan(r, VOXEL_SIZE));
}

uint encodeVoxel(int id, float lightLevel) {
    return 0x8000u | (uint(clamp(lightLevel, 0.0, 15.0) + 0.5) << 8u) | uint(id & 255);
}

#endif

#ifndef MERIDIAN_SIM_COMMON
#define MERIDIAN_SIM_COMMON

// Interactive water simulation domain: a toroidal (world-anchored, wrapping) grid of SIM_N x SIM_N
// cells of SIM_DX blocks, centred on the camera's cell. A texel at index i represents world cell
// i + SIM_N*m for whichever integer m is nearest the camera, so the field never has to be shifted
// when the player moves; cells that change m are cleared by the update pass.
//
// Cells are exact integers in unshifted world space, built from Iris's integer camera position.
// (cameraPosition is shifted by multiples of 30000 blocks to keep float precision, eyePosition is
// not, and the voxelised terrain uses unshifted integers: mixing them put the swimmer, the grid
// and the shorelines in different frames far from 0,0.) Positions inside the domain are handled
// relative to the camera's cell, so they stay small and precise. Requires uniforms.glsl.

#if WATER_SIM_RES == 0
const int SIM_N = 128;
#elif WATER_SIM_RES == 1
const int SIM_N = 256;
#else
const int SIM_N = 512;
#endif
const int SIM_CELLS_PER_BLOCK = 4;
const float SIM_DX = 1.0 / float(SIM_CELLS_PER_BLOCK);
const float SIM_EXTENT = float(SIM_N) * SIM_DX;

ivec2 simTexel(ivec2 cell) { return cell & (SIM_N - 1); }   // SIM_N is a power of two

// The camera's cell (exact).
ivec2 simCameraCell() {
    return cameraPositionInt.xz * SIM_CELLS_PER_BLOCK + ivec2(floor(cameraPositionFract.xz * float(SIM_CELLS_PER_BLOCK)));
}

// Camera-relative position (blocks) -> position in cells relative to simCameraCell().
vec2 simLocal(vec2 playerXZ) {
    vec2 f = cameraPositionFract.xz * float(SIM_CELLS_PER_BLOCK);
    return (f - floor(f)) + playerXZ * float(SIM_CELLS_PER_BLOCK);
}

// Weight that fades the simulated field out towards the edge of the domain; `local` in cells
// relative to the domain centre.
float simEdgeFade(vec2 local) {
    vec2 d = abs(local) / (0.5 * float(SIM_N));
    return 1.0 - smoothstep(0.7, 0.95, maxOf(d));
}

#endif

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
#elif WATER_SIM_RES == 2
const int SIM_N = 512;
#else
const int SIM_N = 1024;
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

// Distance from the domain centre as a fraction of the half-width; `local` in cells relative to
// the domain centre. Radial, so neither the absorbing layer nor the visible fade has corners.
float simRadius(vec2 local) { return length(local) / (0.5 * float(SIM_N)); }

// Absorbing layer: extra per-step damping of the surface velocity, rising quadratically from 0
// at 65 % of the half-width to 0.12 at the edge. Damping the velocity in a graded layer absorbs
// outgoing waves; the old layer scaled the height itself by up to 8 % per step, which acts like
// a change of stiffness and sent 13-23 % of each ring back towards the player
// (tools/tests/test_water_propagation.py: < 1.5 % now, also on the smallest grid).
float simSponge(vec2 local) {
    float u = saturate((simRadius(local) - 0.65) / 0.35);
    return 0.12 * u * u;
}

// Weight that fades the simulated field out towards the edge of the domain (rendering only).
float simEdgeFade(vec2 local) {
    return 1.0 - smoothstep(0.62, 0.95, simRadius(local));
}

#endif

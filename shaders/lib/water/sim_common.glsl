#ifndef MERIDIAN_SIM_COMMON
#define MERIDIAN_SIM_COMMON

// Interactive water simulation domain: a toroidal (world-anchored, wrapping) grid of SIM_N x SIM_N
// cells of SIM_DX blocks, covering the area around the camera. A texel at index i represents
// world cell i + SIM_N*m for whichever integer m is nearest the camera, so the field never has to
// be shifted when the player moves; cells that change m are cleared by the update pass.

#if WATER_SIM_RES == 0
const int SIM_N = 128;
#elif WATER_SIM_RES == 1
const int SIM_N = 256;
#else
const int SIM_N = 512;
#endif
const float SIM_DX = 0.25;
const float SIM_EXTENT = float(SIM_N) * SIM_DX;

// World cell coordinate (integer) of a world xz position.
ivec2 simCell(vec2 worldXZ) { return ivec2(floor(worldXZ / SIM_DX)); }
ivec2 simTexel(ivec2 cell) { return cell & (SIM_N - 1); }   // SIM_N is a power of two

// Weight that fades the simulated field out towards the edge of the domain around `centerXZ`.
float simEdgeFade(vec2 worldXZ, vec2 centerXZ) {
    vec2 d = abs(worldXZ - centerXZ) / (0.5 * SIM_EXTENT);
    return 1.0 - smoothstep(0.7, 0.95, maxOf(d));
}

#endif

#ifndef MERIDIAN_WORLD_COORD
#define MERIDIAN_WORLD_COORD

// Exact world-space xz for procedural surface detail (waves, rain ripples).
//
// The float world position (cameraPosition + camera-relative offset) loses precision with distance
// from 0,0 (2e-3 block at x = 30000, 0.06 block at x = 1e6), which makes fine patterns jitter as
// the camera moves. Iris also gives the camera position as an integer part plus a fraction; the
// integer part is wrapped to WORLD_WRAP blocks here, so the result is exact anywhere. Patterns
// evaluated in these coordinates must repeat every WORLD_WRAP blocks (wave vectors on the lattice
// 2 pi / WORLD_WRAP, hashed cells wrapped with the period) so crossing a wrap changes nothing.
// Requires uniforms.glsl.

const int WORLD_WRAP = 1536;

// a mod n for any sign of a (GLSL leaves % undefined for negative operands).
int wrapInt(int a, int n) { return a >= 0 ? a - (a / n) * n : n - 1 - (-a - 1 - ((-a - 1) / n) * n); }

vec2 wrappedWorldXZ(vec2 playerXZ) {
    ivec2 ci = ivec2(wrapInt(cameraPositionInt.x, WORLD_WRAP), wrapInt(cameraPositionInt.z, WORLD_WRAP));
    return vec2(ci) + cameraPositionFract.xz + playerXZ;
}

#endif

#ifndef MERIDIAN_RIPPLES
#define MERIDIAN_RIPPLES

// Procedural raindrop ripples: each cell of a world-space grid receives drops at random places
// and random moments (one per cycle, independent phase per cell), each drop launching a damped
// circular capillary wave. Neighbouring cells overlap so rings interfere; two grids at different
// scales keep the pattern irregular. Returns the height gradient d(h)/d(xz).
//
// Precision: the pattern is evaluated in exact wrapped world xz (lib/common/world_coord.glsl).
// Evaluated at the float world position (camera + offset), the error grows with distance from
// 0,0: up to 2e-3 block at x = 30000 (0.8 % of a ring wavelength), 0.06 block at x = 1e6 (25 %),
// where the rings jitter as the camera moves (tools/tests/test_ripple_precision.py). The wrap
// period is a whole number of cells of both layers and the cell hash wraps with it, so crossing a
// period boundary changes nothing (3072 cells of 0.5, 4096 cells of 0.375 in 1536 blocks).

#include "/lib/common/world_coord.glsl"

vec2 rippleCoord(vec2 playerXZ) { return wrappedWorldXZ(playerXZ); }

vec2 rippleLayer(vec2 p, float t, float cellSize, float seed, int cellsPerPeriod) {
    vec2 g = p / cellSize;
    ivec2 c0 = ivec2(floor(g));
    vec2 grad = vec2(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            ivec2 c = c0 + ivec2(i, j);
            ivec2 cw = ivec2(wrapInt(c.x, cellsPerPeriod), wrapInt(c.y, cellsPerPeriod));
            vec3 h = hash3(cw + ivec2(int(seed * 101.0), int(seed * 37.0)));
            float period = 0.9 + 0.8 * h.z;
            float tt = t / period + h.x;
            float cycle = floor(tt);
            float age = fract(tt) * period;                   // seconds since this drop landed
            vec2 rnd = hash2(cw * 7 + ivec2(int(cycle) & 1023, int(seed * 13.0)));
            vec2 center = (vec2(c) + 0.15 + 0.7 * rnd) * cellSize;
            vec2 d = p - center;
            float r = length(d);
            float front = age * 0.55;                         // ring radius, blocks
            float x = (r - front) * 26.0;
            float env = exp(-age * 3.2) * exp(-x * x * 0.08) * smoothstep(0.0, 0.05, age);
            float dh = -cos(x) * 26.0 * env;                  // d/dr of sin(x) * env (dominant term)
            grad += (r > 1e-4 ? d / r : vec2(0.0)) * dh;
        }
    }
    return grad;
}

// `playerXZ`: player-space (camera-relative) position.
vec2 rainRippleGradient(vec2 playerXZ, float t) {
    vec2 xz = rippleCoord(playerXZ);
    vec2 g = rippleLayer(xz, t, 0.5, 0.0, 3072) + rippleLayer(xz + 3.7, t * 1.13, 0.375, 1.0, 4096) * 0.7;
    return g * 0.0035;
}

#endif

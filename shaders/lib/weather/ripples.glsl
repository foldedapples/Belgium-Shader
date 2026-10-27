#ifndef MERIDIAN_RIPPLES
#define MERIDIAN_RIPPLES

// Procedural raindrop ripples: each cell of a world-space grid receives drops at random places
// and random moments (one per cycle, independent phase per cell), each drop launching a damped
// circular capillary wave. Neighbouring cells overlap so rings interfere; two grids at different
// scales keep the pattern irregular. Returns the height gradient d(h)/d(xz).

vec2 rippleLayer(vec2 p, float t, float cellSize, float seed) {
    vec2 g = p / cellSize;
    ivec2 c0 = ivec2(floor(g));
    vec2 grad = vec2(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            ivec2 c = c0 + ivec2(i, j);
            vec3 h = hash3(c + ivec2(int(seed * 101.0), int(seed * 37.0)));
            float period = 0.9 + 0.8 * h.z;
            float tt = t / period + h.x;
            float cycle = floor(tt);
            float age = fract(tt) * period;                   // seconds since this drop landed
            vec2 rnd = hash2(c * 7 + ivec2(int(cycle) & 1023, int(seed * 13.0)));
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

vec2 rainRippleGradient(vec2 xz, float t) {
    vec2 g = rippleLayer(xz, t, 0.55, 0.0) + rippleLayer(xz + 3.7, t * 1.13, 0.37, 1.0) * 0.7;
    return g * 0.0035;
}

#endif

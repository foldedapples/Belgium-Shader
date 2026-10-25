#ifndef CORE_NOISE_GLSL
#define CORE_NOISE_GLSL
#include "/lib/core/math.glsl"

// Integer hashing. hashU is the "lowbias32" mixer published into the public domain by
// Chris Wellons; the rest is ours.
uint hashU(uint x) {
    x ^= x >> 16u; x *= 0x7feb352du;
    x ^= x >> 15u; x *= 0x846ca68bu;
    x ^= x >> 16u;
    return x;
}
uint hashU(uvec2 v) { return hashU(v.x ^ hashU(v.y + 0x9e3779b9u)); }
uint hashU(uvec3 v) { return hashU(v.x ^ hashU(v.y ^ hashU(v.z + 0x632be5abu))); }

float u32ToUnit(uint x) { return float(x >> 8u) * (1.0 / 16777216.0); }
float hash11(uint x)  { return u32ToUnit(hashU(x)); }
float hash12(ivec2 p) { return u32ToUnit(hashU(uvec2(p))); }
float hash13(ivec3 p) { return u32ToUnit(hashU(uvec3(p))); }
vec2  hash22(ivec2 p) { uint h = hashU(uvec2(p)); return vec2(u32ToUnit(h), u32ToUnit(hashU(h))); }
vec3  hash33(ivec3 p) {
    uint h = hashU(uvec3(p));
    uint h2 = hashU(h);
    return vec3(u32ToUnit(h), u32ToUnit(h2), u32ToUnit(hashU(h2)));
}

// Additive recurrence with the plastic constant (R2 sequence, Roberts 2018): a low-discrepancy
// per-frame offset for blue-noise animation and stochastic sampling.
vec2 r2Sequence(int n) {
    const vec2 a = vec2(0.754877666246693, 0.569840290998053);
    return fract(0.5 + a * float(n));
}

// Interleaved gradient noise (Jimenez 2014) used only as a fallback when the blue-noise
// texture is unavailable to a stage.
float interleavedGradient(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

// Gradient-free value noise in 2-D and 3-D from the integer hash (smooth quintic fade).
float valueNoise(vec2 p) {
    vec2 i = floor(p), f = p - i;
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    ivec2 c = ivec2(i);
    float a = hash12(c), b = hash12(c + ivec2(1, 0));
    float d = hash12(c + ivec2(0, 1)), e = hash12(c + ivec2(1, 1));
    return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}
float valueNoise(vec3 p) {
    vec3 i = floor(p), f = p - i;
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    ivec3 c = ivec3(i);
    float n000 = hash13(c), n100 = hash13(c + ivec3(1, 0, 0));
    float n010 = hash13(c + ivec3(0, 1, 0)), n110 = hash13(c + ivec3(1, 1, 0));
    float n001 = hash13(c + ivec3(0, 0, 1)), n101 = hash13(c + ivec3(1, 0, 1));
    float n011 = hash13(c + ivec3(0, 1, 1)), n111 = hash13(c + ivec3(1, 1, 1));
    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

#endif

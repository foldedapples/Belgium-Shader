#ifndef MERIDIAN_NOISE
#define MERIDIAN_NOISE

// Integer hashes. pcg3d/pcg4d follow Jarzynski & Olano 2020, "Hash Functions for GPU
// Rendering" (JCGT 9(3)); hash11u is a PCG-style single-word permutation.
uint hash11u(uint v) {
    uint s = v * 747796405u + 2891336453u;
    uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
    return (w >> 22u) ^ w;
}

uvec3 pcg3d(uvec3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return v;
}

uvec4 pcg4d(uvec4 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
    v ^= v >> 16u;
    v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
    return v;
}

const float U32_TO_UNIT = 1.0 / 4294967296.0;

float hash1(float x)  { return float(hash11u(floatBitsToUint(x))) * U32_TO_UNIT; }
float hash1(ivec2 p)  { return float(pcg3d(uvec3(p, 0x9e3779b9u)).x) * U32_TO_UNIT; }
vec2  hash2(ivec2 p)  { return vec2(pcg3d(uvec3(p, 0x85ebca6bu)).xy) * U32_TO_UNIT; }
vec3  hash3(ivec2 p)  { return vec3(pcg3d(uvec3(p, 0xc2b2ae35u))) * U32_TO_UNIT; }
vec3  hash3(ivec3 p)  { return vec3(pcg3d(uvec3(p))) * U32_TO_UNIT; }
vec4  hash4(ivec3 p)  { return vec4(pcg4d(uvec4(p, 0x27d4eb2fu))) * U32_TO_UNIT; }

// Interleaved gradient noise (Jimenez 2014, "Next Generation Post Processing in Call of Duty").
float interleavedGradient(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

// R2 additive recurrence (Roberts 2018): low-discrepancy 2D sequence.
vec2 r2(float n) { return fract(n * vec2(0.754877666246693, 0.569840290998053) + 0.5); }
float r1(float n) { return fract(n * 0.618033988749895 + 0.5); }

// Quintic-interpolated value noise in 2D and 3D, range [0,1].
float valueNoise(vec2 p) {
    ivec2 i = ivec2(floor(p));
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = hash1(i), b = hash1(i + ivec2(1, 0));
    float c = hash1(i + ivec2(0, 1)), d = hash1(i + ivec2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float valueNoise(vec3 p) {
    ivec3 i = ivec3(floor(p));
    vec3 f = fract(p);
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float n000 = hash3(i).x,                n100 = hash3(i + ivec3(1, 0, 0)).x;
    float n010 = hash3(i + ivec3(0, 1, 0)).x, n110 = hash3(i + ivec3(1, 1, 0)).x;
    float n001 = hash3(i + ivec3(0, 0, 1)).x, n101 = hash3(i + ivec3(1, 0, 1)).x;
    float n011 = hash3(i + ivec3(0, 1, 1)).x, n111 = hash3(i + ivec3(1, 1, 1)).x;
    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

// Gradient noise in 2D with analytic derivative: returns (value in ~[-1,1], d/dx, d/dy).
vec3 gradientNoiseD(vec2 p) {
    ivec2 i = ivec2(floor(p));
    vec2 f = fract(p);
    vec2 u  = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
    vec2 ga = hash2(i) * 2.0 - 1.0;
    vec2 gb = hash2(i + ivec2(1, 0)) * 2.0 - 1.0;
    vec2 gc = hash2(i + ivec2(0, 1)) * 2.0 - 1.0;
    vec2 gd = hash2(i + ivec2(1, 1)) * 2.0 - 1.0;
    float va = dot(ga, f);
    float vb = dot(gb, f - vec2(1, 0));
    float vc = dot(gc, f - vec2(0, 1));
    float vd = dot(gd, f - vec2(1, 1));
    float v = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd);
    vec2 d = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
           + du * (u.yx * (va - vb - vc + vd) + vec2(vb, vc) - va);
    return vec3(v * 1.41421356, d * 1.41421356);
}

#endif

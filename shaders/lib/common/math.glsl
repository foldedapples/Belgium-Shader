#ifndef MERIDIAN_MATH
#define MERIDIAN_MATH

const float PI      = 3.14159265358979;
const float TAU     = 6.28318530717959;
const float HALF_PI = 1.57079632679490;
const float INV_PI  = 0.31830988618379;
const float INV_4PI = 0.07957747154595;
const float GOLDEN_ANGLE = 2.39996322972865;

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2  saturate(vec2 x)  { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, 0.0, 1.0); }
vec4  saturate(vec4 x)  { return clamp(x, 0.0, 1.0); }

float sq(float x) { return x * x; }
vec2  sq(vec2 x)  { return x * x; }
vec3  sq(vec3 x)  { return x * x; }
float pow4(float x) { x *= x; return x * x; }
float pow5(float x) { float x2 = x * x; return x2 * x2 * x; }

float maxOf(vec2 v) { return max(v.x, v.y); }
float maxOf(vec3 v) { return max(v.x, max(v.y, v.z)); }
float minOf(vec2 v) { return min(v.x, v.y); }
float minOf(vec3 v) { return min(v.x, min(v.y, v.z)); }

float remap(float x, float a, float b) { return saturate((x - a) / (b - a)); }
float remapUnclamped(float x, float a, float b, float c, float d) { return c + (x - a) * (d - c) / (b - a); }

// Rec.709 relative luminance of linear RGB.
float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// Largest radiance written to the RGBA16F HDR targets. Half floats overflow to infinity above
// 65504; the physical solar disk (~1.5e5 here) and mirror reflections of it exceed that, and a
// single infinite or NaN pixel spreads through bloom and the TAA history as a white block or
// streak. 3e4 leaves headroom for later additions (fog, volumetric light) and is still ~1e4x
// display white at daytime exposure, so nothing visible is lost.
const float HDR_MAX = 3.0e4;
vec3 hdrSafe(vec3 c) { return any(isnan(c)) ? vec3(0.0) : clamp(c, 0.0, HDR_MAX); }

float smootherstep(float a, float b, float x) {
    x = saturate((x - a) / (b - a));
    return x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
}

mat2 rotate2d(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, s, -s, c);
}

// Rotation of `v` about unit axis `k` by angle `a` (Rodrigues).
vec3 rotateAxis(vec3 v, vec3 k, float a) {
    float c = cos(a), s = sin(a);
    return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

// Orthonormal basis around n (Duff et al. 2017, "Building an Orthonormal Basis, Revisited").
mat3 basisFromNormal(vec3 n) {
    float s = n.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (s + n.z);
    float b = n.x * n.y * a;
    vec3 t = vec3(1.0 + s * n.x * n.x * a, s * b, -s * n.x);
    vec3 bt = vec3(b, s + n.y * n.y * a, -n.y);
    return mat3(t, bt, n);
}

// Ray / sphere intersection. Returns (near, far) distances; far < 0 means no hit.
vec2 raySphere(vec3 ro, vec3 rd, float radius) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) return vec2(-1.0);
    h = sqrt(h);
    return vec2(-b - h, -b + h);
}

// Same, for a sphere centred at `center`.
vec2 raySphere(vec3 ro, vec3 rd, vec3 center, float radius) {
    return raySphere(ro - center, rd, radius);
}

#endif

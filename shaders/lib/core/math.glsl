#ifndef CORE_MATH_GLSL
#define CORE_MATH_GLSL
// Scalar/vector helpers shared by every stage. Everything here is guarded against the usual
// sources of NaN: divisions use an epsilon-signed denominator, normalisation has a fallback.

const float PI      = 3.14159265358979;
const float TAU     = 6.28318530717959;
const float HALF_PI = 1.57079632679490;
const float INV_PI  = 0.31830988618379;
const float INV_TAU = 0.15915494309190;
const float GOLDEN_ANGLE = 2.39996322972865;
const float EPSILON = 1e-6;

float sq(float x) { return x * x; }
vec2  sq(vec2 x)  { return x * x; }
vec3  sq(vec3 x)  { return x * x; }
float pow5(float x) { float x2 = x * x; return x2 * x2 * x; }

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2  saturate(vec2 x)  { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, 0.0, 1.0); }
vec4  saturate(vec4 x)  { return clamp(x, 0.0, 1.0); }

float maxOf(vec2 v) { return max(v.x, v.y); }
float maxOf(vec3 v) { return max(v.x, max(v.y, v.z)); }
float minOf(vec2 v) { return min(v.x, v.y); }
float minOf(vec3 v) { return min(v.x, min(v.y, v.z)); }

float linearStep(float a, float b, float x) { return saturate((x - a) / (b - a)); }
float remap(float x, float a, float b, float c, float d) { return c + (x - a) * (d - c) / (b - a); }
// Remap that clamps and survives a degenerate source range.
float remapSafe(float x, float a, float b, float c, float d) {
    float range = b - a;
    float t = abs(range) > EPSILON ? (x - a) / range : step(a, x);
    return mix(c, d, saturate(t));
}

float safeDiv(float a, float b) { return a / (abs(b) > EPSILON ? b : (b < 0.0 ? -EPSILON : EPSILON)); }

vec3 safeNormalize(vec3 v, vec3 fallback) {
    float l2 = dot(v, v);
    return l2 > 1e-20 ? v * inversesqrt(l2) : fallback;
}
vec3 safeNormalize(vec3 v) { return safeNormalize(v, vec3(0.0, 1.0, 0.0)); }
vec2 safeNormalize(vec2 v) {
    float l2 = dot(v, v);
    return l2 > 1e-20 ? v * inversesqrt(l2) : vec2(1.0, 0.0);
}

bool isFiniteVec(vec3 v) { return !(any(isnan(v)) || any(isinf(v))); }
bool isFiniteVec(vec4 v) { return !(any(isnan(v)) || any(isinf(v))); }
// Replaces NaN/Inf (and negative radiance) with black so one bad pixel cannot poison
// temporal history or bloom.
vec3 sanitizeRadiance(vec3 c) { return isFiniteVec(c) ? max(c, vec3(0.0)) : vec3(0.0); }
vec4 sanitizeRadiance(vec4 c) { return isFiniteVec(c) ? max(c, vec4(0.0)) : vec4(0.0); }

// Orthonormal basis around a unit vector without a branchy "pick an up axis" step
// (construction from Duff et al. 2017, "Building an Orthonormal Basis, Revisited").
mat3 basisFromNormal(vec3 n) {
    float s = n.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (s + n.z);
    float b = n.x * n.y * a;
    vec3 t = vec3(1.0 + s * n.x * n.x * a, s * b, -s * n.x);
    vec3 bt = vec3(b, s + n.y * n.y * a, -n.y);
    return mat3(t, bt, n);
}

mat2 rotate2(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }

// Rodrigues rotation of v around unit axis k by angle a.
vec3 rotateAxis(vec3 v, vec3 k, float a) {
    float c = cos(a), s = sin(a);
    return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

// Ray/sphere intersection for a sphere centred at the origin. Returns (near, far) distances;
// far < 0 means no hit.
vec2 raySphere(vec3 ro, vec3 rd, float radius) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) return vec2(-1.0, -1.0);
    h = sqrt(h);
    return vec2(-b - h, -b + h);
}

// Ray against the horizontal slab [y0, y1]. Returns (enter, exit), exit <= enter means miss.
vec2 raySlab(float originY, float dirY, float y0, float y1) {
    if (abs(dirY) < 1e-5) {
        bool inside = originY >= y0 && originY <= y1;
        return inside ? vec2(0.0, 1e7) : vec2(1.0, 0.0);
    }
    float t0 = (y0 - originY) / dirY;
    float t1 = (y1 - originY) / dirY;
    return vec2(max(min(t0, t1), 0.0), max(t0, t1));
}

float smoothMin(float a, float b, float k) {
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

#endif

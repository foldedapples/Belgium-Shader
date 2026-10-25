#ifndef CORE_ENCODING_GLSL
#define CORE_ENCODING_GLSL
#include "/lib/core/math.glsl"

// Octahedral unit-vector encoding into [0,1]^2 (Cigolle et al. 2014). Robust to zero-length
// input: decodes to +Y.
vec2 octSignNonZero(vec2 v) { return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0); }

vec2 encodeUnitVector(vec3 n) {
    n = safeNormalize(n);
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    vec2 p = n.z >= 0.0 ? n.xy : (1.0 - abs(n.yx)) * octSignNonZero(n.xy);
    return p * 0.5 + 0.5;
}

vec3 decodeUnitVector(vec2 e) {
    vec2 p = e * 2.0 - 1.0;
    vec3 n = vec3(p, 1.0 - abs(p.x) - abs(p.y));
    float t = max(-n.z, 0.0);
    n.xy += vec2(n.x >= 0.0 ? -t : t, n.y >= 0.0 ? -t : t);
    return safeNormalize(n);
}

// 8-bit flag helpers for values stored in unorm8 channels.
float encodeByte(int v) { return float(clamp(v, 0, 255)) / 255.0; }
int   decodeByte(float x) { return int(x * 255.0 + 0.5); }
bool  hasFlag(int flags, int bit) { return (flags & bit) != 0; }

#endif

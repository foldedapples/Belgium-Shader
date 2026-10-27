#ifndef MERIDIAN_ENCODING
#define MERIDIAN_ENCODING

// Octahedral unit-vector encoding (Meyer et al. 2010; Cigolle et al. 2014, "A Survey of
// Efficient Representations for Independent Unit Vectors"). Maps a unit vector to [0,1]^2.
vec2 octEncode(vec3 n) {
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    vec2 p = n.xy;
    if (n.z < 0.0) p = (1.0 - abs(p.yx)) * vec2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
    return p * 0.5 + 0.5;
}

vec3 octDecode(vec2 e) {
    e = e * 2.0 - 1.0;
    vec3 n = vec3(e, 1.0 - abs(e.x) - abs(e.y));
    float t = max(-n.z, 0.0);
    n.x += n.x >= 0.0 ? -t : t;
    n.y += n.y >= 0.0 ? -t : t;
    return normalize(n);
}

// Two 8-bit values in one 16-bit UNORM channel. Exact for values that are multiples of 1/255.
float pack2x8(vec2 v) {
    vec2 b = floor(saturate(v) * 255.0 + 0.5);
    return (b.x * 256.0 + b.y) / 65535.0;
}

vec2 unpack2x8(float p) {
    float b = floor(p * 65535.0 + 0.5);
    float hi = floor(b / 256.0);
    return vec2(hi, b - hi * 256.0) / 255.0;
}

// Integer variant for exact 8-bit fields (IDs).
float pack2x8u(uint hi, uint lo) { return float((hi << 8u) | lo) / 65535.0; }
uvec2 unpack2x8u(float p) {
    uint b = uint(p * 65535.0 + 0.5);
    return uvec2(b >> 8u, b & 255u);
}

// sRGB transfer functions (IEC 61966-2-1).
vec3 srgbToLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 linearToSrgb(vec3 c) {
    c = max(c, 0.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

#endif

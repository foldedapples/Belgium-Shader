#ifndef CORE_COLOR_GLSL
#define CORE_COLOR_GLSL
#include "/lib/core/math.glsl"

// Rec.709 / sRGB primaries throughout.
float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 srgbToLinear(vec3 c) {
    vec3 lo = c / 12.92;
    vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
    return mix(lo, hi, step(vec3(0.04045), c));
}
vec3 linearToSrgb(vec3 c) {
    c = max(c, vec3(0.0));
    vec3 lo = c * 12.92;
    vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
    return mix(lo, hi, step(vec3(0.0031308), c));
}

vec3 rgbToYCoCg(vec3 c) {
    return vec3(0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
                0.5 * c.r - 0.5 * c.b,
               -0.25 * c.r + 0.5 * c.g - 0.25 * c.b);
}
vec3 yCoCgToRgb(vec3 c) {
    return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);
}

// Planck's law evaluated at three representative wavelengths (red 610 nm, green 550 nm,
// blue 465 nm), normalised to unit luminance. Physically motivated stand-in for a full
// spectral integration; accurate enough for star, fire and accretion-disk tints.
vec3 blackbody(float kelvin) {
    kelvin = clamp(kelvin, 800.0, 60000.0);
    const vec3 lambda = vec3(610e-9, 550e-9, 465e-9);
    const float c2 = 1.4388e-2; // h*c/k in m*K
    vec3 l5 = lambda * lambda * lambda * lambda * lambda;
    vec3 radiance = 1.0 / (l5 * (exp(c2 / (lambda * kelvin)) - 1.0));
    return radiance / max(luminance(radiance), 1e-30);
}

// Smooth white-balance multiplier relative to a D65-ish reference (6500 K).
vec3 whiteBalance(float kelvin) {
    vec3 ref = blackbody(6500.0);
    return ref / blackbody(kelvin);
}

#endif

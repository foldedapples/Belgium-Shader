#ifndef MERIDIAN_TONEMAP
#define MERIDIAN_TONEMAP

// Display transforms. Input: exposed linear Rec.709 scene radiance. Output: linear display
// values in [0,1] (the final pass applies the sRGB transfer function).

// ---- 0: Meridian filmic (this project's own curve).
// Tone curve: the Naka-Rushton photoreceptor response y = x^c / (x^c + s^c) (Naka & Rushton
// 1966), c = 1.25, s chosen so middle grey 0.18 maps to ~0.19, normalised so 16x middle grey
// reaches white. It is applied to the largest channel and the colour is scaled with it, which
// keeps hue and saturation exactly (a per-channel curve turns bright orange lava yellow: measured
// 29 degrees of hue drift in tools/preview/tests.html). Real film and eyes still see very bright
// light go towards white, so in the shoulder the colour is mixed towards neutral of the same
// value; mixing with grey changes saturation but never hue.
float nakaRushton(float x) {
    const float C = 1.25;
    const float SC = 0.49983;     // 0.18^C * (1/0.19 - 1)
    const float WC = 32.0;        // 16^C
    float xc = pow(max(x, 0.0), C);
    return (xc / (xc + SC)) / (WC / (WC + SC));
}

vec3 meridianFilmic(vec3 x) {
    x = max(x, 0.0);
    float n = maxOf(x);
    if (n <= 1e-8) return vec3(0.0);
    float y = min(nakaRushton(n), 1.0);
    vec3 c = x * (y / n);
    // Path to white in the shoulder (display values above ~0.6).
    float s = smoothstep(0.6, 1.0, y);
    c = mix(c, vec3(y), s * s * 0.9);
    return saturate(c);
}

// ---- 1: Khronos PBR Neutral tone mapper (Copyright 2024 The Khronos Group Inc.,
// Apache License 2.0; https://github.com/KhronosGroup/ToneMapping). Reimplemented from the
// published specification; see THIRD_PARTY_NOTICES.md.
vec3 khronosPbrNeutral(vec3 color) {
    const float startCompression = 0.8 - 0.04;
    const float desaturation = 0.15;
    float x = min(color.r, min(color.g, color.b));
    float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
    color -= offset;
    float peak = max(color.r, max(color.g, color.b));
    if (peak < startCompression) return color;
    const float d = 1.0 - startCompression;
    float newPeak = 1.0 - d * d / (peak + d - startCompression);
    color *= newPeak / peak;
    float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
    return mix(color, newPeak * vec3(1.0), g);
}

// ---- 2: extended Reinhard on luminance (Reinhard et al. 2002) with a white point, hue preserved.
vec3 reinhardLuminance(vec3 c) {
    const float WHITE = 12.0;
    float l = luminance(c);
    float ld = l * (1.0 + l / (WHITE * WHITE)) / (1.0 + l);
    vec3 o = c * (ld / max(l, 1e-6));
    // Bleed over-range channels into the others so bright colours go towards white smoothly.
    float over = max(maxOf(o) - 1.0, 0.0);
    return saturate(o + over * 0.5);
}

vec3 tonemap(vec3 c) {
    #if TONEMAP == 1
    return saturate(khronosPbrNeutral(c));
    #elif TONEMAP == 2
    return reinhardLuminance(c);
    #else
    return meridianFilmic(c);
    #endif
}

#endif

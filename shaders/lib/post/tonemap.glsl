#ifndef MERIDIAN_TONEMAP
#define MERIDIAN_TONEMAP

// Display transforms. Input: exposed linear Rec.709 scene radiance. Output: linear display
// values in [0,1] (the final pass applies the sRGB transfer function).

#include "/lib/post/oklab.glsl"

// ---- 0: Belgium filmic (this project's own transform, the default).
// Why the image looked grey and washed out with the previous default (3, below): its curve has a
// log-log slope of 1.0 around middle grey, so scene contrast passed through flat (a film or ACES
// curve has ~1.3-1.4), lifted the shadows (1/8 of middle grey displayed at 0.0174, about twice a
// film curve), and its hue-preserving scaling gave none of the mid-tone saturation a film curve
// produces. Here:
//  * tone curve y = N (x^c / (x^c + s^c))^q, fitted so middle grey stays at 0.18, the mid-tone
//    slope is 1.28 and the toe 1.4 (1/8 grey -> 0.0104), and white is reached at ~16x middle grey;
//  * applied to the largest channel with the colour scaled along, so hue and channel ratios are
//    kept and nothing leaves the gamut;
//  * colours go towards white only beyond white (largest channel above ~8x middle grey, fully
//    at ~45x): the sun disk and glints whiten, lava, fire and sunlit colours keep their saturation;
//  * a film-like chroma gain in the mid-tones, applied in Oklab so the hue does not drift, fading
//    in deep shadow and towards white, then gamut compression by chroma at constant lightness.
// Measured on a chart of block colours (tools/tests/test_tonemap.py): no hue shift, sunlit grass
// Oklab chroma 0.168 with the Realistic profile (old 0.157, texture 0.145), orange light keeps its
// colour to 3 stops over middle grey (old: greying from 2), deeper shadows, fuller highlights.
const float FILMIC_C = 2.0;
const float FILMIC_S = 0.5920;
const float FILMIC_Q = 0.70;
const float FILMIC_CHROMA = 0.18;

float filmicCurve(float x) {
    const float SC = pow(FILMIC_S, FILMIC_C);
    const float WC = pow(2.88, FILMIC_C);                  // 16 x middle grey
    const float N = 0.985 / pow(WC / (WC + SC), FILMIC_Q);
    float xc = pow(max(x, 0.0), FILMIC_C);
    return min(N * pow(xc / (xc + SC), FILMIC_Q), 1.0);
}

vec3 belgiumFilmic(vec3 x) {
    x = max(x, 0.0);
    float n = maxOf(x);
    if (n <= 1e-10) return vec3(0.0);
    float y = filmicCurve(n);
    vec3 c = x * (y / n);
    float toWhite = smoothstep(0.0, 2.5, log2(n / 1.44));
    c = mix(c, vec3(y), toWhite);
    vec3 lab = linearToOklab(c);
    float e = log2(n / 0.18) + 0.5;
    lab.yz *= 1.0 + FILMIC_CHROMA * exp(-e * e / 9.0) * (1.0 - toWhite);
    return oklabToDisplay(lab);
}

// ---- 3: Meridian filmic (the previous default; flat mid-tones, kept for comparison).
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
    #elif TONEMAP == 3
    return meridianFilmic(c);
    #else
    return belgiumFilmic(c);
    #endif
}

#endif

#ifndef POST_GRADE_GLSL
#define POST_GRADE_GLSL
#include "/lib/core/color.glsl"
#include "/lib/post/color_profile.glsl"

// Colour grading. Scene-referred steps run on exposed linear HDR before the tone curve;
// display-referred steps run on the tone-mapped 0..1 signal.

// Scotopic (rod) vision: in very dim light colour fades and the eye's peak sensitivity moves
// toward blue. Driven by *absolute* scene luminance so it follows the light, not the exposure.
vec3 purkinjeShift(vec3 c, float absoluteLuminance) {
    float scotopic = (1.0 - smoothstep(2e-4, 5e-3, absoluteLuminance)) * NIGHT_DESATURATION;
    float rod = dot(c, vec3(0.08, 0.6, 0.32));
    vec3 rodColour = rod * vec3(0.78, 0.92, 1.18);
    return mix(c, rodColour, scotopic);
}

vec3 gradeSceneReferred(vec3 c, float absoluteLuminance) {
    c *= whiteBalance(float(WHITE_BALANCE));
    c = purkinjeShift(c, absoluteLuminance);
    return c;
}

vec3 gradeDisplayReferred(vec3 c, vec2 uv) {
    // Contrast: a symmetric curve around mid grey in perceptual space.
    vec3 s = linearToSrgb(c);
    s = saturate(0.5 + (s - 0.5) * CP_CONTRAST);
    c = srgbToLinear(s);
    float l = luminance(c);
    // Saturation, then vibrance (boosts muted colours more than saturated ones).
    c = mix(vec3(l), c, CP_SATURATION);
    float sat = maxOf(c) - minOf(c);
    c = mix(vec3(l), c, 1.0 + (CP_VIBRANCE - 1.0) * (1.0 - saturate(sat * 2.0)));
    #ifdef VIGNETTE
        vec2 d = uv - 0.5;
        c *= 1.0 - VIGNETTE_STRENGTH * smoothstep(0.15, 0.75, dot(d, d) * 2.0);
    #endif
    return saturate(c);
}

#endif

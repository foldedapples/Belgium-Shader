#ifndef POST_TONEMAP_GLSL
#define POST_TONEMAP_GLSL
#include "/lib/core/color.glsl"

// Belgium filmic curve: rational f(x) = x(x+b) / (x(x+c)+d), asymptote 1.
// Coefficients were least-squares fitted to anchor points chosen for this pack:
// 0.18 -> 0.168 (mid grey kept near scene-referred),
// 1.0 -> 0.62, 4.0 -> 0.90, 16 -> 0.98. Near-linear toe; contrast is a separate grade step.
const float TM_B = 0.65;
const float TM_C = 0.98;
const float TM_D = 0.68;

float filmicCurve(float x) { x = max(x, 0.0); return x * (x + TM_B) / (x * (x + TM_C) + TM_D); }
vec3  filmicCurve(vec3 x)  { x = max(x, vec3(0.0)); return x * (x + TM_B) / (x * (x + TM_C) + TM_D); }

// Blend of a per-channel curve (natural highlight desaturation, mild hue shift of hot colours)
// and a luminance-ratio curve (hue preserving). The ratio path is pulled to white as its
// luminance approaches display white so saturated lights never clip to flat primaries.
vec3 tonemapFilmic(vec3 c) {
    vec3 perChannel = filmicCurve(c);
    float l = luminance(c);
    float lt = filmicCurve(l);
    vec3 ratio = c * (lt / max(l, 1e-6));
    float whiteMix = smoothstep(0.55, 1.0, lt);
    ratio = mix(ratio, vec3(lt), whiteMix);
    vec3 outC = mix(perChannel, ratio, 0.45);
    return saturate(outC);
}

// Cinematic: the same shoulder with a deeper toe - scene contrast is expanded around middle
// grey in log space before the curve (shadows sink, highlights roll off later).
vec3 tonemapCinematic(vec3 c) {
    float l = max(luminance(c), 1e-7);
    float expanded = 0.18 * pow(l / 0.18, 1.12);
    return tonemapFilmic(c * (expanded / l));
}

// Neutral: fully hue-preserving (luminance curve applied to the colour ratio), with a gentle
// path to white; keeps saturated lights saturated, as the Fantasy profile wants.
vec3 tonemapNeutral(vec3 c) {
    float l = luminance(c);
    float lt = filmicCurve(l);
    vec3 r = c * (lt / max(l, 1e-6));
    float over = maxOf(r);
    if (over > 1.0) r = mix(r / over, vec3(1.0), saturate((over - 1.0) * 0.5));
    return saturate(mix(r, vec3(lt), smoothstep(0.8, 1.0, lt) * 0.5));
}

vec3 tonemapSelected(vec3 c, int curve) {
    if (curve == 1) return tonemapCinematic(c);
    if (curve == 2) return tonemapNeutral(c);
    return tonemapFilmic(c);
}

#endif

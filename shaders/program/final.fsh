// final: bloom, exposure, Purkinje shift, grading, tone mapping, sharpening, vignette, dither,
// debug views.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/state.glsl"
#include "/lib/lighting/emitters.glsl"
#define BLOOM_COMBINE
#include "/lib/post/bloom.glsl"
#include "/lib/post/tonemap.glsl"
#include "/lib/post/grading.glsl"
#include "/lib/lighting/shadow_proj.glsl"
#include "/lib/sky/celestial.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex9;

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

vec3 fetchScene(ivec2 p) {
    return texelFetch(colortex0, clamp(p, ivec2(0), ivec2(viewWidth, viewHeight) - 1), 0).rgb;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 c = fetchScene(px);

    #if DEBUG_VIEW != 0 && DEBUG_VIEW != 18 && DEBUG_VIEW != 19 && (DEBUG_VIEW < 28 || DEBUG_VIEW > 30)
    // Data views are written as display values by the pass that owns them.
    outColor = vec4(linearToSrgb(saturate(c)), 1.0);
    return;
    #endif

    // Contrast-adaptive sharpening of the TAA result (counters its slight softness).
    #ifdef TAA
    {
        vec3 n = fetchScene(px + ivec2(0, 1)), s = fetchScene(px - ivec2(0, 1));
        vec3 e = fetchScene(px + ivec2(1, 0)), w = fetchScene(px - ivec2(1, 0));
        vec3 mn = min(c, min(min(n, s), min(e, w))), mx = max(c, max(max(n, s), max(e, w)));
        vec3 amp = sqrt(saturate(min(mn, 2.0 - mx) / max(mx, 1e-4)));
        vec3 wgt = -amp * (TAA_SHARPNESS * 0.125);
        c = max((c + (n + s + e + w) * wgt) / (1.0 + 4.0 * wgt), 0.0);
    }
    #endif

    float exposure = max(state.exposure, 1e-6);

    #ifdef BLOOM
    vec3 bloom = combineBloom(colortex9, texcoord);
    c = mix(c, bloom, 0.045 * BLOOM_STRENGTH);
    #if DEBUG_VIEW == 30
    // Bloom: only what the bloom adds, at the current exposure.
    outColor = vec4(linearToSrgb(tonemap(max(bloom - fetchScene(px), 0.0) * 0.045 * BLOOM_STRENGTH * exposure * 4.0)), 1.0);
    return;
    #endif
    #elif DEBUG_VIEW == 30
    outColor = vec4(0.0, 0.0, 0.0, 1.0);    // bloom is off
    return;
    #endif

    Grade g = currentGrade();
    c = applySceneGrade(c, g);
    vec3 exposed = c * exposure;

    #if DEBUG_VIEW == 19
    // HDR clipping: magenta where the exposed value exceeds display white before tone mapping.
    outColor = vec4(maxOf(exposed) > 1.0 ? vec3(1.0, 0.0, 1.0) : linearToSrgb(tonemap(exposed)), 1.0);
    return;
    #elif DEBUG_VIEW == 18
    // Exposure: log2 luminance relative to the adapted average, blue (-4 EV) .. red (+4 EV).
    float rel = log2(max(luminance(c), 1e-6)) - state.avgLogLuminance;
    vec3 heat = mix(vec3(0.1, 0.2, 1.0), vec3(1.0, 0.15, 0.05), saturate(rel / 8.0 + 0.5));
    outColor = vec4(linearToSrgb(heat), 1.0);
    return;
    #endif

    // Purkinje shift when adapted to darkness (high exposure multiplier).
    #ifdef WORLD_OVERWORLD
    float dark = saturate((log2(exposure) - 1.5) / 4.0);
    exposed = purkinje(exposed, dark);
    #endif

    vec3 display = tonemap(exposed);
    #if DEBUG_VIEW == 29
    // Tone mapping only: the display transform without the colour profile's display grading.
    outColor = vec4(linearToSrgb(display), 1.0);
    return;
    #endif
    display = applyDisplayGrade(display, g);
    #if DEBUG_VIEW == 28
    // Saturation: Oklab chroma of the final image, grey (none) -> blue -> green -> yellow -> red
    // (0.25, very vivid); magenta where the colour sits on the sRGB gamut boundary.
    {
        vec3 lab = linearToOklab(display);
        float ch = length(lab.yz) / 0.25;
        vec3 heat = ch < 0.33 ? mix(vec3(0.25), vec3(0.1, 0.3, 1.0), ch / 0.33)
                  : ch < 0.66 ? mix(vec3(0.1, 0.3, 1.0), vec3(0.1, 0.9, 0.2), (ch - 0.33) / 0.33)
                  : mix(vec3(1.0, 0.9, 0.1), vec3(1.0, 0.1, 0.05), saturate((ch - 0.66) / 0.34));
        bool edge = (minOf(display) < 0.002 || maxOf(display) > 0.998) && length(lab.yz) > 0.05;
        outColor = vec4(edge ? vec3(1.0, 0.0, 1.0) : heat * mix(0.4, 1.0, lab.x), 1.0);
        return;
    }
    #endif

    if (VIGNETTE > 0.0) {
        vec2 d = texcoord - 0.5;
        display *= 1.0 - VIGNETTE * smoothstep(0.25, 0.9, dot(d, d) * 2.0);
    }

    vec3 srgb = linearToSrgb(display);
    // Triangular dither of one 8-bit step removes banding in skies and fog.
    float n1 = interleavedGradient(gl_FragCoord.xy), n2 = interleavedGradient(gl_FragCoord.xy + 37.3);
    srgb += (n1 + n2 - 1.0) / 255.0;
    outColor = vec4(srgb, 1.0);
}

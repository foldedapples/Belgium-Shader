// composite4 - depth of field (optional, DOF).
// Thin-lens circle of confusion: c = A * f * |1/z_focus - 1/z| scaled to pixels, with the
// focus distance auto-tracked at the screen centre (FrameState, smoothed in composite6) or
// set manually. Gather with a Vogel disk; each sample counts only if its own CoC reaches the
// centre pixel, so sharp foreground does not smear into blurred background.
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/frame_state.glsl"
#include "/lib/core/blue_noise.glsl"
#include "/lib/material/gbuffer.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;

in vec2 texCoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outScene;

float focusDistance() {
    #if DOF_FOCUS == 0
        return frameStateValid() ? max(fsFocus.x, 0.3) : 8.0;
    #else
        return float(DOF_FOCUS);
    #endif
}

float cocPixels(float depth) {
    if (depth >= 1.0) depth = 0.9999;
    float z = linearizeDepth(depth, near, far);
    float zf = focusDistance();
    // Aperture in blocks-equivalent; DOF_APERTURE scales the lens.
    float c = DOF_APERTURE * 0.05 * abs(1.0 / zf - 1.0 / z) * zf;
    return clamp(c * viewHeight, 0.0, float(DOF_MAX_RADIUS));
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 centre = texelFetch(colortex0, px, 0).rgb;
    #ifdef DOF
        float d = texelFetch(depthtex0, px, 0).r;
        bool hand = (decodeByte(texelFetch(colortex4, px, 0).a) & GB_FLAG_HAND) != 0 && d < 1.0;
        float coc = hand ? 0.0 : cocPixels(d);
        if (coc < 0.5) { outScene = vec4(centre, 1.0); return; }
        float rot = blueNoise(px).x * TAU;
        vec3 sum = centre;
        float wsum = 1.0;
        const int N = DOF_SAMPLES;
        for (int i = 0; i < N; i++) {
            float r = sqrt((float(i) + 0.5) / float(N));
            float a = float(i) * GOLDEN_ANGLE + rot;
            vec2 o = r * coc * vec2(cos(a), sin(a));
            vec2 uv = (vec2(px) + 0.5 + o) / vec2(viewWidth, viewHeight);
            float sd = texture(depthtex0, uv).r;
            float sc = cocPixels(sd);
            float reach = smoothstep(r * coc - 1.0, r * coc + 1.0, max(sc, coc * step(sd, d)));
            sum += texture(colortex0, uv).rgb * reach;
            wsum += reach;
        }
        outScene = vec4(sanitizeRadiance(sum / wsum), 1.0);
    #else
        outScene = vec4(centre, 1.0);
    #endif
}
#endif

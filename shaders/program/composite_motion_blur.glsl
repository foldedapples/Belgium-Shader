// composite5 - camera motion blur (optional, MOTION_BLUR). The per-pixel screen velocity
// comes from reprojecting the depth buffer with last frame's camera, scaled by a shutter
// fraction and clamped; the held hand is never blurred.
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/blue_noise.glsl"
#include "/lib/material/gbuffer.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;

in vec2 texCoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outScene;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 centre = texelFetch(colortex0, px, 0).rgb;
    #ifdef MOTION_BLUR
        float d = texelFetch(depthtex0, px, 0).r;
        bool hand = (decodeByte(texelFetch(colortex4, px, 0).a) & GB_FLAG_HAND) != 0 && d < 1.0;
        if (hand) { outScene = vec4(centre, 1.0); return; }
        vec3 scenePos = viewToScene(screenToView(texCoord, d));
        vec2 prevUv = reprojectScene(scenePos).xy;
        // Velocity over one frame, converted to the configured shutter fraction.
        vec2 velocity = (texCoord - prevUv) * MOTION_BLUR_STRENGTH;
        float maxLen = 0.04;
        float len = length(velocity);
        if (len > maxLen) velocity *= maxLen / len;
        if (len * viewWidth < 0.75) { outScene = vec4(centre, 1.0); return; }
        const int N = 8;
        float jitter = blueNoise(px).y;
        vec3 sum = vec3(0.0);
        for (int i = 0; i < N; i++) {
            float t = (float(i) + jitter) / float(N) - 0.5;
            sum += texture(colortex0, clamp(texCoord + velocity * t, vec2(0.0), vec2(1.0))).rgb;
        }
        outScene = vec4(sanitizeRadiance(sum / float(N)), 1.0);
    #else
        outScene = vec4(centre, 1.0);
    #endif
}
#endif

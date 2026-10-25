// Additive emissive overlays: enchantment glint, spider/enderman eyes, beacon beams, lightning
// bolts. Written into colortex5 with ONE ONE blending and zero coverage, so the composite
// overlay (scene*(1-a) + rgb) adds them on top of the lit scene.
#include "/lib/core/common.glsl"
#include "/lib/core/taa_jitter.glsl"

#ifdef STAGE_VERTEX
out vec2 vUv;
out vec4 vColor;
void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    gl_Position = ftransform();
    applyTaaJitter(gl_Position);
}
#endif

#ifdef STAGE_FRAGMENT
uniform sampler2D gtexture;
in vec2 vUv;
in vec4 vColor;

/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 outTranslucent;

void main() {
    #ifdef PROG_LIGHTNING
        vec4 base = vColor;
    #else
        vec4 base = texture(gtexture, vUv) * vColor;
    #endif
    vec3 rgb = srgbToLinear(base.rgb) * base.a;
    #if defined PROG_GLINT
        rgb *= 0.6;
    #elif defined PROG_EYES
        rgb *= 4.0;
    #elif defined PROG_BEAM
        rgb *= 6.0;
    #elif defined PROG_LIGHTNING
        rgb *= 40.0;
    #endif
    outTranslucent = vec4(sanitizeRadiance(rgb), 0.0);
}
#endif

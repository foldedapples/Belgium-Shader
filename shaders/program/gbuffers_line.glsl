// Block selection outline and other line geometry. Rendered as a thin dark overlay into the
// translucent target so it is exposure-independent and never lit.
#include "/lib/core/common.glsl"
#include "/lib/core/taa_jitter.glsl"

#ifdef STAGE_VERTEX
out vec4 vColor;
void main() {
    vColor = gl_Color;
    gl_Position = ftransform();
    applyTaaJitter(gl_Position);
}
#endif

#ifdef STAGE_FRAGMENT
in vec4 vColor;
/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 outTranslucent;
void main() {
    // Straight (non-premultiplied) colour: the blend state multiplies by alpha.
    outTranslucent = vec4(srgbToLinear(vColor.rgb) * 0.02, vColor.a * 0.85);
}
#endif

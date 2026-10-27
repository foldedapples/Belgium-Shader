// Overlays drawn onto existing G-buffer albedo with vanilla blending: enchantment glint
// (additive) and block-breaking cracks (multiplicative).
#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/jitter.glsl"

out vec2 vUv;
out vec4 vColor;

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    gl_Position = applyJitter(ftransform());
}

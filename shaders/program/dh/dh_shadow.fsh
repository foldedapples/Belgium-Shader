#include "/lib/settings.glsl"
#include "/lib/lighting/shadow_proj.glsl"

in vec4 vColor;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outNormal;

void main() {
    vec2 q = gl_FragCoord.xy / float(shadowMapResolution) - cascadeOrigin(3);
    if (any(lessThan(q, vec2(0.0))) || any(greaterThanEqual(q, vec2(0.5)))) discard;
    outColor = vec4(vColor.rgb, 1.0);
    outNormal = vec4(0.5, 0.5, 0.0, 1.0);
}

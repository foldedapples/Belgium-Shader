#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/lighting/shadow_proj.glsl"

uniform sampler2D gtexture;

in vec2 fUv;
in vec4 fColor;
in vec3 fNormal;
flat in int fId;
flat in int fCascade;

/*
const int shadowcolor0Format = RGBA8;
const int shadowcolor1Format = RGBA8;
const bool shadowcolor0Clear = true;
const bool shadowcolor1Clear = true;
*/

// shadowcolor0: rgb caster albedo / translucent tint (sRGB), a = translucent opacity
// shadowcolor1: xy octahedral normal (player space), z = 1 for water, w = 1 for any caster
/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outNormal;

void main() {
    // Keep each triangle inside its own atlas quadrant (no hardware clip planes in Iris).
    vec2 q = gl_FragCoord.xy / float(shadowMapResolution) - cascadeOrigin(fCascade);
    if (any(lessThan(q, vec2(0.0))) || any(greaterThanEqual(q, vec2(0.5)))) discard;

    vec4 albedo = texture(gtexture, fUv) * fColor;
    bool water = fId == MAT_WATER;
    if (water) {
        albedo = vec4(fColor.rgb, 0.1);
    } else if (albedo.a < 0.1) {
        discard;
    }
    #ifndef COLORED_SHADOWS
    if (!water && fId >= 21 && fId <= 26) albedo.rgb = vec3(1.0);
    #endif
    outColor = albedo;
    outNormal = vec4(octEncode(normalize(fNormal)), water ? 1.0 : 0.0, 1.0);
}

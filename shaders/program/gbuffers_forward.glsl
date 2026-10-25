// Forward-lit translucent draws that are not water: particles and weather (rain/snow).
// Output is premultiplied radiance + coverage into colortex5, blended back-to-front with
// SRC_ALPHA ONE_MINUS_SRC_ALPHA / ONE ONE_MINUS_SRC_ALPHA (see shaders.properties), then
// composited over the scene in composite.
#include "/lib/core/common.glsl"
#include "/lib/core/taa_jitter.glsl"
#include "/lib/lighting/forward.glsl"

#ifdef STAGE_VERTEX
out vec2 vUv;
out vec2 vLightmap;
out vec4 vColor;
out vec3 vScenePos;

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 lm = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vLightmap = saturate((lm - 1.0 / 32.0) * (16.0 / 15.0));
    vColor = gl_Color;
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vScenePos = viewToScene(viewPos.xyz);
    gl_Position = gl_ProjectionMatrix * viewPos;
    applyTaaJitter(gl_Position);
}
#endif

#ifdef STAGE_FRAGMENT
uniform sampler2D gtexture;

in vec2 vUv;
in vec2 vLightmap;
in vec4 vColor;
in vec3 vScenePos;

/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 outTranslucent;

void main() {
    vec4 base = texture(gtexture, vUv) * vColor;
    #ifdef PROG_WEATHER
        base.a *= 0.55; // rain streak textures are authored opaque-looking for vanilla
    #endif
    if (base.a < 0.02) discard;
    vec3 albedo = srgbToLinear(base.rgb);
    // Particles are mostly camera-facing quads; light them as if facing the viewer and up.
    vec3 n = safeNormalize(-safeNormalize(vScenePos) + vec3(0.0, 0.5, 0.0));
    vec3 radiance = forwardLighting(albedo, n, vLightmap, vScenePos);
    outTranslucent = vec4(sanitizeRadiance(radiance), base.a);
}
#endif

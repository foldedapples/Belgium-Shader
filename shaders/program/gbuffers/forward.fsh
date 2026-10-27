#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/state.glsl"
#include "/lib/common/gbuffer.glsl"
#include "/lib/material/ids.glsl"
#define ATMOSPHERE_SAMPLERS
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/sky/celestial.glsl"
#include "/lib/lighting/ambient.glsl"
#include "/lib/lighting/emitters.glsl"
#ifdef WORLD_END
#include "/lib/space/end_sky.glsl"
#endif
#ifdef WORLD_NETHER
#include "/lib/nether/nether.glsl"
#endif

uniform sampler2D gtexture;

in vec2 vUv;
in vec2 vLightmap;
in vec4 vColor;
in vec3 vPlayerPos;
in vec3 vNormal;

#ifdef GBUF_WEATHER
/* RENDERTARGETS: 13 */
#else
/* RENDERTARGETS: 0 */
#endif
layout(location = 0) out vec4 outColor;

void main() {
    vec4 tex = texture(gtexture, vUv) * vColor;
    if (tex.a < 0.004) discard;
    vec2 lm = normalizeLightmap(vLightmap);
    vec3 albedo = srgbToLinear(tex.rgb);
    vec3 dir = normalize(vPlayerPos);

    vec3 ambient;
    vec3 sunPart = vec3(0.0);
    #ifdef WORLD_OVERWORLD
    SkyLights L = skyLights();
    vec3 lightIllum = (L.sunIsLight ? vec3(L.sunIllum) : L.moonIllum) * transmittanceToTop(cameraRadius(cameraPosition.y), L.lightDir.y);
    ambient = skyIrradiance(vec3(0.0, 1.0, 0.0)) * skyVisibility(lm.y);
    #elif defined WORLD_END
    vec3 lightIllum = endLightIlluminance();
    ambient = endAmbient(vec3(0.0, 1.0, 0.0));
    #else
    vec3 lightIllum = vec3(0.0);
    ambient = netherAmbient(vec3(0.0, 1.0, 0.0), vPlayerPos + cameraPosition);
    #endif
    vec3 block = blackbody(float(BLOCKLIGHT_TEMPERATURE)) * pow(lm.x, 2.6) * 1.6 * BLOCKLIGHT_STRENGTH;   // as blocklight.glsl

    #ifdef GBUF_WEATHER
    bool snow = biomeSnowy > 0.5;
    #ifdef RAIN_STREAKS
    if (!snow) {
        // Rain drops are tiny lenses: they show the bright sky and lights around them rather than
        // a diffuse colour, with a strong forward glint towards the sun or moon.
        #ifdef WORLD_OVERWORLD
        float glint = pow(saturate(dot(dir, L.lightDir)), 24.0) * 0.6;
        // Streaks show ~40 % of the sky radiance: faint against the sky, visible against dark ground.
        vec3 c = ambient * PI * 0.4 + block * 0.6 + lightIllum * (glint * 0.02 + 0.004) * skyVisibility(lm.y);
        // Lightning flashes light every drop.
        c += vec3(0.7, 0.75, 1.0) * lightningBoltPosition.w * 6.0;
        #else
        vec3 c = ambient * PI * 0.5 + block * 0.6;
        #endif
        float a = tex.a * RAIN_OPACITY * smoothstep(0.0, 2.0, length(vPlayerPos));
        outColor = vec4(c * a, a);
        return;
    }
    #endif
    vec3 c = albedo * (ambient + block + lightIllum * INV_PI * 0.6 * skyVisibility(lm.y));
    float a = tex.a * (snow ? 0.9 : RAIN_OPACITY);
    outColor = vec4(c * a, a);
    #else
    vec3 c = albedo * (ambient + block + lightIllum * INV_PI * 0.5 * skyVisibility(lm.y));
    outColor = vec4(c, tex.a);
    #endif
}

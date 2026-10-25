// Forward-lit translucent draws that are not water: particles and weather (rain/snow).
// Output is premultiplied radiance + coverage into colortex5, blended back-to-front with
// SRC_ALPHA ONE_MINUS_SRC_ALPHA / ONE ONE_MINUS_SRC_ALPHA (see shaders.properties), then
// composited over the scene in composite.
#include "/lib/core/common.glsl"
#include "/lib/core/taa_jitter.glsl"
#include "/lib/lighting/forward.glsl"
#ifdef PROG_WEATHER
    #include "/lib/core/phase_functions.glsl"
    #include "/lib/weather/lightning.glsl"
#endif

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
    #ifdef PROG_WEATHER
        // Rain leans with the wind: shear the vanilla rain sheets (vertical quads around the
        // player) in proportion to height, more in storms. Snow is left vertical (it drifts).
        float lean = RAIN_WIND_TILT * (1.0 + thunderStrength) * (1.0 - biomeSnowSmooth);
        float a = radians(WATER_WIND_ANGLE);
        vScenePos.xz += vec2(cos(a), sin(a)) * lean * vScenePos.y;
        viewPos.xyz = sceneToView(vScenePos);
    #endif
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

#ifdef PROG_WEATHER
// Rain streaks (after Garg & Nayar 2006): a falling drop is a small lens that refracts a wide
// cone of its surroundings (~165 deg) toward the eye, so a streak shows roughly the average
// radiance around it - the sky where it is open, nearby lamps - plus a forward-scattered glint
// when the view points toward the sun or moon. A drop covers a pixel only for part of the
// exposure, so streaks are faint. Before, rain was lit as a white diffuse surface in direct
// sunlight at 55 % opacity, i.e. bright opaque-looking streaks, and equally lit at night.
vec4 rainStreak(float texAlpha, vec3 scenePos, vec2 lightmap) {
    float dist = length(scenePos);
    vec3 viewDir = scenePos / max(dist, 1e-4);
    vec3 env = vec3(0.0);
    #if defined DIM_NETHER
        env = srgbToLinear(fogColor) * 0.3;
    #else
        env = fsSkyIrradianceUp.rgb * INV_PI * dimensionSkyVisibility(lightmap.y);
    #endif
    vec3 blockE = blockLightIrradiance(lightmap.x);
    vec4 chroma = blockLightChroma(scenePos, -viewDir);
    blockE = mix(blockE, luminance(blockE) * chroma.rgb, chroma.a);
    vec3 toHand;
    env += (blockE + handLightIrradiance(scenePos, -viewDir, toHand) + ambientFloor()) * INV_PI;
    vec3 glint = vec3(0.0);
    #ifndef DIM_NETHER
        if (fsLightDir.w >= 0.0) {
            ShadowSample sh = sampleShadowMap(scenePos, -viewDir, lightmap.y, 0.5);
            vec3 lightColor = fsLightColor.rgb;
            #ifdef DIM_OVERWORLD
                lightColor *= cloudShadow(scenePos);
            #endif
            glint = lightColor * sh.light * henyeyGreenstein(dot(viewDir, fsLightDir.xyz), 0.85) * 0.06;
        }
    #endif
    #ifdef DIM_OVERWORLD
        env += lightningIrradiance(scenePos, vec3(0.0, 1.0, 0.0), lightmap.y) * INV_PI;
    #endif
    // Streaks right at the camera are motion-blurred to nothing; far ones lose contrast.
    float alpha = texAlpha * RAIN_OPACITY * smoothstep(0.5, 2.5, dist) * (1.0 - 0.6 * smoothstep(10.0, 48.0, dist));
    return vec4(env * 1.15 + glint, alpha);
}
#endif

void main() {
    vec4 base = texture(gtexture, vUv) * vColor;
    #ifdef PROG_WEATHER
        if (base.a < 0.02) discard;
        vec4 rain = rainStreak(base.a, vScenePos, vLightmap);
        // Snow flakes are opaque ice: diffuse lighting, nearly full opacity.
        vec3 snowRadiance = forwardLighting(srgbToLinear(base.rgb), safeNormalize(-safeNormalize(vScenePos) + vec3(0.0, 0.5, 0.0)), vLightmap, vScenePos);
        float snow = biomeSnowSmooth;
        outTranslucent = vec4(sanitizeRadiance(mix(rain.rgb, snowRadiance, snow)), mix(rain.a, base.a * 0.9, snow));
        return;
    #endif
    if (base.a < 0.02) discard;
    vec3 albedo = srgbToLinear(base.rgb);
    // Particles are mostly camera-facing quads; light them as if facing the viewer and up.
    vec3 n = safeNormalize(-safeNormalize(vScenePos) + vec3(0.0, 0.5, 0.0));
    vec3 radiance = forwardLighting(albedo, n, vLightmap, vScenePos);
    outTranslucent = vec4(sanitizeRadiance(radiance), base.a);
}
#endif

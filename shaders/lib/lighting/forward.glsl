#ifndef LIGHTING_FORWARD_GLSL
#define LIGHTING_FORWARD_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/lighting/surface.glsl"
#include "/lib/lighting/hand_light.glsl"
#define LIGHT_VOLUME_READ
#include "/lib/lighting/floodfill.glsl"
#ifndef DIM_NETHER
    #include "/lib/lighting/shadows.glsl"
#endif
#ifdef DIM_OVERWORLD
    #define CLOUD_SHADOW_READ
    #include "/lib/clouds/cloud_shadow.glsl"
#endif

// Diffuse lighting for forward-rendered translucent surfaces (glass tint, particles, weather).
// Uses the same light, shadow map and sky irradiance as the deferred path.
vec3 forwardLighting(vec3 albedo, vec3 n, vec2 lightmap, vec3 scenePos) {
    vec3 e = vec3(0.0);
    #ifndef DIM_NETHER
    if (fsLightDir.w >= 0.0) {
        float nDotL = dot(n, fsLightDir.xyz);
        ShadowSample sh = sampleShadowMap(scenePos, n, lightmap.y, 0.5);
        vec3 lightColor = fsLightColor.rgb;
        #ifdef DIM_OVERWORLD
            lightColor *= cloudShadow(scenePos);
        #endif
        e += lightColor * sh.light * (max(nDotL, 0.0) * 0.8 + 0.2);
    }
    #endif
    #if defined DIM_NETHER
        e += srgbToLinear(fogColor) * 0.6;
    #else
        e += skyIrradiance(n) * dimensionSkyVisibility(lightmap.y);
    #endif
    vec3 blockE = blockLightIrradiance(lightmap.x);
    vec4 chroma = blockLightChroma(scenePos, n);
    blockE = mix(blockE, luminance(blockE) * chroma.rgb, chroma.a);
    vec3 toHand;
    e += blockE + handLightIrradiance(scenePos, n, toHand) + ambientFloor();
    return albedo * INV_PI * e;
}

#endif

// composite1 - volumetric light at reduced resolution (scale.composite1 = 0.5).
// Marches the view ray through the participating medium (ground fog and rain haze in air,
// water when the camera is submerged) and accumulates single-scattered light from the
// dominant light, shadowed by the shadow map and the cloud shadow map. Underwater the light
// is also attenuated along its own path through the water (from the shadow map's water
// depth) and modulated by the caustic pattern, which produces visible light shafts.
// Output: in-scattered radiance (rgb) into colortex10. Extinction and the unshadowed ambient
// part of the fog are applied analytically elsewhere, so nothing is counted twice.
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/frame_state.glsl"
#include "/lib/core/blue_noise.glsl"
#include "/lib/core/phase_functions.glsl"
#include "/lib/atmosphere/height_fog.glsl"
#include "/lib/water/water_params.glsl"
#ifndef DIM_NETHER
    #include "/lib/lighting/shadow_space.glsl"
    #include "/lib/water/caustics.glsl"
    uniform sampler2DShadow shadowtex1HW;
    uniform sampler2D shadowtex0;
    uniform sampler2D shadowcolor1;
#endif
#ifdef DIM_OVERWORLD
    #define CLOUD_SHADOW_READ
    #include "/lib/clouds/cloud_shadow.glsl"
#endif
#ifdef DIM_END
    #include "/lib/end/end_params.glsl"
#endif
#if WATER_SOURCE == 1 && defined DIM_OVERWORLD && defined UW_SUN_SHAFTS
    #include "/lib/water/water_sim_common.glsl"
    #define HALCYON_HAS_WATER_PLANE
    #define HALCYON_UW_SHAFTS
    #include "/lib/halcyon/halcyon_water_light.glsl"
#endif

uniform sampler2D depthtex0;

/* RENDERTARGETS: 10 */
layout(location = 0) out vec4 outVolumetric;

void main() {
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * 0.5);
    outVolumetric = vec4(0.0, 0.0, 0.0, 1.0);
    #if !defined DIM_NETHER && defined VOLUMETRIC_LIGHT
    if (any(greaterThan(uv, vec2(1.0))) || !frameStateValid() || fsLightDir.w < 0.0) return;

    float depth = texelFetch(depthtex0, ivec2(uv * vec2(viewWidth, viewHeight)), 0).r;
    vec3 viewPos = screenToView(uv, depth >= 1.0 ? 1.0 : depth);
    vec3 scenePos = viewToScene(viewPos);
    vec3 dir = normalize(scenePos);
    bool underwater = isEyeInWater == 1;
    float maxDist = underwater ? VL_WATER_DISTANCE : VL_DISTANCE;
    float dist = depth >= 1.0 ? maxDist : min(length(viewPos), maxDist);

    #if WATER_SOURCE == 1 && defined DIM_OVERWORLD && defined UW_SUN_SHAFTS
    if (underwater) {
        // Halcyon's underwater sun shafts: refracted sunlight through Belgium's water medium,
        // shadowed by the shadow map and focused by Halcyon's caustics (Caustics Mode 2).
        float j = blueNoise(ivec2(gl_FragCoord.xy)).z;
        outVolumetric = vec4(sanitizeRadiance(halcyonUnderwaterShafts(viewPos, j)), 1.0);
        return;
    }
    #endif
    const int STEPS = VL_STEPS;
    float dt = dist / float(STEPS);
    float jitter = blueNoise(ivec2(gl_FragCoord.xy)).z;
    vec3 l = fsLightDir.xyz;
    float cosTheta = dot(dir, l);
    vec3 ext = waterExtinction();
    vec3 scat = waterScattering();
    float phase = underwater ? mix(henyeyGreenstein(cosTheta, 0.7), 0.25 * INV_PI, 0.3)
                             : mix(henyeyGreenstein(cosTheta, 0.6), 0.25 * INV_PI, 0.35);

    vec3 sum = vec3(0.0);
    vec3 T = vec3(1.0);
    for (int i = 0; i < STEPS; i++) {
        float t = (float(i) + jitter) * dt;
        vec3 p = dir * t;
        vec3 clip = sceneToShadowClip(p);
        float vis = 1.0;
        float waterAbove = 0.0;
        // Outside the map the visibility is unknown. Treating it as lit made a hard lit/shadowed
        // boundary on the map's side planes; those planes contain the light direction, so on
        // screen it showed as a bright line through the sun (seen in game). Fade to the
        // unshadowed value over the outer part of the map, like the surface lookup does.
        float coverage = (1.0 - smoothstep(0.85, 0.97, maxOf(abs(clip.xy)))) * (1.0 - smoothstep(0.9, 1.0, abs(clip.z)));
        if (coverage > 0.0) {
            vec3 tc = shadowClipToTexture(clip);
            vis = mix(1.0, texture(shadowtex1HW, tc), coverage);
            if (texture(shadowcolor1, tc.xy).r > 0.5) waterAbove = max(tc.z - texture(shadowtex0, tc.xy).r, 0.0) * 2.0 * SHADOW_DEPTH_HALF * coverage;
        }
        #ifdef DIM_OVERWORLD
            vis *= cloudShadow(p);
        #endif
        vec3 sigmaS, sigmaT;
        if (underwater) {
            sigmaS = scat; sigmaT = ext;
            vec3 lightT = exp(-ext * waterAbove);
            // Shafts: the surface focuses light into moving bands.
            float c = waterAbove > 0.0 ? causticFactor(cameraPosition + p, l, waterAbove, 0.6, 0.0) : 1.0;
            vis *= c;
            sum += T * sigmaS * lightT * vis * dt;
        } else {
            #ifdef DIM_END
                // The End's haze (same extinction as endFog) is dark dust: only a small part of
                // the black hole's light is scattered toward the camera. Before, the End used
                // the Overworld's ground-fog model (morning mist from a day clock the End does
                // not have), which made strong shafts and a bright band at the horizon.
                sigmaT = vec3(endHazeExtinction());
                sigmaS = sigmaT * END_HAZE_ALBEDO;
            #else
                float k = heightFogDensityAt(cameraPosition.y + p.y);
                sigmaS = vec3(k); sigmaT = vec3(k);
            #endif
            sum += T * sigmaS * vis * dt;
        }
        T *= exp(-sigmaT * dt);
    }
    vec3 radiance = sum * fsLightColor.rgb * phase * VL_STRENGTH;
    outVolumetric = vec4(sanitizeRadiance(radiance), 1.0);
    #endif
}
#endif

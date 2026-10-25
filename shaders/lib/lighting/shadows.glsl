#ifndef LIGHTING_SHADOWS_GLSL
#define LIGHTING_SHADOWS_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/lighting/shadow_space.glsl"

// Shadow-map visibility for a receiver (ORIGINAL_ARCHITECTURE.md sec. 4).
// Tiers (SHADOW_FILTER): 0 hardware 2x2, 1 8-tap PCF, 2 16-tap PCF,
//                        3 blocker search + 16 taps, 4 blocker search + 32 taps.

uniform sampler2DShadow shadowtex0HW;
uniform sampler2DShadow shadowtex1HW;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

struct ShadowSample {
    vec3  light;        // visibility including translucent tint (0..1 per channel)
    float opaque;       // visibility against opaque casters only
    float waterDepth;   // blocks of water between the receiver and the light (0 if none)
    float thickness;    // blocks between the receiver and the first opaque caster (for SSS)
    float coverage;     // 1 inside the shadow map, fades to 0 at its edge
};

vec2 vogelDisk(int i, int n, float rotation) {
    float r = sqrt((float(i) + 0.5) / float(n));
    float a = float(i) * GOLDEN_ANGLE + rotation;
    return r * vec2(cos(a), sin(a));
}

// Fallback visibility where the shadow map has no data: open sky light is a good proxy for an
// unobstructed sky above.
float lightmapShadow(float skyLight) { return smoothstep(0.82, 0.97, skyLight); }

float worldToShadowDepth(float blocks) { return blocks / (2.0 * SHADOW_DEPTH_HALF); }

ShadowSample sampleShadowMap(vec3 scenePos, vec3 geoNormal, float skyLight, float noise) {
    ShadowSample s;
    s.light = vec3(1.0); s.opaque = 1.0; s.waterDepth = 0.0; s.thickness = 64.0; s.coverage = 0.0;

    vec3 L = fsLightDir.xyz;
    float nDotL = dot(geoNormal, L);

    // Normal-offset bias scaled by the local texel footprint: grows towards the map edge and
    // at grazing light, which removes acne without detaching contact shadows.
    vec3 clip0 = sceneToShadowClip(scenePos);
    float texel = shadowTexelWorld(clip0.xy);
    float grazing = 1.0 - saturate(abs(nDotL));
    vec3 biased = scenePos + geoNormal * texel * (0.9 + 1.6 * grazing) * sign(nDotL + 1e-4)
                           + L * texel * 0.35;
    vec3 clip = sceneToShadowClip(biased);

    float edge = maxOf(abs(clip.xy));
    s.coverage = 1.0 - smoothstep(0.88, 0.98, edge);
    if (s.coverage <= 0.0 || abs(clip.z) >= 1.0) {
        float v = lightmapShadow(skyLight);
        s.light = vec3(v); s.opaque = v; s.coverage = 0.0;
        return s;
    }

    vec3 tc = shadowClipToTexture(clip);
    float stretch = shadowRadialStretch(length(clip.xy));
    float texelUv = 1.0 / float(shadowMapResolution);
    float rot = noise * TAU;

    // Filter radius in world blocks -> texture units at this point of the distorted map.
    float worldRadius = 0.035 * SHADOW_SOFTNESS;
    #if SHADOW_FILTER >= 3
    {
        const int BLOCKERS = SHADOW_FILTER >= 4 ? 12 : 8;
        float searchWorld = 1.2 * SHADOW_SOFTNESS;
        float searchUv = searchWorld / shadowDistance * 0.5 * stretch;
        float sum = 0.0, count = 0.0;
        for (int i = 0; i < BLOCKERS; i++) {
            vec2 o = vogelDisk(i, BLOCKERS, rot) * searchUv;
            float d = texture(shadowtex1, tc.xy + o).r;
            if (d < tc.z) { sum += d; count += 1.0; }
        }
        if (count > 0.0) {
            float blockerBlocks = (tc.z - sum / count) * 2.0 * SHADOW_DEPTH_HALF;
            // Penumbra from the light's angular radius (the sun or moon disk).
            float lightRadius = max(fsCelestialAxis.w, 0.004);
            worldRadius = max(worldRadius * 0.4, blockerBlocks * tan(lightRadius) * 1.6 * SHADOW_SOFTNESS);
            worldRadius = min(worldRadius, 0.9 * SHADOW_SOFTNESS);
        }
    }
    #endif
    float radiusUv = max(worldRadius / shadowDistance * 0.5 * stretch, texelUv * 0.75);

    #if SHADOW_FILTER == 0
        const int TAPS = 1;
    #elif SHADOW_FILTER == 1
        const int TAPS = 8;
    #elif SHADOW_FILTER == 4
        const int TAPS = 32;
    #else
        const int TAPS = 16;
    #endif

    float visOpaque = 0.0, visAll = 0.0;
    for (int i = 0; i < TAPS; i++) {
        vec2 o = TAPS == 1 ? vec2(0.0) : vogelDisk(i, TAPS, rot) * radiusUv;
        vec3 p = vec3(tc.xy + o, tc.z);
        visOpaque += texture(shadowtex1HW, p);
        // Always compared: water detection (attenuation, caustics) needs it even when
        // coloured shadows are off.
        visAll += texture(shadowtex0HW, p);
    }
    visOpaque /= float(TAPS);
    visAll /= float(TAPS);

    // Something translucent sits between receiver and light where visAll < visOpaque.
    vec3 light = vec3(visOpaque);
    float translucentShare = saturate(visOpaque - visAll);
    if (translucentShare > 0.0) {
        vec3 tint = texture(shadowcolor0, tc.xy).rgb;
        float isWater = texture(shadowcolor1, tc.xy).r;
        float frontDepth = texture(shadowtex0, tc.xy).r;
        if (isWater > 0.5) {
            s.waterDepth = max(tc.z - frontDepth, 0.0) * 2.0 * SHADOW_DEPTH_HALF;
            tint = vec3(1.0); // water attenuation is applied by the caller from waterDepth
        }
        #ifndef COLORED_SHADOWS
            tint = vec3(1.0);  // translucent casters do not shade when coloured shadows are off
        #endif
        light = vec3(visAll) + translucentShare * tint;
    }

    float occluder = texture(shadowtex1, tc.xy).r;
    s.thickness = max(tc.z - occluder, 0.0) * 2.0 * SHADOW_DEPTH_HALF;

    // Blend to the lightmap proxy near the edge of the shadow distance.
    float fallback = lightmapShadow(skyLight);
    s.light = mix(vec3(fallback), light, s.coverage);
    s.opaque = mix(fallback, visOpaque, s.coverage);
    return s;
}

#endif

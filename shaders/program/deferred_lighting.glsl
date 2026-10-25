// deferred4 - opaque lighting and sky for every pixel -> colortex0 (absolute HDR radiance).
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/buffers.glsl"
#include "/lib/compat/lod.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/core/blue_noise.glsl"
#include "/lib/core/phase_functions.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/material/gbuffer.glsl"
#include "/lib/material/labpbr.glsl"
#include "/lib/lighting/surface.glsl"
#include "/lib/weather/wetness.glsl"
#include "/lib/weather/lightning.glsl"
#include "/lib/reflections/reflection_policy.glsl"
#include "/lib/lighting/screen_space.glsl"
#include "/lib/lighting/hand_light.glsl"
#define LIGHT_VOLUME_READ
#include "/lib/lighting/floodfill.glsl"
#ifndef DIM_NETHER
    #include "/lib/lighting/shadows.glsl"
    #include "/lib/water/caustics.glsl"
#endif
#ifdef DIM_OVERWORLD
    #include "/lib/sky/sky_render.glsl"
    #include "/lib/atmosphere/fog.glsl"
    #include "/lib/clouds/cirrus.glsl"
    #include "/lib/sky/aurora.glsl"
    #include "/lib/sky/rainbow.glsl"
    #if SKY_SOURCE == 1
        #define HALCYON_SKY_RENDER
        #include "/lib/halcyon/halcyon_sky.glsl"
    #endif
    #include "/lib/atmosphere/height_fog.glsl"
    #define CLOUD_SHADOW_READ
    #include "/lib/clouds/cloud_shadow.glsl"
    #ifdef VOLUMETRIC_CLOUDS
        uniform sampler2D colortex9;
    #endif
#endif
#ifdef DIM_END
    #include "/lib/end/end_sky.glsl"
#else
    // spaceBackground() for end portals
    #include "/lib/end/black_hole.glsl"
#endif
#ifdef DIM_NETHER
    #include "/lib/nether/nether_atmosphere.glsl"
#endif

#include "/lib/atmosphere/atmosphere_chain.glsl"

uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
#ifdef SSGI
uniform sampler2D colortex13;
#endif

in vec2 texCoord;

#if DEBUG_VIEW == DBG_SHADOW || DEBUG_VIEW == DBG_DIRECT || DEBUG_VIEW == DBG_INDIRECT || DEBUG_VIEW == DBG_AO || DEBUG_VIEW == DBG_LIGHT_VOLUME || DEBUG_VIEW == DBG_GI
    #define DEFERRED_WRITES_DEBUG
#endif
// With SSGI, colortex14 receives the sun/sky-lit diffuse radiance of each opaque surface
// (no block light, emission or atmosphere): next frame's SSGI bounces only light the vanilla
// lightmap does not already account for.
#if defined DEFERRED_WRITES_DEBUG && defined SSGI
/* RENDERTARGETS: 0,14,11 */
layout(location = 1) out vec4 outBounce;
layout(location = 2) out vec4 outDebug;
#elif defined DEFERRED_WRITES_DEBUG
/* RENDERTARGETS: 0,11 */
vec4 outBounce;
layout(location = 1) out vec4 outDebug;
#elif defined SSGI
/* RENDERTARGETS: 0,14 */
layout(location = 1) out vec4 outBounce;
vec4 outDebug;
#else
/* RENDERTARGETS: 0 */
vec4 outBounce;
vec4 outDebug;
#endif
layout(location = 0) out vec4 outScene;

float pixelAngularSize() { return 2.0 / max(gbufferProjection[1][1] * viewHeight, 1.0); }

vec3 renderSky(vec3 dir) {
    #if defined DIM_OVERWORLD && SKY_SOURCE == 1
        return halcyonSkyRadiance(dir, true);
    #elif defined DIM_OVERWORLD
        bool moonCovers;
        vec3 objects = celestialRadiance(dir, pixelAngularSize(), moonCovers);
        vec3 sky = skyRadiance(dir) + viewTransmittance(dir) * objects;
        bool sunUp = fsSunDir.y > -0.12;
        vec4 ci = cirrusLayer(dir, sunUp ? fsSunDir.xyz : fsMoonDir.xyz,
                              sunUp ? fsSunIrradiance.rgb : fsMoonIrradiance.rgb, fsSkyIrradianceUp.rgb,
                              pixelAngularSize(), CIRRUS_AMOUNT, 1.0);
        sky = sky * ci.a + ci.rgb;
        #ifdef AURORA
            sky += auroraRadiance(dir, blueNoise(ivec2(gl_FragCoord.xy)).w) * viewTransmittance(dir) * ci.a;
        #endif
        sky += rainbowRadiance(dir, fsSunIrradiance.rgb * viewTransmittance(fsSunDir.xyz), cloudShadow(vec3(0.0)), fsWeather.z * biomePrecipSmooth, 1.0);
        return sky;
    #elif defined DIM_END
        return endSkyRadiance(dir, pixelAngularSize());
    #else
        return netherSkyRadiance(dir);
    #endif
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    float vanillaDepth = texelFetch(depthtex0, px, 0).r;
    ScenePoint sp = scenePoint(texCoord, vanillaDepth, px, true);
    float depth = sp.sky ? 1.0 : min(sp.depth, 0.999999);
    vec3 viewPos = sp.view;
    vec3 scenePos = sp.scene;
    float dist = sp.dist;
    vec3 viewDir = scenePos / max(dist, EPSILON);
    outDebug = vec4(0.0);
    outBounce = vec4(0.0);

    #if defined DIM_OVERWORLD && defined VOLUMETRIC_CLOUDS
        vec4 clouds = texelFetch(colortex9, px, 0);
    #else
        vec4 clouds = vec4(0.0, 0.0, 0.0, 1.0);
    #endif

    if (depth >= 1.0 || !frameStateValid()) {
        vec3 sky = frameStateValid() ? renderSky(viewDir) : vec3(0.0);
        sky = sky * clouds.a + clouds.rgb;
        outScene = vec4(sanitizeRadiance(sky), 1.0);
        return;
    }

    GBufferData g = decodeGBuffer(texelFetch(colortex1, px, 0), texelFetch(colortex2, px, 0),
                                  texelFetch(colortex3, px, 0), texelFetch(colortex4, px, 0));
    Material m = decodeMaterial(g.albedo, g.specular, g.ao, g.material);
    vec3 n = g.normal;
    #ifndef DIM_NETHER
    {
        // Rain: wet materials, puddles and drop ripples (not on entities, the hand or LODs).
        vec3 worldPos = cameraPosition + scenePos;
        bool wettable = (g.flags & (GB_FLAG_HAND | GB_FLAG_ENTITY)) == 0 && g.material != MAT_LAVA;
        float wet = wettable ? surfaceWetness(g.geoNormal, g.lightmap.y) : 0.0;
        float puddle = ((g.flags & GB_FLAG_LOD) != 0 ? 0.0 : puddleMask(worldPos, g.geoNormal, wet));
        applyWetness(m, n, g.geoNormal, wet, puddle, worldPos);
    }
    #endif
    vec3 v = -viewDir;
    float nDotV = max(dot(n, v), 1e-3);
    vec4 noise = blueNoise(px);

    // ---------------------------------------------------------------- direct light
    vec3 direct = vec3(0.0);
    float shadowVis = 1.0;
    #ifndef DIM_NETHER
    if (fsLightDir.w >= 0.0) {
        vec3 l = fsLightDir.xyz;
        ShadowSample sh = sampleShadowMap(scenePos, g.geoNormal, g.lightmap.y, noise.x);
        shadowVis = luminance(sh.light);
        vec3 diffuse, specular;
        evaluateDirectBrdf(m, n, v, l, diffuse, specular);
        // A normal map must not light faces the geometry hides from the light.
        float geoTerm = smoothstep(-0.05, 0.1, dot(g.geoNormal, l));
        vec3 lightColor = fsLightColor.rgb;
        #ifdef DIM_OVERWORLD
            lightColor *= cloudShadow(scenePos);
        #endif
        #ifdef CONTACT_SHADOWS
            if ((g.flags & (GB_FLAG_HAND | GB_FLAG_LOD)) == 0 && dist < 48.0) {
                float cs = contactShadow(viewPos, normalize(sceneToViewDir(l)), depthtex0, noise.w);
                sh.light *= cs; sh.opaque *= cs;
            }
        #endif
        direct = lightColor * sh.light * (diffuse + specular) * geoTerm;
        if (sh.waterDepth > 0.0) {
            // Lit through water: Beer-Lambert along the light path and caustics.
            vec3 worldPos = cameraPosition + scenePos;
            float footprint = dist * pixelAngularSize();
            direct *= exp(-waterExtinction() * sh.waterDepth)
                    * causticFactor(worldPos, l, sh.waterDepth, waterOpenness(1.0), footprint);
        }

        #ifdef SUBSURFACE_SCATTERING
        float sss = max(m.sss, (g.flags & GB_FLAG_SSS) != 0 ? 0.6 : 0.0);
        if (sss > 0.0) {
            // Light diffusing through thin material: attenuated by the thickness the shadow map
            // sees, strongest when looking toward the light (forward scattering).
            float transmit = exp(-sh.thickness * 3.2 / sss) * sh.opaque * 0.5 + exp(-sh.thickness * 1.2 / sss) * 0.5;
            float phase = mix(0.25, 1.0, henyeyGreenstein(dot(l, -v), 0.45) * 4.0 * PI * 0.25);
            direct += lightColor * m.albedo * INV_PI * sss * transmit * phase * saturate(1.0 - sh.waterDepth);
        }
        #endif
    }
    #endif

    // ---------------------------------------------------------------- ambient light
    float skyVis = dimensionSkyVisibility(g.lightmap.y);
    // Environment (sky, or the Nether's haze) and local (block, hand, floor, lightning) parts
    // are kept apart: SSGI corrects only the environment part for occlusion.
    #if defined DIM_NETHER
        vec3 envE = netherAmbientIrradiance(n);
    #else
        vec3 envE = skyIrradiance(n) * skyVis;
    #endif
    // Block light: vanilla lightmap intensity, coloured by the flood-filled light volume.
    vec3 blockE = blockLightIrradiance(g.lightmap.x);
    vec4 chroma = blockLightChroma(scenePos, g.geoNormal);
    blockE = mix(blockE, luminance(blockE) * chroma.rgb, chroma.a);
    vec3 toHand;
    vec3 handE = handLightIrradiance(scenePos, n, toHand);
    vec3 localE = blockE + handE + ambientFloor() + lightningIrradiance(scenePos, n, g.lightmap.y);
    float ssao = 1.0;
    #ifdef SSAO
        if ((g.flags & (GB_FLAG_HAND | GB_FLAG_LOD)) == 0) ssao = screenSpaceAO(viewPos, normalize(sceneToViewDir(g.geoNormal)), depthtex0, noise.xy);
    #endif
    vec3 diffuseBrdf = m.albedo * INV_PI * diffuseWeight(m) * m.ao;

    // Screen-space bounce light (half resolution, denoised in deferred3). Signed: bounce
    // radiance from hit surfaces minus the environment light those surfaces block.
    vec3 giE = vec3(0.0);
    #ifdef SSGI
    if ((g.flags & (GB_FLAG_HAND | GB_FLAG_LOD)) == 0) {
        vec2 halfSize = vec2(viewWidth, viewHeight) * 0.5;
        vec2 lp = texCoord * halfSize - 0.5;
        ivec2 base = ivec2(floor(lp));
        vec2 f = lp - vec2(base);
        vec3 sum = vec3(0.0), nearest = vec3(0.0);
        float wsum = 0.0, best = 1e9;
        for (int y = 0; y <= 1; y++) for (int x = 0; x <= 1; x++) {
            ivec2 q = clamp(base + ivec2(x, y), ivec2(0), ivec2(halfSize) - 1);
            vec4 h = texelFetch(colortex13, q, 0);
            float rel = abs(h.a - dist) / max(dist * 0.03, 0.05);
            float wb = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y);
            float w = wb * exp(-rel);
            sum += h.rgb * w; wsum += w;
            if (rel < best) { best = rel; nearest = h.rgb; }
        }
        // No tap on this surface (thin geometry, silhouettes): use the closest one only if
        // it is plausibly the same surface, otherwise no bounce.
        vec3 gi = wsum > 1e-3 ? sum / wsum : (best < 3.0 ? nearest : vec3(0.0));
        // Saturation about luminance without clamping (the value is signed).
        float gl = luminance(gi);
        giE = (vec3(gl) + (gi - vec3(gl)) * CP_GI_SATURATION) * SSGI_STRENGTH;
    }
    #endif
    vec3 envDiffuseE = max(envE * ssao + giE, 0.0);
    vec3 diffuseAmbient = diffuseBrdf * (envDiffuseE + localE * ssao);

    // Directional block and hand light: a specular highlight on smooth, wet and metal
    // surfaces, oriented by the light volume's gradient (blocks) or the hand position.
    vec3 blockSpecular = vec3(0.0);
    {
        vec4 bdir = blockLightDirection(scenePos, g.geoNormal);
        vec3 bd, bs;
        if (bdir.w > 0.0) {
            // SSR surfaces already reflect the emitters themselves (composite).
            evaluateDirectBrdf(m, n, v, bdir.xyz, bd, bs);
            if (!usesScreenSpaceReflection(m, g.flags)) blockSpecular += blockE * bs * bdir.w;
        }
        if (dot(handE, handE) > 0.0) {
            // bs already contains the cosine: divide out the diffuse wrap baked into handE.
            evaluateDirectBrdf(m, n, v, toHand, bd, bs);
            blockSpecular += handE / max(handLightFacing(n, toHand), 0.3) * bs;
        }
        blockSpecular *= m.ao;
    }

    vec3 specularAmbient = vec3(0.0);
    {
        vec3 r = reflect(-v, n);
        #if defined DIM_OVERWORLD
            vec3 env = skyRadiance(normalize(vec3(r.x, max(r.y, 0.02), r.z)));
            env = mix(env, (fsSkyIrradianceUp.rgb + fsSkyIrradianceSide.rgb) * 0.5 * INV_PI, sqrt(m.roughness));
            env *= skyVis;
        #else
            vec3 env = envE * INV_PI;   // block and hand light have their own highlights
        #endif
        // Horizon occlusion: reflections below the geometric surface are blocked.
        float horizon = saturate(1.0 + 1.2 * dot(r, g.geoNormal));
        specularAmbient = env * min(environmentReflectance(m, nDotV) * CP_REFLECTION, vec3(1.0)) * horizon * horizon * m.ao * ssao;
        // Surfaces handled by screen-space reflections get their specular in composite.
        if (usesScreenSpaceReflection(m, g.flags)) specularAmbient = vec3(0.0);
    }

    vec3 emission = m.albedo * m.emission * 5.0 * EMISSION_INTENSITY;
    if (g.material == MAT_END_PORTAL) {
        // End portals and gateways: a window into deep space, seen along the view ray, with a
        // faint violet glow. Replaces the vanilla portal effect, which needs vanilla shaders.
        vec3 space = spaceBackground(viewDir, pixelAngularSize()) * 40.0;
        float glow = 0.5 + 0.5 * sin(frameTimeCounter * 0.7 + dot(cameraPosition + scenePos, vec3(0.3, 0.1, 0.2)));
        emission = space + vec3(0.25, 0.1, 0.45) * (0.08 + 0.04 * glow) * EMISSION_INTENSITY;
        diffuseAmbient = vec3(0.0); specularAmbient *= 0.2; direct = vec3(0.0);
    }

    vec3 radiance = direct + diffuseAmbient + specularAmbient + blockSpecular + emission;
    outBounce = vec4(sanitizeRadiance(direct + diffuseBrdf * envDiffuseE), 1.0);

    // ---------------------------------------------------------------- atmosphere
    // An underwater camera looks through water, not air: composite applies water fog instead.
    if (isEyeInWater != 1) {
        radiance = applyAtmosphere(radiance, scenePos, dist, viewDir);
        #if defined DIM_OVERWORLD
            #if SKY_SOURCE == 0
            // Belgium's rainbow also forms in front of distant terrain; Halcyon's is sky-only.
            radiance += rainbowRadiance(viewDir, fsSunIrradiance.rgb * viewTransmittance(fsSunDir.xyz), cloudShadow(vec3(0.0)),
                                        fsWeather.z * biomePrecipSmooth, smoothstep(24.0, 160.0, dist));
            #endif
            radiance = radiance * clouds.a + clouds.rgb;
        #endif
    }

    #if DEBUG_VIEW == DBG_SHADOW
        outDebug = vec4(vec3(shadowVis), 1.0);
    #elif DEBUG_VIEW == DBG_DIRECT
        outDebug = vec4(direct, 1.0);
    #elif DEBUG_VIEW == DBG_INDIRECT
        outDebug = vec4(diffuseAmbient + specularAmbient, 1.0);
    #elif DEBUG_VIEW == DBG_GI
        outDebug = vec4(giE, 1.0);
    #elif DEBUG_VIEW == DBG_AO
        outDebug = vec4(vec3(ssao * m.ao), 1.0);
    #elif DEBUG_VIEW == DBG_LIGHT_VOLUME
        outDebug = vec4(chroma.rgb * chroma.a / max(maxOf(chroma.rgb), 1e-3), 1.0);
    #endif

    outScene = vec4(sanitizeRadiance(radiance), 1.0);
}
#endif

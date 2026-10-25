// composite - water surfaces, underwater view and the translucent overlay.
//
// From above: Fresnel blend of (refracted scene x water transmittance + in-scatter) and the
// reflection (screen-space trace against opaque depth, falling back to the sky), plus the
// sun's specular highlight. From below: Snell's window with total internal reflection, and
// underwater fog over every path. Translucent forward surfaces are composited last.
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/frame_state.glsl"
#include "/lib/core/blue_noise.glsl"
#include "/lib/lighting/brdf.glsl"
#include "/lib/lighting/surface.glsl"
#include "/lib/water/water_params.glsl"
#include "/lib/water/water_record.glsl"
#include "/lib/water/waves.glsl"
#include "/lib/post/color_profile.glsl"
#include "/lib/lighting/hand_light.glsl"
#define LIGHT_VOLUME_READ
#include "/lib/lighting/floodfill.glsl"
#include "/lib/water/water_sim_common.glsl"
#if DEBUG_VIEW == DBG_WATER_HEIGHT || DEBUG_VIEW == DBG_WATER_VELOCITY
    #include "/lib/water/water_sim_sample.glsl"
#endif
#include "/lib/reflections/ssr.glsl"
#include "/lib/compat/lod.glsl"
#include "/lib/reflections/reflection_policy.glsl"
#include "/lib/material/gbuffer.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/weather/wetness.glsl"
#ifndef DIM_NETHER
    #include "/lib/lighting/shadows.glsl"
#endif
#ifdef DIM_OVERWORLD
    #include "/lib/sky/sky_render.glsl"
    #include "/lib/atmosphere/fog.glsl"
    #include "/lib/atmosphere/height_fog.glsl"
    #if SKY_SOURCE == 1
        #define HALCYON_SKY_RENDER
        #include "/lib/halcyon/halcyon_sky.glsl"
    #endif
    #define CLOUD_SHADOW_READ
    #include "/lib/clouds/cloud_shadow.glsl"
#endif
#ifdef DIM_END
    #include "/lib/end/end_sky.glsl"
#endif
#ifdef DIM_NETHER
    #include "/lib/nether/nether_atmosphere.glsl"
#endif
#include "/lib/atmosphere/atmosphere_chain.glsl"
#if defined DIM_OVERWORLD && defined VOLUMETRIC_CLOUDS
    uniform sampler2D colortex9;
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex5;
#ifdef OPAQUE_SSR
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
#endif
uniform sampler2D colortex6;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

in vec2 texCoord;

#if DEBUG_VIEW == DBG_REFLECTIONS || DEBUG_VIEW == DBG_WATER_HEIGHT || DEBUG_VIEW == DBG_WATER_VELOCITY
/* RENDERTARGETS: 0,11 */
layout(location = 1) out vec4 outDebug;
#else
/* RENDERTARGETS: 0 */
vec4 outDebug;
#endif
layout(location = 0) out vec4 outScene;

vec3 environment(vec3 dir) {
    #if defined DIM_OVERWORLD && SKY_SOURCE == 1
        // Halcyon's reflection sky: atmosphere, plus the aurora with Aurora in Reflections.
        return halcyonSkyRadiance(normalize(vec3(dir.x, max(dir.y, 0.01), dir.z)), false);
    #elif defined DIM_OVERWORLD
        return skyRadiance(normalize(vec3(dir.x, max(dir.y, 0.01), dir.z)));
    #elif defined DIM_END
        return endSkyRadiance(dir, 0.001);
    #else
        return netherSkyRadiance(dir);
    #endif
}

// Light reaching water near the surface: sky dome (occluded by sky light) plus the direct
// light through the surface.
vec3 waterAmbient(float skyLight, float sunVisibility) {
    vec3 e = vec3(0.0);
    #if defined DIM_NETHER
        e = netherAmbientIrradiance(vec3(0.0, 1.0, 0.0));
    #else
        e = fsSkyIrradianceUp.rgb * skyVisibility(skyLight);
        if (fsLightDir.w >= 0.0) e += fsLightColor.rgb * max(fsLightDir.y, 0.0) * sunVisibility * dimensionSkyVisibility(skyLight);
    #endif
    return e + ambientFloor();
}

// Depth of the camera below the water surface, from the water plane the simulation tracks;
// 2 blocks when no plane is known yet.
float cameraDepthBelowSurface() {
    if (wsHeader.x == WS_VERSION) return max(wsPlane.x - cameraPosition.y, 0.0);
    return 2.0;
}

// Environment seen by a reflection ray that leaves the screen. Matches deferred lighting:
// the sky (occluded by sky light) in the Overworld, the ambient irradiance elsewhere.
vec3 environmentFallback(vec3 dir, float skyLight) {
    #if defined DIM_OVERWORLD
        return environment(dir) * skyVisibility(skyLight);
    #elif defined DIM_END
        return skyIrradiance(dir) * INV_PI;
    #else
        return netherAmbientIrradiance(dir) * INV_PI;
    #endif
}

vec4 cloudsAt(vec2 uv) {
    #if defined DIM_OVERWORLD && defined VOLUMETRIC_CLOUDS
        return texture(colortex9, uv);
    #else
        return vec4(0.0, 0.0, 0.0, 1.0);
    #endif
}

// colortex0 holds radiance after the atmosphere and clouds between the camera and the
// surface (deferred lighting). Undo both to recover the radiance leaving the surface.
vec3 removeAtmosphere(vec3 c, vec2 uv, vec3 scenePos, float dist) {
    vec4 cl = cloudsAt(uv);
    c = (c - cl.rgb) / max(cl.a, 0.05);
    vec3 T, S;
    atmosphereTerms(scenePos, dist, scenePos / max(dist, EPSILON), T, S);
    return max((c - S) / max(T, vec3(0.05)), vec3(0.0));
}

vec3 reflectionAt(vec3 viewPos, vec3 viewDirReflected, vec3 sceneDirReflected, float skyLight, float jitter, out float hitConfidence) {
    vec3 env = environmentFallback(sceneDirReflected, skyLight);
    SsrResult s = traceScreenSpace(viewPos, viewDirReflected, depthtex1, SSR_STEPS, jitter);
    hitConfidence = s.hit ? s.confidence : 0.0;
    if (!s.hit) return env;
    vec3 hitColor = texture(colortex0, s.uv).rgb;
    return mix(env, hitColor, s.confidence);
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 scene = texelFetch(colortex0, px, 0).rgb;
    vec4 waterData = texelFetch(colortex6, px, 0);
    float d0 = texelFetch(depthtex0, px, 0).r;
    float d1 = texelFetch(depthtex1, px, 0).r;
    bool water = waterData.a > 0.5;
    vec2 waterLm;
    bool lodWaves;
    unpackWaterLight(waterData.b, waterLm, lodWaves);
    vec4 noise = blueNoise(px);
    outDebug = vec4(0.0);

    // LOD surfaces (water and terrain) live in their own depth buffers.
    ScenePoint p0 = scenePoint(texCoord, d0, px, false);
    ScenePoint p1 = scenePoint(texCoord, d1, px, true);
    if (!p0.sky) d0 = min(p0.depth, 0.999999);
    if (!p1.sky) d1 = min(p1.depth, 0.999999);
    vec3 view0 = p0.view;
    vec3 view1 = p1.view;
    vec3 scene0 = p0.scene;
    float dist0 = p0.dist;
    float dist1 = p1.sky ? far * 2.0 : p1.dist;
    vec3 dir = scene0 / max(dist0, EPSILON);
    vec3 ext = waterExtinction();

    if (isEyeInWater == 1) {
        // ------------------------------------------------------------ underwater view
        float pathLen = water ? dist0 : dist1;
        vec3 surfaceColor = scene;
        float skyLight = water ? waterLm.y : float(eyeBrightnessSmooth.y) / 240.0;
        if (water) {
            vec3 n = decodeUnitVector(waterData.rg);
            vec3 nBelow = -n;
            float cosI = saturate(dot(-dir, nBelow));
            float F = fresnelDielectric(cosI, 1.0 / WATER_IOR);
            vec3 t = refract(dir, nBelow, WATER_IOR);
            vec3 above = environment(dir);
            if (dot(t, t) > 0.0) {
                vec3 tv = sceneToViewDir(t);
                vec3 p = viewToScreen(view0 + tv * 6.0);
                vec2 uv = clamp(p.xy, vec2(0.001), vec2(0.999));
                ivec2 q = ivec2(uv * vec2(viewWidth, viewHeight));
                ScenePoint pa = scenePoint(uv, texelFetch(depthtex1, q, 0).r, q, true);
                above = (pa.sky || pa.dist > dist0) ? texture(colortex0, uv).rgb : environment(t);
            }
            // Beyond the critical angle the surface mirrors the deep water below.
            vec3 deep = waterInscatter(waterAmbient(skyLight, 1.0) * 0.4, 64.0);
            surfaceColor = mix(above, deep, F);
        }
        vec3 T = exp(-ext * pathLen);
        float depthBelow = cameraDepthBelowSurface();
        // With volumetric light on, the directional sun part under water comes from the
        // shadowed light-shaft pass; keep only a fraction here as broad forward scatter.
        #ifdef VOLUMETRIC_LIGHT
            const float sunShare = 0.3;
        #else
            const float sunShare = 1.0;
        #endif
        vec3 ambient = waterAmbient(skyLight, sunShare) * exp(-ext * depthBelow);
        scene = surfaceColor * T + waterInscatter(ambient, pathLen);
    } else if (water) {
        // ------------------------------------------------------------ water from above
        vec3 n = decodeUnitVector(waterData.rg);
        if (lodWaves) {
            // LOD water from Voxy: add the analytic waves here, band-limited by distance.
            float footprint = dist0 * 2.0 / max(gbufferProjection[1][1] * viewHeight, 1.0) / max(abs(dir.y), 0.12);
            n = waveNormal(waveSurface(cameraPosition.xz + scene0.xz, waveTime(), waterOpenness(waterLm.y), footprint).slope);
        }
        vec3 v = -dir;
        float skyLight = waterLm.y;
        vec3 nView = sceneToViewDir(n);
        vec3 viewDirV = normalize(view0);

        // Refraction: offset the lookup along the refracted ray, re-validate against depth.
        float thickness = d1 >= 1.0 ? 64.0 : max(dist1 - dist0, 0.0);
        vec3 refrV = refract(viewDirV, nView, 1.0 / WATER_IOR);
        vec2 uv = texCoord;
        if (dot(refrV, refrV) > 0.0) {
            vec3 target = view0 + refrV * min(thickness, 3.0) * WATER_REFRACTION;
            vec2 cand = viewToScreen(target).xy;
            if (all(greaterThan(cand, vec2(0.0))) && all(lessThan(cand, vec2(1.0)))) {
                ivec2 q = ivec2(cand * vec2(viewWidth, viewHeight));
                ScenePoint pc = scenePoint(cand, texelFetch(depthtex1, q, 0).r, q, true);
                if (pc.sky || pc.dist > dist0) uv = cand;  // still behind the water surface
            }
        }
        ivec2 rq = ivec2(uv * vec2(viewWidth, viewHeight));
        ScenePoint pr = scenePoint(uv, texelFetch(depthtex1, rq, 0).r, rq, true);
        vec3 refracted = texture(colortex0, uv).rgb;
        // The floor's colour was fogged for the whole camera-to-floor path in deferred; remove
        // that so the atmosphere is applied once, for the camera-to-water path, below.
        if (!pr.sky) refracted = removeAtmosphere(refracted, uv, pr.scene, pr.dist);
        float pathLen = pr.sky ? 64.0 : max(pr.dist - dist0, 0.0);

        float sunVis = 1.0;
        vec3 sunLight = vec3(0.0);
        #ifndef DIM_NETHER
        if (fsLightDir.w >= 0.0) {
            ShadowSample sh = sampleShadowMap(scene0, vec3(0.0, 1.0, 0.0), skyLight, noise.x);
            sunVis = sh.opaque;
            sunLight = fsLightColor.rgb * sh.light;
            #ifdef DIM_OVERWORLD
                float cs = cloudShadow(scene0);
                sunLight *= cs;
                sunVis *= cs;
            #endif
        }
        #endif
        vec3 T = exp(-ext * pathLen);
        // The medium is lit from above; light reaching mid-path has crossed about half the
        // vertical extent of the path.
        float midDepth = 0.5 * pathLen * max(-dir.y, 0.1);
        // Block and hand light near the surface colour the water body too.
        vec3 blockE = blockLightIrradiance(waterLm.x);
        vec4 chroma = blockLightChroma(scene0, vec3(0.0, 1.0, 0.0));
        blockE = mix(blockE, luminance(blockE) * chroma.rgb, chroma.a);
        vec3 toHand;
        blockE += handLightIrradiance(scene0, vec3(0.0, 1.0, 0.0), toHand);
        vec3 ambient = (waterAmbient(skyLight, sunVis) + blockE) * exp(-ext * midDepth);
        vec3 transmitted = refracted * T + waterInscatter(ambient, pathLen);

        // Reflection.
        vec3 r = reflect(-v, n);
        float conf;
        vec3 reflection = reflectionAt(view0, normalize(sceneToViewDir(r)), r, skyLight, noise.y, conf);
        float F = min(fresnelDielectric(saturate(dot(n, v)), WATER_IOR) * WATER_REFLECTIVITY * CP_REFLECTION, 1.0);

        // Sun/moon glint: very smooth GGX on the wave normal.
        vec3 glint = vec3(0.0);
        #ifndef DIM_NETHER
        if (fsLightDir.w >= 0.0) {
            vec3 l = fsLightDir.xyz;
            float nDotL = dot(n, l);
            if (nDotL > 0.0) {
                vec3 h = normalize(l + v);
                float alpha = 0.0025 + 0.02 * fsWeather.z;
                float D = ggxDistribution(saturate(dot(n, h)), alpha);
                float Vis = smithVisibilityCorrelated(max(dot(n, v), 1e-3), nDotL, alpha);
                float Fh = fresnelDielectric(saturate(dot(v, h)), WATER_IOR);
                glint = sunLight * D * Vis * Fh * nDotL;
            }
        }
        #endif
        scene = mix(transmitted, reflection, F) + glint;
        // Atmosphere and clouds between the camera and the water surface, applied once.
        scene = applyAtmosphere(scene, scene0, dist0, dir);
        vec4 cl = cloudsAt(texCoord);
        scene = scene * cl.a + cl.rgb;
        #if DEBUG_VIEW == DBG_REFLECTIONS
            outDebug = vec4(conf, F, 0.0, 1.0);
        #elif DEBUG_VIEW == DBG_WATER_HEIGHT || DEBUG_VIEW == DBG_WATER_VELOCITY
            SimSurface sim = sampleWaterSim(scene0);
            float value = DEBUG_VIEW == DBG_WATER_HEIGHT ? sim.height * 10.0 : sim.velocity * 0.5;
            outDebug = vec4(max(value, 0.0), sim.weight * 0.15, max(-value, 0.0), 1.0);
        #endif
    }

    #ifdef OPAQUE_SSR
    else if (d1 < 1.0) {
        // ------------------------------------------------------------ opaque reflections
        // Trace from the opaque surface, which may sit behind glass.
        vec3 scene1 = viewToScene(view1);
        vec3 dir1 = scene1 / max(length(scene1), EPSILON);
        GBufferData g = decodeGBuffer(texelFetch(colortex1, px, 0), texelFetch(colortex2, px, 0),
                                      texelFetch(colortex3, px, 0), texelFetch(colortex4, px, 0));
        Material m = decodeMaterial(g.albedo, g.specular, g.ao, g.material);
        vec3 n = g.normal;
        #ifndef DIM_NETHER
        {
            // Same deterministic rain modification as deferred lighting.
            vec3 worldPos = cameraPosition + scene1;
            bool wettable = (g.flags & (GB_FLAG_HAND | GB_FLAG_ENTITY)) == 0 && g.material != MAT_LAVA;
            float wet = wettable ? surfaceWetness(g.geoNormal, g.lightmap.y) : 0.0;
            applyWetness(m, n, g.geoNormal, wet, ((g.flags & GB_FLAG_LOD) != 0 ? 0.0 : puddleMask(worldPos, g.geoNormal, wet, g.material)), worldPos, g.lightmap.y);
        }
        #endif
        if (usesScreenSpaceReflection(m, g.flags)) {
            vec3 v = -dir1;
            // Rough surfaces: reflect about a GGX-sampled microfacet normal (TAA resolves it).
            vec3 h = n;
            if (m.roughness > 0.01) {
                float a2 = m.roughness * m.roughness;
                float phi = TAU * noise.z;
                float cosH = sqrt((1.0 - noise.w) / (1.0 + (a2 - 1.0) * noise.w));
                float sinH = sqrt(max(1.0 - cosH * cosH, 0.0));
                h = basisFromNormal(n) * vec3(cos(phi) * sinH, sin(phi) * sinH, cosH);
            }
            vec3 r = reflect(-v, h);
            if (dot(r, g.geoNormal) < 0.0) r = reflect(r, g.geoNormal);
            float conf;
            vec3 refl = reflectionAt(view1, normalize(sceneToViewDir(r)), r, g.lightmap.y, noise.y, conf);
            float horizon = saturate(1.0 + 1.2 * dot(r, g.geoNormal));
            // The deferred colour already carries the atmosphere and clouds in front of the
            // surface; the added reflection must be attenuated by the same transmittance.
            vec3 T, S;
            atmosphereTerms(scene1, length(scene1), dir1, T, S);
            vec3 add = refl * min(environmentReflectance(m, max(dot(n, v), 1e-3)) * CP_REFLECTION, vec3(1.0)) * horizon * horizon * m.ao;
            scene += add * T * cloudsAt(texCoord).a;
            #if DEBUG_VIEW == DBG_REFLECTIONS
                outDebug = vec4(conf, 0.0, m.smoothness, 1.0);
            #endif
        }
    }
    #endif

    // ---------------------------------------------------------------- translucent overlay
    vec4 layer = texelFetch(colortex5, px, 0);
    scene = scene * (1.0 - saturate(layer.a)) + layer.rgb;
    outScene = vec4(sanitizeRadiance(scene), 1.0);
}
#endif

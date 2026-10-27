// composite (translucency + reflections). Input colortex0 = lit opaque scene and sky.
//  * Opaque pixels: adds environment specular (SSR, or sky with sky-light occlusion) weighted by
//    colortex6 from the lighting pass. Rough surfaces sample a GGX-distributed reflection
//    direction per frame; TAA integrates them into a glossy reflection.
//  * Water: refraction (screen-space, validated against depth), Beer-Lambert absorption and
//    in-scattering over the underwater path, Fresnel (n = 1.333) reflection, sun/moon glints,
//    caustics already applied on the floor by the lighting pass via shadows.
//  * Glass, ice, slime, portals: tinted transmission, slight refraction, Fresnel reflection.
//  * Underwater view: Snell's window and total internal reflection at the surface.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/state.glsl"
#include "/lib/common/transform.glsl"
#include "/lib/common/depth.glsl"
#include "/lib/common/gbuffer.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/material/labpbr.glsl"
#define ATMOSPHERE_SAMPLERS
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/sky/celestial.glsl"
#include "/lib/lighting/shadow_proj.glsl"
#include "/lib/lighting/shadows.glsl"
#include "/lib/lighting/brdf.glsl"
#include "/lib/lighting/ambient.glsl"
#include "/lib/atmosphere/fog.glsl"
#include "/lib/reflections/ssr.glsl"
#ifdef WORLD_OVERWORLD
#include "/lib/sky/stars.glsl"
#include "/lib/sky/moon.glsl"
#include "/lib/sky/sky.glsl"
#endif
#ifdef WORLD_END
#include "/lib/space/end_sky.glsl"
#endif
#ifdef WORLD_NETHER
#include "/lib/nether/nether.glsl"
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
#if DEBUG_VIEW == 24
#include "/lib/water/sim_common.glsl"
uniform sampler2D waterSimSamplerA;
uniform sampler2D waterSimSamplerB;
#endif

in vec2 texcoord;

/*
const int colortex4Format = RGBA16;
const int colortex5Format = RGBA8;
const bool colortex4Clear = true;
const bool colortex5Clear = true;
const vec4 colortex4ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
*/

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

// GGX half-vector sample (tangent space, z = normal) for rough reflections.
vec3 sampleGGX(vec2 u, float a) {
    float a2 = a * a;
    float cosT = sqrt((1.0 - u.x) / (1.0 + (a2 - 1.0) * u.x));
    float sinT = sqrt(max(1.0 - cosT * cosT, 0.0));
    float phi = TAU * u.y;
    return vec3(sinT * cos(phi), sinT * sin(phi), cosT);
}

vec3 fallbackSky(vec3 dirPlayer, float skyLight, float roughA) {
    #ifdef SKY_REFLECTIONS
    #ifdef WORLD_OVERWORLD
    SkyLights L = skyLights();
    // The shadow-casting body is added analytically by the BRDF glint; only the other one is drawn.
    vec3 s = roughA < 0.08 ? skyRadianceDisks(dirPlayer, L, pixelAngularSize(), false, L.sunIsLight)
                           : skyRadiance(dirPlayer, L, 0.01, false);
    // Very rough surfaces see the cosine-weighted sky.
    s = mix(s, skyIrradiance(dirPlayer) * PI, saturate(roughA * 1.5));
    #elif defined WORLD_END
    vec3 s = endSkyRadiance(dirPlayer, 0.01);
    #else
    vec3 s = netherSkyRadiance(dirPlayer);
    #endif
    return s * skyVisibility(skyLight);
    #else
    return vec3(0.0);
    #endif
}

// Reflection radiance for a surface: SSR where possible, sky otherwise.
vec3 reflectionRadiance(vec3 viewPos, vec3 viewN, float roughA, float skyLight, float noise, vec2 noise2, out float hitConf) {
    vec3 v = normalize(-viewPos);
    vec3 n = viewN;
    if (roughA > 0.002) {
        mat3 tbn = basisFromNormal(n);
        vec3 h = tbn * sampleGGX(noise2 * vec2(0.9, 1.0), roughA);
        if (dot(h, v) > 0.0) n = h;
    }
    vec3 r = reflect(-v, n);
    vec3 rPlayer = mat3(gbufferModelViewInverse) * r;
    hitConf = 0.0;
    vec3 col = fallbackSky(rPlayer, skyLight, roughA);
    #ifdef SSR
    if (roughA <= SSR_MAX_ROUGHNESS * SSR_MAX_ROUGHNESS) {
        SSRHit hit = traceSSR(viewPos, r, depthtex1, noise, SSR_STEPS);
        if (hit.confidence > 0.0) {
            vec3 c = texture(colortex0, hit.uv).rgb;
            hitConf = hit.confidence;
            col = mix(col, c, hit.confidence);
        }
    }
    #endif
    return col;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec2 uv = texcoord;
    vec3 scene = texelFetch(colortex0, px, 0).rgb;
    float noise = interleavedGradient(gl_FragCoord.xy + float(NOISE_FRAME % 64) * 5.588238);
    vec2 noise2 = r2(float(NOISE_FRAME % 256) + noise * 64.0);

    vec4 surf = texelFetch(colortex4, px, 0);
    uvec2 idf = unpack2x8u(surf.w);
    int tId = int(idf.x);
    // Front surface (with translucents) and opaque surface, across vanilla and LOD depth buffers.
    SceneDepth sd0 = resolveDepth(uv, false, false);
    SceneDepth sd1 = resolveDepth(uv, true, false);
    float d0 = texelFetch(depthtex0, px, 0).r;
    float d1 = texelFetch(depthtex1, px, 0).r;
    bool translucent = tId != 0 && !sd0.sky && (sd1.sky || sd0.viewPos.z > sd1.viewPos.z + 1e-3);

    #if DEBUG_VIEW == 24
    // Water simulation: simulated height on water (red up, blue down) over a dimmed scene, and a
    // status strip in the top-left corner, one cell each: simulation active | field still moving |
    // entry armed (dry >= 0.15 s) | splash pending | steps this frame (0-4) | splash applied now.
    {
        vec3 dbg = linearToSrgb(saturate(scene * state.exposure)) * 0.35;
        if (tId == MAT_WATER && !sd0.sky) {
            vec3 pp = viewToPlayer(sd0.viewPos);
            ivec2 cell = simCameraCell() + ivec2(floor(simLocal(pp.xz)));
            ivec2 tx = simTexel(cell);
            float h = state.simParity == 0 ? texelFetch(waterSimSamplerA, tx, 0).r : texelFetch(waterSimSamplerB, tx, 0).r;
            dbg = mix(dbg, h > 0.0 ? vec3(1.0, 0.25, 0.1) : vec3(0.1, 0.35, 1.0), saturate(abs(h) * 6.0));
            dbg *= mix(0.4, 1.0, simEdgeFade(simLocal(pp.xz)));
        }
        vec2 sp = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        if (sp.y > 0.95 && sp.x < 0.3) {
            int k = int(sp.x / 0.05);
            bool on = k == 0 ? state.simCenter.w > 0.5 : k == 1 ? state.simFlags.x != 0 : k == 2 ? state.simFlags.z >= 150
                    : k == 3 ? state.simFlags.w > 0 : k == 4 ? state.simInfo.y > 0 : state.simInfo.z > 0;
            float steps = float(state.simInfo.y) / 4.0;
            dbg = k == 4 ? vec3(steps, steps, 0.2) : (on ? vec3(0.2, 1.0, 0.3) : vec3(0.35, 0.05, 0.05));
            if (fract(sp.x / 0.05) < 0.06) dbg = vec3(0.0);
        }
        outColor = vec4(srgbToLinear(dbg), 1.0);
        return;
    }
    #endif

    // ---------------------------------------------------------------- opaque reflections
    if (!translucent) {
        vec4 sw = texelFetch(colortex6, px, 0);
        if (maxOf(sw.rgb) > 0.004 && d1 < 1.0) {
            vec4 g2 = texelFetch(colortex2, px, 0);
            vec3 n = octDecode(g2.xy);
            vec2 lm = unpack2x8(g2.w);
            vec3 viewPos = sceneToView(uv, d1);
            vec3 viewN = normalize(mat3(gbufferModelView) * n);
            float conf;
            vec3 refl = reflectionRadiance(viewPos, viewN, sw.a, lm.y, noise, noise2, conf);
            scene += refl * sw.rgb;
        }
        outColor = vec4(hdrSafe(scene), 1.0);
        return;
    }

    // ---------------------------------------------------------------- translucent surface
    vec3 n = octDecode(surf.xy);
    vec2 lm = unpack2x8(surf.z);
    bool water = tId == MAT_WATER;
    vec4 tint = texelFetch(colortex5, px, 0);
    vec3 viewPos0 = sd0.viewPos;
    vec3 viewPos1 = sd1.sky ? viewPos0 * 1e3 : sd1.viewPos;
    vec3 viewN = normalize(mat3(gbufferModelView) * n);
    vec3 v = normalize(-viewPos0);
    vec3 playerV = mat3(gbufferModelViewInverse) * v;
    bool fromBelow = water && isEyeInWater == 1 && dot(n, playerV) < 0.0;
    if (fromBelow) { n = -n; viewN = -viewN; }

    float iorRatio = water ? (fromBelow ? 1.333 : 1.0 / 1.333) : 1.0 / 1.5;
    float NoV = saturate(dot(viewN, v));
    float f0 = water ? 0.02 : 0.04;
    float F = f0 + (1.0 - f0) * pow5(1.0 - NoV);

    // Refraction: offset proportional to the bent ray's lateral travel through the medium.
    vec3 transmitted = scene;
    float pathLen = length(viewPos1 - viewPos0);
    #ifdef WATER_REFRACTION
    vec3 refrDir = refract(-v, viewN, iorRatio);
    bool tir = dot(refrDir, refrDir) < 1e-6;
    if (!tir) {
        float strength = water ? min(pathLen, 6.0) * 0.6 : 0.15;
        vec3 target = viewPos0 + refrDir * max(strength, 0.05);
        vec2 ruv = viewToScene(target).xy;
        ruv = clamp(ruv, vec2(0.001), vec2(0.999));
        // The opaque surface seen through the refracted ray, across vanilla and LOD depth. LOD
        // water has no vanilla depth behind it; reading only depthtex1 there treated the bottom
        // as 1000x farther than the surface and absorbed everything (dark distant water).
        SceneDepth rs = resolveDepth(ruv, true, false);
        vec3 rp = rs.sky ? viewPos0 * 1e3 : rs.viewPos;
        // Only accept samples that are behind the surface (else foreground leaks in).
        if (rp.z < viewPos0.z) {
            transmitted = texture(colortex0, ruv).rgb;
            pathLen = length(rp - viewPos0);
        }
    }
    #else
    bool tir = false;
    #endif

    vec3 color;
    #ifdef WORLD_OVERWORLD
    SkyLights L = skyLights();
    vec3 lightDir = L.lightDir;
    vec3 lightIllum = (L.sunIsLight ? vec3(L.sunIllum) : L.moonIllum) * transmittanceToTop(cameraRadius(cameraPosition.y), lightDir.y);
    float lightAng = L.sunIsLight ? SUN_ANGULAR_RADIUS : MOON_ANGULAR_RADIUS;
    #elif defined WORLD_END
    vec3 lightDir = END_LIGHT_DIR;
    vec3 lightIllum = endLightIlluminance();
    float lightAng = 0.02;
    #else
    vec3 lightDir = vec3(0.0, 1.0, 0.0);
    vec3 lightIllum = vec3(0.0);
    float lightAng = 0.0;
    #endif
    vec3 playerPos0 = viewToPlayer(viewPos0);

    if (water) {
        if (!fromBelow) {
            // Light inside the water column: absorption plus in-scattering of ambient and sun light.
            vec3 sigA = waterAbsorption();
            vec3 sigS = waterScattering(tint.rgb);
            vec3 sigT = sigA + sigS;
            float dPath = min(pathLen, 256.0);
            vec3 Tw = exp(-sigT * dPath);
            #ifdef WORLD_OVERWORLD
            vec3 amb = skyIrradiance(vec3(0.0, 1.0, 0.0)) * PI * skyVisibility(lm.y);
            #elif defined WORLD_END
            vec3 amb = endAmbient(vec3(0.0, 1.0, 0.0)) * PI;
            #else
            vec3 amb = netherAmbient(vec3(0.0, 1.0, 0.0), playerPos0 + cameraPosition) * PI;
            #endif
            vec3 inLight = amb * INV_4PI + lightIllum * 0.08 * saturate(lightDir.y) * smoothstep(0.5, 0.9, lm.y);
            vec3 scatterW = sigS / max(sigT, vec3(1e-5)) * inLight * (1.0 - Tw);
            transmitted = transmitted * Tw + scatterW;
        }
    } else {
        // Glass-like: coloured transmission by alpha, light lit surface for the tint itself.
        vec3 t = srgbToLinear(tint.rgb);
        float a = tint.a;
        transmitted = transmitted * mix(vec3(1.0), t, sqrt(a)) * (1.0 - a * 0.25);
        #ifdef WORLD_OVERWORLD
        vec3 amb = skyIrradiance(n) * skyVisibility(lm.y);
        #else
        vec3 amb = vec3(0.02);
        #endif
        transmitted += t * a * a * amb * 0.5;
    }

    // Reflection.
    float conf;
    // Distant water: the roughness its footprint-filtered normal lost (gbuffers/translucent.fsh)
    // widens the lobe, so far glitter blurs into a glow instead of aliasing.
    float waterExtraA = water ? tint.a * tint.a : 0.0;    // decodeWaterRoughness (lib/water/waves.glsl)
    float roughA = water ? sqrt(sq(0.0016) + sq(waterExtraA)) : 0.004;
    vec3 refl = reflectionRadiance(viewPos0, viewN, roughA, fromBelow ? 0.0 : lm.y, noise, noise2, conf);
    if (fromBelow) {
        // Seen from below, the reflection is the underwater world (total internal reflection
        // outside Snell's window); approximate with the water's own scattered colour.
        refl = mix(refl, waterScattering(tint.rgb) * 2.0 * skyIrradiance(vec3(0.0, 1.0, 0.0)), 1.0 - conf);
    }
    if (tir) F = 1.0;
    color = mix(transmitted, refl, F);

    // Direct specular glint from the sun or moon (shadowed).
    if (maxOf(lightIllum) > 0.0 && !fromBelow) {
        ShadowResult sh = sampleShadow(playerPos0, n, lightDir, noise, 0.01);
        Material wm;
        wm.albedo = vec3(0.0); wm.alpha = water ? sqrt(sq(0.0025) + sq(waterExtraA)) : 0.003; wm.f0 = vec3(f0); wm.metal = false; wm.metalIndex = -2;
        wm.porosity = 0.0; wm.sss = 0.0; wm.emission = 0.0; wm.ao = 1.0;
        LightSample ls = evalDirectional(wm, n, playerV, lightDir, lightAng);
        vec3 glint = ls.specular * lightIllum;
        #ifdef WORLD_OVERWORLD
        glint = limitHighlight(glint);
        #endif
        color += glint * sh.light * smoothstep(0.0, 0.3, lm.y + 0.2);
    }

    #if DEBUG_VIEW == 16
    color = water ? n * 0.5 + 0.5 : vec3(0.0);
    #elif DEBUG_VIEW == 17
    color = vec3(conf, 1.0 - conf, 0.0);
    #endif
    outColor = vec4(hdrSafe(color), 1.0);
}

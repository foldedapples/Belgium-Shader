// deferred (lighting): shades the opaque G-buffer, draws the sky behind it.
// Output colortex0: HDR radiance (no aerial perspective yet; that is applied in composite after
// translucents). colortex6: environment specular weight (rgb) and GGX alpha, consumed by the
// reflection pass.

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
#include "/lib/lighting/emitters.glsl"
#ifdef COLORED_LIGHTING
#include "/lib/lighting/light_volume.glsl"
#endif
#include "/lib/lighting/blocklight.glsl"
#include "/lib/weather/ripples.glsl"
#include "/lib/weather/wetness.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/water/waves.glsl"
#include "/lib/atmosphere/fog.glsl"
#include "/lib/water/caustics.glsl"
#include "/lib/lighting/contact.glsl"
#ifdef WORLD_OVERWORLD
#include "/lib/sky/stars.glsl"
#include "/lib/sky/moon.glsl"
#include "/lib/sky/sky.glsl"
#include "/lib/clouds/clouds_common.glsl"
#endif
#ifdef WORLD_END
#include "/lib/space/end_sky.glsl"
#endif
#ifdef WORLD_NETHER
#include "/lib/nether/nether.glsl"
#endif
#if defined AMBIENT_OCCLUSION || defined INDIRECT_SUN
uniform sampler2D aoGiSampler;   // half resolution: rgb indirect sun (per unit illuminance), a AO
#endif

uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D noisetex;

in vec2 texcoord;

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA8;
const int colortex2Format = RGBA16;
const int colortex3Format = RGBA16;
const int colortex6Format = RGBA16F;
const bool colortex6Clear = true;
*/

/* RENDERTARGETS: 0,6 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outSpecWeight;

// Emitters under local adaptation (as the sun disk, lib/sky/celestial.glsl): a surface emitting
// `strength` x albedo would display at strength x exposure; that peak is compressed smoothly
// towards EMISSION_DISPLAY_PEAK x display white. Lava at strength 8 used to display at 6x white in
// the Nether and clipped to a white sheet. The factor depends on the material's strength and the
// exposure only - not on the pixel - so the texture's own contrast is kept.
const float EMISSION_DISPLAY_PEAK = 2.5;
float adaptedEmission(float strength) {
    float ex = max(state.exposure, 1e-6);
    return strength / (1.0 + strength * ex / EMISSION_DISPLAY_PEAK);
}

// Joint-bilateral upsampling of a half-resolution buffer guided by depth and normal.
vec4 upsampleHalf(sampler2D tex, vec2 uv, float linDepth, vec3 normal) {
    vec2 halfSize = vec2(textureSize(tex, 0));
    vec2 p = uv * halfSize - 0.5;
    ivec2 b = ivec2(floor(p));
    vec2 f = p - vec2(b);
    vec4 sum = vec4(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 4; i++) {
        ivec2 o = ivec2(i & 1, i >> 1);
        ivec2 tc = clamp(b + o, ivec2(0), ivec2(halfSize) - 1);
        vec4 s = texelFetch(tex, tc, 0);
        vec2 fullUv = (vec2(tc) + 0.5) / halfSize;
        float d = linearizeDepth(texture(depthtex1, fullUv).r, near, far * 4.0);
        float wd = exp(-abs(d - linDepth) / max(linDepth * 0.05, 0.05));
        vec2 w2 = mix(1.0 - f, f, vec2(o));
        float w = w2.x * w2.y * wd + 1e-4;
        sum += s * w;
        wsum += w;
    }
    return sum / wsum;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec2 uv = texcoord;
    vec4 g1 = texelFetch(colortex1, px, 0);
    vec4 g2 = texelFetch(colortex2, px, 0);
    vec4 g3 = texelFetch(colortex3, px, 0);
    GBufferData gb = decodeGBuffer(g1, g2, g3);
    bool hand = hasFlag(gb.flags, FLAG_HAND);
    SceneDepth sd = resolveDepth(uv, true, hand);
    vec3 playerPos = viewToPlayer(sd.viewPos);
    vec3 viewDir = normalize(playerPos);
    float pixAng = pixelAngularSize();
    outSpecWeight = vec4(0.0, 0.0, 0.0, 1.0);

    #ifdef WORLD_OVERWORLD
    SkyLights L = skyLights();
    #endif

    if (sd.sky) {
        #ifdef WORLD_OVERWORLD
        vec3 sky = skyRadiance(viewDir, L, pixAng, true);
        #ifdef VOLUMETRIC_CLOUDS
        vec4 clouds = sampleClouds(uv);
        sky = sky * clouds.a + clouds.rgb;
        #endif
        outColor = vec4(hdrSafe(sky), 1.0);
        #elif defined WORLD_END
        outColor = vec4(endSkyRadiance(viewDir, pixAng), 1.0);
        #else
        outColor = vec4(netherSkyRadiance(viewDir), 1.0);
        #endif
        return;
    }

    float ign = interleavedGradient(gl_FragCoord.xy + float(NOISE_FRAME % 64) * 5.588238);
    vec3 worldPos = playerPos + cameraPosition;
    Material m = decodeMaterial(gb.albedo, gb.spec, 1.0);
    vec3 n = gb.normal;
    vec3 v = -viewDir;
    // Normals facing away from the viewer (normal maps at grazing angles) are bent back.
    if (dot(n, v) < 0.0) n = normalize(n + v * (-dot(n, v) + 0.02));

    if (hasFlag(gb.flags, FLAG_UNLIT)) { outColor = vec4(gb.albedo * 0.5, 1.0); return; }
    if (gb.id == MAT_EMISSIVE_FLAT) { outColor = vec4(gb.albedo * adaptedEmission(6.0 * EMISSION_STRENGTH), 1.0); return; }

    float puddle = 0.0;
    #ifdef WORLD_OVERWORLD
    puddle = applyWetness(m, n, gb.geoNormal, gb.lightmap, playerPos, worldPos, gb.flags, 1.0);
    applySnow(m, n, gb.geoNormal, gb.lightmap, worldPos, gb.flags);
    #endif

    float ao = gb.ao;
    #ifdef AMBIENT_OCCLUSION
    if (!hand && !sd.lod) {
        float linD = linearizeDepth(sd.depth, near, far * 4.0);
        ao *= mix(1.0, upsampleHalf(aoGiSampler, uv, linD, n).a, AO_STRENGTH);
    }
    #endif

    vec3 color = vec3(0.0);
    vec3 dbgDirect = vec3(0.0), dbgAmbientStart = vec3(0.0), dbgEmission = vec3(0.0);
    float skyVis = skyVisibility(gb.lightmap.y);
    vec3 shadowLight = vec3(1.0);

    // ---------------------------------------------------------------- direct light
    #if defined WORLD_OVERWORLD || defined WORLD_END
    #ifdef WORLD_OVERWORLD
    vec3 lightDir = L.lightDir;
    float r = cameraRadius(worldPos.y);
    vec3 lightIllum = (L.sunIsLight ? vec3(L.sunIllum) : L.moonIllum) * transmittanceToTop(r, lightDir.y);
    float sunAng = L.sunIsLight ? SUN_ANGULAR_RADIUS : MOON_ANGULAR_RADIUS;
    #else
    vec3 lightDir = END_LIGHT_DIR;
    vec3 lightIllum = endLightIlluminance();
    float sunAng = 0.02;
    #endif
    if (maxOf(lightIllum) > 1e-6) {
        float NoLgeo = dot(gb.geoNormal, lightDir);
        bool thin = hasFlag(gb.flags, FLAG_PLANT) || m.sss > 0.0;
        ShadowResult sh;
        sh.light = vec3(1.0);
        sh.casterDist = 1e4;
        if (NoLgeo > -0.02 || thin) {
            sh = sampleShadow(playerPos, thin ? lightDir : gb.geoNormal, lightDir, ign, sunAng);
        } else {
            sh.light = vec3(0.0);
        }
        #ifdef WORLD_OVERWORLD
        #ifdef CLOUD_SHADOWS_ACTIVE
        sh.light *= cloudShadowAt(worldPos, lightDir);
        #endif
        #endif
        // Water above the receiver: absorption and caustics from the actual waves.
        if (maxOf(sh.light) > 0.0 && !sd.lod) sh.light *= underwaterLight(playerPos, lightDir);
        // Fine contact shadows the shadow map cannot resolve.
        if (maxOf(sh.light) > 0.0 && !hand && !sd.lod) {
            vec3 viewL = normalize(mat3(gbufferModelView) * lightDir);
            sh.light *= contactShadow(sd.viewPos + mat3(gbufferModelView) * gb.geoNormal * 0.02, viewL, ign);
        }
        // Parallax self-shadowing from the G-buffer.
        sh.light *= mix(1.0, gb.parallaxShadow, 0.9);
        // Light that only reaches faces open to the sky (vanilla sky light 0 means enclosed). Only in
        // the Overworld: the End has no sky light at all, so this gate switched the black hole's
        // light off everywhere and only block light (the portal) lit the island.
        #ifdef WORLD_OVERWORLD
        sh.light *= smoothstep(0.0, 0.2, gb.lightmap.y + (sd.lod ? 1.0 : 0.0)) * 0.98 + 0.02 * float(hand);
        #endif
        shadowLight = sh.light;
        LightSample ls = evalDirectional(m, n, v, lightDir, sunAng);
        #ifdef WORLD_OVERWORLD
        // A mirror image of the sun or moon is never brighter than the (adapted) disk itself.
        ls.specular = limitHighlight(ls.specular * lightIllum) / max(lightIllum, vec3(1e-9));
        #endif
        vec3 direct = (ls.diffuse * m.albedo + ls.specular) * sh.light;
        #ifdef SUBSURFACE_SCATTERING
        if (m.sss > 0.0) {
            float thick = sh.casterDist > 1e3 ? 0.0 : sh.casterDist;
            direct += m.albedo * subsurfaceTransmission(m, gb.geoNormal, v, lightDir, thick) * sh.light;
        }
        #endif
        color += direct * lightIllum;
        dbgDirect = direct * lightIllum;
    }
    #endif

    // ---------------------------------------------------------------- ambient
    dbgAmbientStart = color;
    vec3 diffuseColor = m.metal ? vec3(0.0) : m.albedo;
    #ifdef WORLD_OVERWORLD
    vec3 skyAmb = skyIrradiance(n) * SKY_LIGHT_STRENGTH;
    // Light bouncing off the ground into the lower hemisphere of a surface.
    vec3 groundBounce = skyIrradiance(vec3(0.0, 1.0, 0.0)) * 0.25 * saturate(-n.y * 0.5 + 0.5);
    color += diffuseColor * (skyAmb + groundBounce) * skyVis * ao;
    #ifdef INDIRECT_SUN
    if (!hand && !sd.lod) {
        float linD = linearizeDepth(sd.depth, near, far * 4.0);
        vec3 gi = upsampleHalf(aoGiSampler, uv, linD, n).rgb;
        color += diffuseColor * gi * (L.sunIsLight ? vec3(L.sunIllum) : L.moonIllum) * transmittanceToTop(cameraRadius(worldPos.y), L.lightDir.y) * ao * INDIRECT_SUN_STRENGTH;
    }
    #endif
    #elif defined WORLD_END
    color += diffuseColor * endAmbient(n) * ao;
    #else
    color += diffuseColor * netherAmbient(n, worldPos) * ao;
    #endif

    #if defined LIGHTNING_FLASH && defined WORLD_OVERWORLD
    // Lightning: a brief, very bright blue-white source high above the bolt.
    if (lightningBoltPosition.w > 0.5) {
        vec3 toBolt = lightningBoltPosition.xyz + vec3(0.0, 60.0, 0.0) - playerPos;
        float dB = length(toBolt);
        float flash = 1.0 / (1.0 + dB * dB * 2.5e-4);
        color += diffuseColor * vec3(0.75, 0.8, 1.0) * (12.0 * flash) * saturate(dot(n, toBolt / dB) * 0.6 + 0.4) * max(skyVis, 0.05);
    }
    #endif

    // Cave floor light: a dim, neutral minimum so unlit caves are not pure black.
    color += diffuseColor * (CAVE_MIN_LIGHT * 4.0e-4 + nightVision * 0.25) * ao;

    // ---------------------------------------------------------------- block light and emission
    color += diffuseColor * blockLightAt(playerPos, gb.geoNormal, gb.lightmap.x) * ao;
    color += diffuseColor * handLight(playerPos, n);
    dbgEmission = m.albedo * adaptedEmission(m.emission * EMISSION_STRENGTH * 8.0);
    vec3 dbgAmbient = color - dbgAmbientStart;      // ambient, sky, lightning, block and hand light
    color += dbgEmission;

    // ---------------------------------------------------------------- environment specular weight
    float NoV = saturate(dot(n, v));
    vec3 specWeight = m.metal && m.metalIndex >= 0
        ? fresnelConductor(NoV, METAL_N[m.metalIndex], METAL_K[m.metalIndex]) * m.albedo * mix(1.0, dfgTerm(NoV, m.alpha).x + dfgTerm(NoV, m.alpha).y, saturate(m.alpha * 2.0))
        : specularAlbedo(m.f0, NoV, m.alpha);
    specWeight *= multiScatterCompensation(m.f0, NoV, m.alpha);
    // Specular occlusion from AO (Lagarde & de Rousiers 2014).
    float specOcc = saturate(pow(NoV + ao, exp2(-16.0 * m.alpha - 1.0)) - 1.0 + ao);
    specWeight *= specOcc;
    outSpecWeight = vec4(specWeight, m.alpha);

    #if DEBUG_VIEW != 0
    vec3 dbg = vec3(0.0);
    #if DEBUG_VIEW == 1
    dbg = m.albedo;
    #elif DEBUG_VIEW == 2
    dbg = n * 0.5 + 0.5;
    #elif DEBUG_VIEW == 3
    dbg = vec3(sqrt(m.alpha));
    #elif DEBUG_VIEW == 4
    dbg = m.metal ? vec3(1.0, 0.8, 0.2) * m.f0 + 0.2 : m.f0 * 4.0;
    #elif DEBUG_VIEW == 5
    dbg = m.albedo * m.emission;
    #elif DEBUG_VIEW == 6
    dbg = vec3(ao);
    #elif DEBUG_VIEW == 7
    dbg = vec3(gb.lightmap, 0.0);
    #elif DEBUG_VIEW == 8
    dbg = shadowLight;
    #elif DEBUG_VIEW == 9
    {
        ShadowCoord sc = shadowCoordFor(shadowLightRotation() * playerPos, 0.0);
        const vec3 cols[5] = vec3[5](vec3(0.2), vec3(1, 0.3, 0.3), vec3(0.3, 1, 0.3), vec3(0.3, 0.4, 1), vec3(1, 1, 0.3));
        // Cascade colour; the checker pattern is world-anchored shadow texels (must not swim).
        vec2 t = floor((shadowLightRotation() * playerPos).xy + state.cascadeCenter[max(sc.cascade, 0)].xy) / sc.texelBlocks;
        dbg = cols[sc.cascade + 1] * (0.75 + 0.25 * mod(floor(sc.uvz.x * float(shadowMapResolution)) + floor(sc.uvz.y * float(shadowMapResolution)), 2.0));
    }
    #elif DEBUG_VIEW == 10
    // Lighting only: the shaded result divided by the albedo (surface colour removed).
    dbg = color / max(m.albedo, vec3(0.04)) * 0.25;
    #elif DEBUG_VIEW == 11
    #ifdef COLORED_LIGHTING
    {
        vec3 rel = playerPos + gb.geoNormal * 0.5;
        ivec3 blk = cameraPositionInt + ivec3(floor(cameraPositionFract + rel));
        dbg = insideVolume(blk, ivec3(state.lightVolumeOrigin.xyz)) ? sampleLightVolume(rel).rgb : vec3(0.1, 0.0, 0.0);
    }
    #endif
    #elif DEBUG_VIEW == 12
    dbg = blockLightAt(playerPos, gb.geoNormal, gb.lightmap.x) * 0.25;
    #elif DEBUG_VIEW == 13
    dbg = hash3(ivec2(gb.id, 7));
    #elif DEBUG_VIEW == 14
    dbg = vec3(m.porosity, m.sss, puddle);
    #elif DEBUG_VIEW == 20
    dbg = sd.lod ? vec3(0.2, 0.6, 1.0) : vec3(0.6);
    #elif DEBUG_VIEW >= 21 && DEBUG_VIEW <= 23
    // HDR contributions at the current exposure (soft roll-off so overexposure stays readable):
    // 21 direct light (sun / moon / End disk), 22 ambient + block light, 23 emission.
    vec3 part = DEBUG_VIEW == 21 ? dbgDirect : DEBUG_VIEW == 22 ? dbgAmbient : dbgEmission;
    dbg = 1.0 - exp(-part * state.exposure);
    #endif
    #if DEBUG_VIEW <= 14 || (DEBUG_VIEW >= 20 && DEBUG_VIEW <= 23)
    outColor = vec4(dbg, 1.0);
    return;
    #endif
    #endif

    outColor = vec4(hdrSafe(color), 1.0);
}

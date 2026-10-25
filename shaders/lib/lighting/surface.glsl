#ifndef LIGHTING_SURFACE_GLSL
#define LIGHTING_SURFACE_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/material/labpbr.glsl"
#include "/lib/lighting/brdf.glsl"
#include "/lib/post/color_profile.glsl"

// Shared surface lighting for deferred and forward paths (ORIGINAL_ARCHITECTURE.md sec. 5).
// All inputs are scene space; `v` points from the surface to the camera.

uniform sampler2D dfgLutTex;

vec2 sampleDfg(float nDotV, float roughness) {
    float perceptual = sqrt(roughness);
    vec2 uv = (vec2(saturate(nDotV), saturate(perceptual)) * 63.0 + 0.5) / 64.0;
    return texture(dfgLutTex, uv).rg;
}

// Metals defined by complex IOR are tinted by the albedo (LabPBR: predefined metals use the
// albedo as a tint). The tint is normalised to its brightest channel so the IOR keeps
// control of overall reflectance.
vec3 metalTint(vec3 albedo) { return albedo / max(maxOf(albedo), 0.04); }

vec3 materialFresnel(Material m, float cosTheta) {
    if (m.metalCode >= 230 && m.metalCode <= 237) {
        vec3 n, k;
        labMetalIor(m.metalCode, n, k);
        return fresnelConductor(cosTheta, n, k) * saturate(metalTint(m.albedo));
    }
    return fresnelSchlick(m.f0, cosTheta);
}

// Reflectance used to weight environment (ambient/SSR) specular: split-sum with DFG and a
// single-scattering energy compensation so rough metals do not lose energy.
vec3 environmentReflectance(Material m, float nDotV) {
    vec2 dfg = sampleDfg(nDotV, m.roughness);
    vec3 f0 = m.f0;
    if (m.metalCode >= 230 && m.metalCode <= 237) f0 = materialFresnel(m, 1.0);
    vec3 single = f0 * dfg.x + dfg.y;
    float ess = max(dfg.x + dfg.y, 1e-3);
    vec3 compensation = 1.0 + f0 * (1.0 / ess - 1.0);
    return single * compensation;
}

float diffuseWeight(Material m) { return m.metal ? 0.0 : 1.0; }

// Direct light: returns outgoing radiance per unit light irradiance (already includes nDotL).
void evaluateDirectBrdf(Material m, vec3 n, vec3 v, vec3 l, out vec3 diffuse, out vec3 specular) {
    float nDotL = dot(n, l);
    float nDotV = max(dot(n, v), 1e-3);
    diffuse = vec3(0.0); specular = vec3(0.0);
    if (nDotL <= 0.0) return;
    vec3 h = safeNormalize(l + v, n);
    float nDotH = saturate(dot(n, h));
    float vDotH = saturate(dot(v, h));
    vec3 F = materialFresnel(m, vDotH);
    float D = ggxDistribution(nDotH, m.roughness);
    float V = smithVisibilityCorrelated(nDotV, nDotL, m.roughness);
    specular = D * V * F * nDotL;
    diffuse = m.albedo * INV_PI * diffuseWeight(m) * (1.0 - F) * nDotL;
}

// Sky visibility from the vanilla sky lightmap: sky light drops one level per block of
// occlusion, which reads as roughly a power falloff of the visible sky solid angle.
float skyVisibility(float skyLight) { return pow(saturate(skyLight), 2.4); }

// The End and the Nether have no sky light data (the lightmap's sky channel is 0 there). In
// the End the space backdrop lights everything that is open; in the Nether the haze ambient
// is handled separately, so the sky term is zero.
float dimensionSkyVisibility(float skyLight) {
    #if defined DIM_END
        return 1.0;
    #elif defined DIM_NETHER
        return 0.0;
    #else
        return skyVisibility(skyLight);
    #endif
}

// Block light from the vanilla block lightmap: a softened inverse-square falloff in light
// levels, zero exactly at level 0.
vec3 blockLightIrradiance(float blockLight) {
    float level = saturate(blockLight) * 15.0;
    float e = pow(1.0 / (16.0 - level), 1.65);
    e *= smoothstep(0.0, 1.5, level);
    return blackbody(float(BLOCKLIGHT_TEMPERATURE)) * e * 2.2 * BLOCKLIGHT_INTENSITY * CP_BLOCK_LIGHT;
}

// Sky irradiance onto a surface with normal n from the per-frame hemispherical integrals:
// up-facing, side-facing and a ground bounce for down-facing normals.
vec3 skyIrradiance(vec3 n) {
    vec3 up = fsSkyIrradianceUp.rgb, side = fsSkyIrradianceSide.rgb;
    // With SSGI, real bounce light replaces most of the analytic ground bounce.
    #ifdef SSGI
        const float bounceScale = 0.4;
    #else
        const float bounceScale = 1.0;
    #endif
    vec3 groundBounce = bounceScale * up * 0.12 + fsLightColor.rgb * max(fsLightDir.y, 0.0) * 0.12 * float(fsLightDir.w >= 0.0) * bounceScale;
    float y = n.y;
    vec3 e = y >= 0.0 ? mix(side, up, y * y) : mix(side, groundBounce, y * y);
    return e * SKYLIGHT_INTENSITY;
}

// Minimal ambient so pitch-black caves stay barely readable (starlight/airglow analogue).
vec3 ambientFloor() { return vec3(0.75, 0.8, 1.0) * 2.0e-5 * AMBIENT_FLOOR + vec3(nightVision * 0.05); }

#endif

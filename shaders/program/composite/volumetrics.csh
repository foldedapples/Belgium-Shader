// composite1 compute: volumetric light at half resolution -> vlImg (rgb in-scatter, a transmittance).
//
// Overworld (air): marches the haze/mist layer from the camera to the first surface, with the
//   shadow map (single tap, from the cascade that contains the sample) and cloud shadows, so
//   light shafts appear through trees, windows and cloud gaps. Phase: hazePhase() (fog.glsl).
// Underwater: marches the water medium with sunlight attenuated through the water above each
//   sample (water depth from the all-geometry shadow map minus the opaque one).
// Nether: smoke with animated density, lit by the lava sea and the biome haze colour.
// The End: thin dust lit by the black hole's disk, with shadows.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/state.glsl"
#include "/lib/common/transform.glsl"
#define ATMOSPHERE_SAMPLERS
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/sky/celestial.glsl"
#include "/lib/lighting/shadow_proj.glsl"
#include "/lib/lighting/ambient.glsl"
#include "/lib/atmosphere/fog.glsl"
#ifdef WORLD_OVERWORLD
#include "/lib/clouds/clouds_common.glsl"
#endif
#ifdef WORLD_END
#include "/lib/lighting/emitters.glsl"
#include "/lib/space/end_sky.glsl"
#endif
#ifdef WORLD_NETHER
#include "/lib/nether/nether.glsl"
#endif

layout(local_size_x = 8, local_size_y = 8) in;
const vec2 workGroupsRender = vec2(0.5, 0.5);

uniform sampler2D depthtex0;
uniform sampler2D colortex4;
uniform sampler2DShadow shadowtex1HW;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
layout(rgba16f) uniform writeonly image2D vlImg;

// Single-tap shadow visibility and (optionally) water depth above the point along the light.
// Outside the shadow map nothing is known; treating those samples as fully lit while samples just
// inside are shadowed creates a plane through the camera that contains the light direction, which
// appears as a bright line through the sun (observed in game with an earlier pack). The coarsest
// cascade therefore fades to its average-ish value (lit) over its outer 15 %, and samples beyond
// it count as lit only by that faded amount.
float shadowVis(vec3 playerPos, mat3 Ls, out float waterDepth) {
    waterDepth = 0.0;
    vec3 lp = Ls * playerPos;
    for (int k = 0; k < 4; k++) {
        vec2 c = (lp.xy + state.cascadeCenter[k].xy) / cascadeExtent(k);
        float r = maxOf(abs(c));
        if (r < 0.97) {
            vec2 uv = cascadeOrigin(k) + (c * 0.5 + 0.5) * 0.5;
            float z = (-lp.z / SHADOW_Z_RANGE) * 0.5 + 0.5;
            float vis = texture(shadowtex1HW, vec3(uv, z - 0.0005));
            float dAll = texture(shadowtex0, uv).r;
            if (dAll < z) waterDepth = (z - dAll) * 2.0 * SHADOW_Z_RANGE;
            if (k == 3) vis = mix(vis, 1.0, smoothstep(0.82, 0.97, r));
            return vis;
        }
    }
    return 1.0;
}

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(vlImg);
    if (any(greaterThanEqual(px, size))) return;
    vec2 uv = (vec2(px) + 0.5) / vec2(size);
    float depth = texture(depthtex0, uv).r;
    vec3 viewPos = sceneToView(uv, depth);
    vec3 dirView = normalize(viewPos);
    vec3 dir = mat3(gbufferModelViewInverse) * dirView;
    float dist = depth < 1.0 ? length(viewPos) : far * 1.5;
    float noise = interleavedGradient(vec2(px) + float(frameCounter % 64) * 5.588238);
    mat3 Ls = shadowLightRotation();
    vec3 lightDir = shadowLightDirPlayer();

    vec3 scatter = vec3(0.0);
    vec3 T = vec3(1.0);

    #ifndef VOLUMETRIC_LIGHT
    imageStore(vlImg, px, vec4(0.0, 0.0, 0.0, 1.0));
    return;
    #endif

    #if defined WORLD_OVERWORLD
    SkyLights L = skyLights();
    bool underwater = isEyeInWater == 1;
    float maxD = underwater ? min(dist, 64.0) : min(dist, 240.0);
    float stepLen = maxD / float(VL_STEPS);
    vec3 eLight = (L.sunIsLight ? vec3(L.sunIllum) : L.moonIllum) * transmittanceToTop(cameraRadius(cameraPosition.y), lightDir.y);
    float cosL = dot(dir, lightDir);
    vec3 amb = skyIrradiance(vec3(0.0, 1.0, 0.0)) * PI * INV_4PI * skyVisibility(float(eyeBrightnessSmooth.y) / 240.0);
    if (underwater) {
        vec3 sigA = waterAbsorption();
        vec3 sigS = waterScattering(vec3(0.25, 0.55, 0.85));
        vec3 sigT = sigA + sigS;
        float ph = mix(phaseHG(cosL, 0.8), phaseHG(cosL, 0.0), 0.4);
        for (int i = 0; i < VL_STEPS; i++) {
            float t = (float(i) + noise) * stepLen;
            vec3 p = dir * t + relativeEyePosition * 0.0;
            float wd;
            float vis = shadowVis(p, Ls, wd);
            vec3 sunIn = eLight * vis * exp(-sigT * wd) * ph;
            vec3 S = sigS * (sunIn + amb * exp(-sigT * 4.0));
            vec3 stepT = exp(-sigT * stepLen);
            scatter += T * (S - S * stepT) / sigT;
            T *= stepT;
        }
    } else {
        float ph = hazePhase(cosL);
        for (int i = 0; i < VL_STEPS; i++) {
            float t = (float(i) + noise) * stepLen;
            vec3 p = dir * t;
            float sigma = hazeDensity(p.y + cameraPosition.y) * VL_STRENGTH;
            if (sigma <= 1e-7) continue;
            float wd;
            float vis = shadowVis(p, Ls, wd);
            #ifdef CLOUD_SHADOWS_ACTIVE
            vis *= cloudShadowAt(p + cameraPosition, lightDir);
            #endif
            vec3 S = sigma * (eLight * vis * ph + amb);
            float stepT = exp(-sigma * stepLen);
            scatter += T * (S - S * stepT) / sigma;
            T *= stepT;
        }
        // Haze beyond the marched range, analytically (no shadows that far).
        if (dist > maxD) {
            vec3 pEnd = dir * maxD;
            float sigma = hazeDensity(pEnd.y + cameraPosition.y) * VL_STRENGTH;
            float rest = min(dist - maxD, 2000.0);
            float tr = exp(-sigma * rest);
            scatter += T * sigma * (eLight * ph + amb) * (1.0 - tr) / max(sigma, 1e-7);
            T *= tr;
        }
        // Glare limit: haze toward the light may reach a few times the radiance of a sunlit white
        // surface (W) and is compressed smoothly beyond that, so dense mist reads as a bright glow
        // rather than a white disc tens of degrees wide. Tied to the light level, not exposure,
        // so it does not pump when the camera adapts.
        float W = luminance(eLight) * max(lightDir.y, 0.0) / PI + luminance(amb) * 4.0 / PI;
        float lumS = luminance(scatter);
        float knee = 2.5 * max(W, 1e-6);
        scatter *= inversesqrt(1.0 + sq(lumS / knee));
    }
    #elif defined WORLD_NETHER
    float maxD = min(dist, 160.0);
    float stepLen = maxD / float(VL_STEPS);
    vec3 haze = netherHazeColor();
    for (int i = 0; i < VL_STEPS; i++) {
        float t = (float(i) + noise) * stepLen;
        vec3 wp = dir * t + cameraPosition;
        float dens = 0.006 * NETHER_FOG_DENSITY;
        #ifdef NETHER_SMOKE
        vec3 q = wp * 0.045 + vec3(0.0, -frameTimeCounter * 0.08, frameTimeCounter * 0.03);
        float n = valueNoise(q) * 0.6 + valueNoise(q * 2.3) * 0.3 + valueNoise(q * 5.1) * 0.1;
        dens *= 0.35 + 1.6 * smoothstep(0.35, 0.8, n);
        #endif
        dens *= 0.6 + 0.4 * exp(-max(wp.y - 40.0, 0.0) / 60.0);
        vec3 light = haze * 2.5 + lavaGlow(wp.y) * 1.5;
        float stepT = exp(-dens * stepLen);
        scatter += T * light * (1.0 - stepT);
        T *= stepT;
    }
    #elif defined WORLD_END
    float maxD = min(dist, 200.0);
    float stepLen = maxD / float(VL_STEPS);
    vec3 eLight = endLightIlluminance();
    float ph = phaseHG(dot(dir, END_LIGHT_DIR), 0.6);
    for (int i = 0; i < VL_STEPS; i++) {
        float t = (float(i) + noise) * stepLen;
        vec3 p = dir * t;
        float sigma = 0.0012 * exp(-max(p.y + cameraPosition.y - 40.0, 0.0) / 80.0);
        float wd;
        float vis = shadowVis(p, Ls, wd);
        vec3 S = sigma * (eLight * vis * ph + vec3(0.02, 0.015, 0.03));
        float stepT = exp(-sigma * stepLen);
        scatter += T * (S - S * stepT) / sigma;
        T *= stepT;
    }
    #endif

    imageStore(vlImg, px, vec4(scatter, dot(T, vec3(1.0 / 3.0))));
}

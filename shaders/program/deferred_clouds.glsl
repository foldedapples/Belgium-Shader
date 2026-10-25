// deferred - volumetric cloud raymarch at reduced resolution (scale.deferred = CLOUD_RES).
// Writes in-scattered radiance (rgb) and transmittance (a) into the lower-left CLOUD_RES
// fraction of colortex8. The start offset is jittered per pixel and per frame with blue
// noise; deferred1 accumulates the samples over time.
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/frame_state.glsl"
#include "/lib/core/blue_noise.glsl"
#define ATMOSPHERE_LUTS
#define SKY_VIEW_READ
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/atmosphere/sky_view.glsl"
#include "/lib/clouds/clouds.glsl"
#include "/lib/compat/lod.glsl"
#include "/lib/post/color_profile.glsl"
#if CLOUD_SOURCE == 1
    #include "/lib/halcyon/halcyon_clouds.glsl"
#endif

uniform sampler2D depthtex0;

/* RENDERTARGETS: 8 */
layout(location = 0) out vec4 outClouds;

#if CLOUD_QUALITY == 0
    const int STEPS = 24;  const int LIGHT_STEPS = 3;
#elif CLOUD_QUALITY == 1
    const int STEPS = 32;  const int LIGHT_STEPS = 4;
#elif CLOUD_QUALITY == 2
    const int STEPS = 48;  const int LIGHT_STEPS = 5;
#elif CLOUD_QUALITY == 3
    const int STEPS = 64;  const int LIGHT_STEPS = 6;
#else
    const int STEPS = 96;  const int LIGHT_STEPS = 7;
#endif

CloudLighting cloudLighting() {
    CloudLighting lit;
    bool sunUp = fsSunDir.y > -0.12;
    lit.lightDir = sunUp ? fsSunDir.xyz : fsMoonDir.xyz;
    float rCloud = ATM_GROUND + max(fsCloud.z - 62.0, 0.0) * 1e-3 + 0.4;
    vec3 toa = sunUp ? fsSunIrradiance.rgb : fsMoonIrradiance.rgb;
    float radius = sunUp ? fsCelestialAxis.w : fsMoonParams.x;
    lit.lightIrradiance = toa * sunTransmittance(rCloud, lit.lightDir.y, radius) * CP_CLOUD_LIGHT;
    vec3 skyE = fsSkyIrradianceUp.rgb;
    lit.ambientTop = skyE * INV_PI * 1.15;
    lit.ambientBottom = skyE * INV_PI * 0.22 + lit.lightIrradiance * max(lit.lightDir.y, 0.0) * 0.08 * INV_PI;
    return lit;
}

void main() {
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * CLOUD_RES);
    if (any(greaterThan(uv, vec2(1.0))) || !frameStateValid()) { outClouds = vec4(0.0, 0.0, 0.0, 1.0); return; }

    // Nearest full-resolution depth of this low-resolution pixel's footprint centre.
    ivec2 fullPx = ivec2(uv * vec2(viewWidth, viewHeight));
    ScenePoint sp = scenePoint(uv, texelFetch(depthtex0, fullPx, 0).r, fullPx, true);
    vec3 dir = normalize(viewToSceneDir(normalize(sp.sky ? screenToView(uv, 1.0) : sp.view)));
    float maxDist = sp.sky ? 1e7 : sp.dist;

    float jitter = blueNoise(ivec2(gl_FragCoord.xy)).x;
    #if CLOUD_SOURCE == 1
        CloudResult c;
        float hcDepth;
        vec4 hc = halcyonCloudMarch(dir, maxDist, jitter, hcDepth);
        c.scattering = hc.rgb * CP_CLOUD_LIGHT;
        c.transmittance = hc.a;
        c.distance = hcDepth > 0.0 ? hcDepth : min(maxDist, 2.4e4);
    #else
        CloudResult c = marchClouds(dir, maxDist, jitter, cloudLighting(), STEPS, LIGHT_STEPS);
    #endif

    // Atmospheric haze between the camera and the cloud.
    if (c.transmittance < 1.0) {
        float dKm = c.distance * 1e-3;
        vec3 haze = exp(-(RAYLEIGH_SCATTERING * 0.6 + MIE_EXTINCTION * 0.5) * dKm * (1.0 + 2.0 * fsWeather.z));
        vec3 skyDir = normalize(vec3(dir.x, max(dir.y, 0.02), dir.z));
        c.scattering = c.scattering * haze + skyRadiance(skyDir) * (1.0 - haze) * (1.0 - c.transmittance);
        // Fade the farthest clouds into the sky instead of ending at a hard distance (Halcyon's
        // march already fades with distance itself).
        #if CLOUD_SOURCE == 1
            float fade = 1.0;
        #else
            float fade = 1.0 - smoothstep(CLOUD_MAX_DISTANCE * 0.7, CLOUD_MAX_DISTANCE, c.distance);
        #endif
        c.scattering *= fade;
        c.transmittance = mix(1.0, c.transmittance, fade);
    }
    outClouds = vec4(sanitizeRadiance(c.scattering), saturate(c.transmittance));
}
#endif

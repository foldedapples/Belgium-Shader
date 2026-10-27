// deferred compute: volumetric clouds at 1/CLOUD_RES resolution.
//   CLOUD_MARCH        deferred_a.csh  ray march -> cloudMarch (rgb in-scatter, a transmittance), cloudDist
//   CLOUD_RECONSTRUCT  deferred_b.csh  temporal reconstruction -> cloudHistA/B (by frame parity)
//
// March: jittered start (interleaved gradient noise rotated per frame) plus a per-frame sub-pixel
// offset inside each low-resolution pixel, so the temporal accumulation converges to a smooth,
// higher-resolution result. Empty space is crossed with long steps using the cheap weather map,
// dense space with short steps; the march stops when transmittance is below 1 %.
// Lighting: sun and moon via a short light march, multiple scattering by the octave
// approximation (Wrenninge et al. 2013), dual-lobe phase for silver linings, sky ambient from
// the SH sky projection (brighter at cloud tops), and aerial perspective towards the horizon.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/state.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/common/transform.glsl"
#define ATMOSPHERE_SAMPLERS
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/sky/celestial.glsl"
#include "/lib/lighting/ambient.glsl"
#define CLOUD_PRODUCER
#include "/lib/clouds/clouds_common.glsl"

layout(local_size_x = 8, local_size_y = 8) in;
#if CLOUD_RES == 1
const vec2 workGroupsRender = vec2(1.0, 1.0);
#elif CLOUD_RES == 2
const vec2 workGroupsRender = vec2(0.5, 0.5);
#else
const vec2 workGroupsRender = vec2(0.25, 0.25);
#endif

uniform sampler2D depthtex1;

#ifdef CLOUD_MARCH
layout(rgba16f) uniform writeonly image2D cloudMarch;
layout(r32f) uniform writeonly image2D cloudDist;

#if CLOUD_QUALITY == 0
const int PRIMARY_STEPS = 20; const int LIGHT_STEPS = 4;
#elif CLOUD_QUALITY == 1
const int PRIMARY_STEPS = 36; const int LIGHT_STEPS = 6;
#elif CLOUD_QUALITY == 2
const int PRIMARY_STEPS = 56; const int LIGHT_STEPS = 7;
#else
const int PRIMARY_STEPS = 96; const int LIGHT_STEPS = 9;
#endif

float lightOpticalDepth(vec3 p, vec3 l, CloudWeather w) {
    float od = 0.0;
    float step = 60.0;
    vec3 q = p;
    for (int i = 0; i < LIGHT_STEPS; i++) {
        q += l * step;
        CloudWeather wq = cloudWeatherAt(q.xz);
        float d = cloudDensity(q, wq, i < 2);
        od += cloudExtinction(d, wq.type) * step;
        step *= 1.6;
    }
    return od;
}

// Multiple-scattering octaves (Wrenninge et al. 2013): octave i has a^i energy, b^i extinction
// and c^i anisotropy. The truncated series underestimates the energy that diffuses through a thick
// cloud (its lit side should approach albedo * E / pi); the factor 2 restores that level, which
// was checked against the sunlit-cumulus brightness in the preview harness.
float scatterOctaves(float odLight, float cosTheta, float odView) {
    float s = 0.0;
    float a = 1.0, b = 1.0, c = 1.0;
    for (int i = 0; i < 4; i++) {
        float ph = mix(phaseHG(cosTheta, -0.2 * c), phaseHG(cosTheta, 0.82 * c), 0.62);
        s += a * ph * exp(-b * odLight);
        a *= 0.6; b *= 0.32; c *= 0.55;
    }
    return s * 2.0;
}

void main() {
    #ifndef VOLUMETRIC_CLOUDS
    return;
    #endif
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(cloudMarch);
    if (any(greaterThanEqual(px, size))) return;

    // Sub-pixel position inside the low-res pixel cycles every frame (temporal super-sampling).
    vec2 sub = r2(float(frameCounter % 64));
    vec2 uv = (vec2(px) + sub) / vec2(size);
    float depth = texture(depthtex1, uv).r;
    vec3 viewPos = screenToView(uv, 1.0, gbufferProjectionInverse);
    vec3 dir = normalize(mat3(gbufferModelViewInverse) * viewPos);
    float maxDist = 1e9;
    if (depth < 1.0) maxDist = length(screenToView(uv, depth, gbufferProjectionInverse));

    float camAlt = cameraPosition.y - 62.0;
    vec3 ro = vec3(0.0, PLANET_RADIUS + camAlt, 0.0);
    float rBase = PLANET_RADIUS + CLOUD_BASE, rTop = PLANET_RADIUS + cloudTop();
    vec2 hitTop = raySphere(ro, dir, rTop);
    vec2 hitBase = raySphere(ro, dir, rBase);
    float tStart, tEnd;
    if (camAlt < CLOUD_BASE) {
        // Below the layer: enter at the base, leave at the top (skip rays that hit the ground first).
        if (hitBase.y < 0.0) { imageStore(cloudMarch, px, vec4(0, 0, 0, 1)); imageStore(cloudDist, px, vec4(1e6)); return; }
        vec2 hitPlanet = raySphere(ro, dir, PLANET_RADIUS);
        if (hitPlanet.x > 0.0) { imageStore(cloudMarch, px, vec4(0, 0, 0, 1)); imageStore(cloudDist, px, vec4(1e6)); return; }
        tStart = hitBase.y; tEnd = hitTop.y;
    } else if (camAlt < cloudTop()) {
        tStart = 0.0;
        tEnd = hitBase.x > 0.0 ? hitBase.x : hitTop.y;
    } else {
        if (hitTop.x < 0.0) { imageStore(cloudMarch, px, vec4(0, 0, 0, 1)); imageStore(cloudDist, px, vec4(1e6)); return; }
        tStart = hitTop.x;
        tEnd = hitBase.x > 0.0 ? hitBase.x : hitTop.y;
    }
    tEnd = min(tEnd, min(tStart + 60000.0, maxDist));
    if (tEnd <= tStart) { imageStore(cloudMarch, px, vec4(0, 0, 0, 1)); imageStore(cloudDist, px, vec4(1e6)); return; }

    SkyLights L = skyLights();
    float rCloud = PLANET_RADIUS + CLOUD_BASE + 800.0;
    vec3 eSun = L.sunIllum * transmittanceToTop(rCloud, L.sunDir.y);
    vec3 eMoon = L.moonIllum * transmittanceToTop(rCloud, L.moonDir.y);
    vec3 ambTop = skyIrradiance(vec3(0.0, 1.0, 0.0)) * PI;
    vec3 ambBottom = skyIrradiance(vec3(0.0, -1.0, 0.0)) * PI + ambTop * 0.15;
    float cosS = dot(dir, L.sunDir), cosM = dot(dir, L.moonDir);

    // Two-rate march (mirrored and tested by tools/tests/test_cloud_march.py): coarse steps through
    // empty air; on the first coarse sample with cloud, step back one coarse step and continue with
    // fine steps; return to coarse steps after 6 empty fine samples. Fronts are found within one
    // fine step and thick clouds get at least 4 samples, so low-elevation rays (tens of km through
    // the shell) no longer band. Beyond 30 km the aerial-perspective fade takes over.
    tEnd = min(tEnd, tStart + 30000.0);
    float span = tEnd - tStart;
    float coarse = clamp(span / float(PRIMARY_STEPS), 60.0, 600.0);
    float fine = coarse * 0.25;
    float jitter = interleavedGradient(vec2(px) + float(frameCounter % 32) * 7.17);
    float t = tStart + coarse * jitter;
    vec3 T = vec3(1.0);
    vec3 scatter = vec3(0.0);
    float distSum = 0.0, distW = 0.0;
    vec3 camWorld = cameraPosition;
    bool inCloud = false;
    int emptyRun = 0;

    for (int i = 0; i < PRIMARY_STEPS * 3; i++) {
        if (t >= tEnd || T.g < 0.01) break;
        vec3 pPlanet = ro + dir * t;
        // World position: horizontal offset along the ray, height from the sphere.
        float h = length(pPlanet) - PLANET_RADIUS;
        vec3 wp = vec3(camWorld.x + dir.x * t, h + 62.0, camWorld.z + dir.z * t);
        CloudWeather w = cloudWeatherAt(wp.xz);
        if (!inCloud) {
            float probe = w.coverage > 0.02 ? cloudDensity(wp, w, false) : 0.0;
            if (probe > 0.0) {
                inCloud = true;
                emptyRun = 0;
                t = max(t - coarse, tStart) + fine * jitter;
                continue;
            }
            t += coarse;
            continue;
        }
        float d = cloudDensity(wp, w, true);
        float dt = fine;
        if (d > 0.0) {
            emptyRun = 0;
            float sigma = cloudExtinction(d, w.type);
            float h01 = saturate((h - CLOUD_BASE) / (cloudTop() - CLOUD_BASE));
            float odS = lightOpticalDepth(wp, L.sunDir, w);
            vec3 light = eSun * scatterOctaves(odS, cosS, 0.0);
            if (maxOf(eMoon) > 1e-6) light += eMoon * scatterOctaves(lightOpticalDepth(wp, L.moonDir, w), cosM, 0.0);
            vec3 amb = mix(ambBottom, ambTop, h01) * INV_4PI * mix(0.55, 1.0, h01);
            #ifdef LIGHTNING_FLASH
            // Lightning inside or below the storm: the cloud glows from within, strongest low down.
            amb += vec3(0.7, 0.75, 1.0) * lightningBoltPosition.w * 40.0 * (1.0 - h01) * INV_4PI;
            #endif
            vec3 S = (light + amb) * sigma;
            float stepT = exp(-sigma * dt);
            scatter += T * (S - S * stepT) / max(sigma, 1e-7);
            float absorbed = T.g * (1.0 - stepT);
            distSum += t * absorbed; distW += absorbed;
            T *= stepT;
        } else if (++emptyRun >= 6) {
            inCloud = false;
        }
        t += dt;
    }

    #ifdef CIRRUS_CLOUDS
    // Thin ice layer high above: 2D noise, lit with a mostly forward phase, behind the volume.
    vec2 hc = raySphere(ro, dir, PLANET_RADIUS + CIRRUS_ALTITUDE);
    if (hc.y > 0.0 && (depth >= 1.0)) {
        float tc = camAlt < CIRRUS_ALTITUDE ? hc.y : hc.x;
        vec3 pc = ro + dir * tc;
        vec2 xz = cameraPosition.xz + dir.xz * tc + state.cloudOffset.zw;
        vec2 wdir = windDirection();
        // Gentle stretch along the wind (1.4x) avoids the repeated-streak look of strong stretching.
        mat2 align = mat2(wdir.x, -wdir.y, wdir.y, wdir.x);
        vec2 q = align * xz / vec2(9000.0, 6300.0);
        // The noise texture has no mipmaps: octaves finer than the pixel footprint would alias into
        // sparkling streaks near the horizon (seen in game with an earlier pack), so each octave
        // fades to its mean once a texel is smaller than ~2 pixels.
        float footprint = tc * pixelAngularSize() * float(CLOUD_RES) / max(abs(dir.y), 0.03);   // metres
        float texel = 6300.0 / 512.0;                                                         // metres per texel, octave 1
        float f1 = 1.0 - smoothstep(1.0, 3.0, footprint / texel);
        float f2 = 1.0 - smoothstep(1.0, 3.0, footprint * 3.1 / texel);
        float f3 = 1.0 - smoothstep(1.0, 3.0, footprint * 7.3 / texel);
        float n = mix(0.5, texture(noise2dTex, q).r, f1) * 0.6
                + mix(0.5, texture(noise2dTex, q * 3.1 + 0.21).g, f2) * 0.3
                + mix(0.5, texture(noise2dTex, q * 7.3).a, f3) * 0.1;
        float cov = 0.45 + 0.25 * rainStrength;
        float od = saturate((n - (1.0 - cov)) * 2.5) * 0.35 * CIRRUS_AMOUNT;
        float fade = saturate(dir.y * 8.0);
        od *= fade;
        if (od > 0.0) {
            vec3 eS = L.sunIllum * transmittanceToTop(PLANET_RADIUS + CIRRUS_ALTITUDE, L.sunDir.y);
            vec3 eM = L.moonIllum * transmittanceToTop(PLANET_RADIUS + CIRRUS_ALTITUDE, L.moonDir.y);
            vec3 li = eS * mix(phaseHG(cosS, 0.6), phaseHG(cosS, -0.1), 0.3) + eM * phaseHG(cosM, 0.6) + ambTop * INV_4PI;
            float tr = exp(-od);
            scatter += T * li * (1.0 - tr) * 0.9;
            if (distW < 1e-4) { distSum = tc; distW = 1.0; }
            T *= mix(1.0, tr, 0.6);
        }
    }
    #endif

    float dist = distW > 1e-4 ? distSum / distW : 1e6;
    // Aerial perspective: distant clouds fade into the sky's own in-scatter.
    // The air between us and the cloud adds its own in-scatter (the horizon haze colour). Under
    // rain that air is lit by the overcast, so the haze is grey, not clear-sky blue.
    float fadeDist = 42000.0 / (1.0 + 0.35 * aerosolFactor());
    float airT = exp(-dist / fadeDist);
    vec3 haze = sampleSkyView(normalize(vec3(dir.x, max(dir.y, 0.03), dir.z)));
    haze = mix(haze, vec3(luminance(haze)) * 0.7, saturate(rainStrength * 0.9));
    scatter = scatter * airT + haze * (1.0 - T) * (1.0 - airT);
    imageStore(cloudMarch, px, vec4(scatter, dot(T, vec3(1.0 / 3.0))));
    imageStore(cloudDist, px, vec4(dist));
}
#endif

#ifdef CLOUD_RECONSTRUCT
uniform sampler2D cloudMarchSampler;
uniform sampler2D cloudDistSampler;
uniform sampler2D cloudHistSamplerA;
uniform sampler2D cloudHistSamplerB;
layout(rgba16f) uniform writeonly image2D cloudHistA;
layout(rgba16f) uniform writeonly image2D cloudHistB;

void main() {
    #ifndef VOLUMETRIC_CLOUDS
    return;
    #endif
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = textureSize(cloudMarchSampler, 0);
    if (any(greaterThanEqual(px, size))) return;
    vec2 uv = (vec2(px) + 0.5) / vec2(size);
    vec4 cur = texelFetch(cloudMarchSampler, px, 0);

    // 3x3 neighbourhood bounds of the current frame.
    vec4 mn = cur, mx = cur, m1 = vec4(0.0), m2 = vec4(0.0);
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        vec4 s = texelFetch(cloudMarchSampler, clamp(px + ivec2(i, j), ivec2(0), size - 1), 0);
        mn = min(mn, s); mx = max(mx, s);
        m1 += s; m2 += s * s;
    }
    m1 /= 9.0; m2 /= 9.0;
    vec4 sd = sqrt(max(m2 - m1 * m1, 0.0));

    // Reproject through the cloud's distance.
    float dist = min(texelFetch(cloudDistSampler, px, 0).r, 2e5);
    vec3 viewPos = screenToView(uv, 1.0, gbufferProjectionInverse);
    vec3 dir = normalize(mat3(gbufferModelViewInverse) * viewPos);
    vec3 worldP = dir * dist + cameraPosition;
    vec3 prevPlayer = worldP - previousCameraPosition;
    vec3 prevView = mat3(gbufferPreviousModelView) * prevPlayer;
    vec3 prevScreen = viewToScreen(prevView, gbufferPreviousProjection);
    bool valid = all(greaterThan(prevScreen.xy, vec2(0.0))) && all(lessThan(prevScreen.xy, vec2(1.0))) && prevView.z < 0.0;

    vec4 hist = cur;
    if (valid) hist = (frameCounter & 1) == 0 ? texture(cloudHistSamplerB, prevScreen.xy) : texture(cloudHistSamplerA, prevScreen.xy);
    // Variance clipping keeps history from ghosting when the clouds or the view change.
    vec4 lo = max(mn, m1 - sd * 1.25), hi = min(mx, m1 + sd * 1.25);
    hist = clamp(hist, lo, hi);
    float blend = valid ? 0.12 : 1.0;
    // Faster response when the camera is moving quickly.
    blend = max(blend, saturate(length(cameraPosition - previousCameraPosition) * 0.05));
    vec4 res = mix(hist, cur, blend);
    if (any(isnan(res))) res = vec4(0, 0, 0, 1);
    if ((frameCounter & 1) == 0) imageStore(cloudHistA, px, res);
    else imageStore(cloudHistB, px, res);
}
#endif

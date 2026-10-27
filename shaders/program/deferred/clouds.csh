// deferred compute: volumetric clouds at 1/CLOUD_RES resolution.
//   CLOUD_MARCH        deferred_a.csh  ray march -> cloudMarch (rgb in-scatter, a transmittance), cloudDist
//   CLOUD_RECONSTRUCT  deferred_b.csh  temporal reconstruction -> cloudHistA/B (by frame parity)
//
// March: jittered start (interleaved gradient noise rotated per frame) plus a per-frame sub-pixel
// offset inside each low-resolution pixel, so the temporal accumulation converges to a smooth,
// higher-resolution result. Empty space is crossed with long steps using the cheap weather map,
// dense space with short steps; the march stops when transmittance is below 1 %.
// Lighting: sun and moon via a short light march (each only while it matters), multiple
// scattering by the octave approximation (Wrenninge et al. 2013) with a depth build-up for the
// higher octaves, dual-lobe phase for silver linings, sky ambient from the SH sky projection
// shaded by the cloud above each sample (dark cumulonimbus interiors), lightning, and aerial
// perspective towards the horizon. The density model and weather map are in
// lib/clouds/clouds_common.glsl.

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
#if CLOUD_RES == 1 || defined(CLOUD_RECONSTRUCT)
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

// Quality tiers. Low: no edge erosion, short light march; Cinematic: long marches, every light
// sample at full detail. All tiers use the same scattering octaves so brightness matches.
#if CLOUD_QUALITY == 0
const int PRIMARY_STEPS = 20; const int LIGHT_STEPS = 4; const int PRIMARY_LOD = 1; const int LIGHT_DETAIL = 1;
#elif CLOUD_QUALITY == 1
const int PRIMARY_STEPS = 36; const int LIGHT_STEPS = 6; const int PRIMARY_LOD = 2; const int LIGHT_DETAIL = 2;
#elif CLOUD_QUALITY == 2
const int PRIMARY_STEPS = 56; const int LIGHT_STEPS = 7; const int PRIMARY_LOD = 2; const int LIGHT_DETAIL = 2;
#elif CLOUD_QUALITY == 3
const int PRIMARY_STEPS = 96; const int LIGHT_STEPS = 9; const int PRIMARY_LOD = 2; const int LIGHT_DETAIL = 3;
#else
const int PRIMARY_STEPS = 128; const int LIGHT_STEPS = 12; const int PRIMARY_LOD = 2; const int LIGHT_DETAIL = 12;
#endif

// Optical depth towards the light: geometrically growing steps (60 m, x1.6). The first few
// samples stay within a few hundred metres of the column, so they reuse its weather; the first
// LIGHT_DETAIL samples use the full shape, the far ones the one-fetch shape.
float lightOpticalDepth(vec3 p, vec3 l, CloudWeather w) {
    float od = 0.0;
    float step = 60.0;
    vec3 q = p;
    CloudWeather wq = w;
    for (int i = 0; i < LIGHT_STEPS; i++) {
        q += l * step;
        if (q.y - 62.0 > cloudTop()) break;
        if (i >= 3) wq = cloudWeatherAt(q.xz);
        float d = cloudDensity(q, wq, i < LIGHT_DETAIL ? 1 : 0);
        od += cloudExtinction(d) * step;
        step *= 1.6;
    }
    return od;
}

// Multiple-scattering octaves (Wrenninge et al. 2013): octave i has a^i energy, b^i extinction
// and c^i anisotropy. The truncated series underestimates the energy that diffuses through a thick
// cloud (its lit side should approach albedo * E / pi); the factor 2 restores that level, which
// was checked against the sunlit-cumulus brightness in the preview harness.
//
// Multiply scattered light needs some depth to build up: just inside the sunlit surface there is
// little of it, which is what makes the folds of a cumulus read as rounded volumes instead of
// flat white cut-outs (the "powder" darkening of sunward edges). Applied to the higher octaves
// only, so thin cloud keeps its single-scattered silver lining.
float scatterOctaves(float odLight, float cosTheta, float odView) {
    float s = 0.0;
    float a = 1.0, b = 1.0, c = 1.0;
    float buildUp = 1.0 - 0.6 * exp(-odLight * 1.5);
    for (int i = 0; i < 4; i++) {
        float ph = mix(phaseHG(cosTheta, -0.2 * c), phaseHG(cosTheta, 0.82 * c), 0.62);
        s += a * ph * exp(-b * odLight) * (i == 0 ? 1.0 : buildUp);
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
    vec2 sub = r2(float(NOISE_FRAME % 64));
    vec2 uv = (vec2(px) + sub) / vec2(size);
    float depth = texture(depthtex1, uv).r;
    vec3 viewPos = screenToView(uv, 1.0, gbufferProjectionInverse);
    vec3 dir = normalize(mat3(gbufferModelViewInverse) * viewPos);
    float maxDist = 1e9;
    if (depth < 1.0) maxDist = length(sceneToView(uv, depth));

    float camAlt = cameraPosition.y - 62.0;
    vec3 ro = vec3(0.0, PLANET_RADIUS + camAlt, 0.0);
    float rBase = PLANET_RADIUS + cloudShellBase(), rTop = PLANET_RADIUS + cloudTop();
    vec2 hitTop = raySphere(ro, dir, rTop);
    vec2 hitBase = raySphere(ro, dir, rBase);
    float tStart, tEnd;
    if (camAlt < cloudShellBase()) {
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
    // Each light gets its own light march only when it matters: a daytime moon adds < 0.2 % to
    // sunlight, and the sun is below the horizon all night, yet both used to be marched for every
    // lit sample.
    bool moonLit = maxOf(eMoon) > 1e-6 && luminance(eMoon) > 0.002 * luminance(eSun);
    bool sunLit = maxOf(eSun) > 1e-6 && luminance(eSun) > 0.002 * luminance(eMoon);
    vec3 ambTop = skyIrradiance(vec3(0.0, 1.0, 0.0)) * PI;
    vec3 ambBottom = skyIrradiance(vec3(0.0, -1.0, 0.0)) * PI + ambTop * 0.15;
    float cosS = dot(dir, L.sunDir), cosM = dot(dir, L.moonDir);

    // Two-rate march: coarse steps through
    // empty air; on the first coarse sample with cloud, step back one coarse step and continue with
    // fine steps; return to coarse steps after 6 empty fine samples. Fronts are found within one
    // fine step and thick clouds get at least 4 samples, so low-elevation rays (tens of km through
    // the shell) no longer band. Beyond 30 km the aerial-perspective fade takes over.
    tEnd = min(tEnd, tStart + 30000.0);
    float span = tEnd - tStart;
    float coarse = clamp(span / float(PRIMARY_STEPS), 60.0, 600.0);
    float fine = coarse * 0.25;
    float jitter = interleavedGradient(vec2(px) + float(NOISE_FRAME % 32) * 7.17);
    float pixelSize = pixelAngularSize() * float(CLOUD_RES);    // radians per march pixel
    float t = tStart + coarse * jitter;
    vec3 T = vec3(1.0);
    vec3 scatter = vec3(0.0);
    float distSum = 0.0, distW = 0.0;
    vec3 camWorld = cameraPosition;
    bool inCloud = false;
    int emptyRun = 0;
    #if DEBUG_VIEW == 26
    vec3 dbgDirect = vec3(0.0), dbgAmbient = vec3(0.0);
    #endif

    for (int i = 0; i < PRIMARY_STEPS * 3; i++) {
        if (t >= tEnd || T.g < 0.01) break;
        vec3 pPlanet = ro + dir * t;
        // World position: horizontal offset along the ray, height from the sphere.
        float h = length(pPlanet) - PLANET_RADIUS;
        vec3 wp = vec3(camWorld.x + dir.x * t, h + 62.0, camWorld.z + dir.z * t);
        CloudWeather w = cloudWeatherAt(wp.xz);
        if (!inCloud) {
            // Same shape as the fine samples minus erosion (which only removes density), so the
            // probe never steps over a cloud the fine march would see.
            float probe = (w.coverage > 0.02 || w.anvil > 0.01) ? cloudDensity(wp, w, 1) : 0.0;
            if (probe > 0.0) {
                inCloud = true;
                emptyRun = 0;
                t = max(t - coarse, tStart) + fine * jitter;
                continue;
            }
            t += coarse;
            continue;
        }
        float d = cloudDensity(wp, w, PRIMARY_LOD, t * pixelSize);
        float dt = fine;
        if (d > 0.0) {
            emptyRun = 0;
            float sigma = cloudExtinction(d);
            float h01 = saturate((h - w.base) / (w.top - w.base));
            float odS = sunLit ? lightOpticalDepth(wp, L.sunDir, w) : 0.0;
            vec3 light = sunLit ? eSun * scatterOctaves(odS, cosS, 0.0) : vec3(0.0);
            if (moonLit) light += eMoon * scatterOctaves(lightOpticalDepth(wp, L.moonDir, w), cosM, 0.0);
            // Sky light from above is shaded by the cloud over the sample: with multiple scattering
            // it diffuses down gently, ~0.75 at the base of a 2 km fair-weather cumulus, ~0.9 under
            // thin stratus, ~0.1 at the base of a 9 km cumulonimbus, which gives storm towers their
            // dark interiors without greying fair-weather clouds.
            float skyAo = max(exp(-2.55e-4 * (w.top - h) * sqrt(w.coverage) * w.density * CLOUD_DENSITY), 0.1);
            // Isotropic in-scatter of the light arriving from each hemisphere is E / (2 pi): sky from
            // above (shaded by the cloud over the sample), ground and cloud-reflected light from below
            // (less of it reaches the upper parts). The old E / (4 pi) of a blend of the two halved
            // the light on every shadowed side, which made fair-weather clouds a muddy grey.
            vec3 amb = (ambTop * mix(skyAo, 1.0, h01 * h01) + ambBottom * mix(1.0, 0.3, h01)) * (0.5 * INV_PI);
            #ifdef LIGHTNING_FLASH
            // Lightning inside or below the storm: the cloud glows from within, strongest low down.
            amb += vec3(0.7, 0.75, 1.0) * lightningBoltPosition.w * 40.0 * (1.0 - h01) * INV_4PI;
            #endif
            vec3 S = (light + amb) * sigma;
            float stepT = exp(-sigma * dt);
            scatter += T * (S - S * stepT) / max(sigma, 1e-7);
            #if DEBUG_VIEW == 26
            dbgDirect += T * light * (1.0 - stepT);
            dbgAmbient += T * amb * (1.0 - stepT);
            #endif
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
        vec2 worldXZ = cameraPosition.xz + dir.xz * tc;
        vec2 xz = worldXZ - state.cloudOffset.zw;
        // Fibrous strands aligned with the mean wind direction (36.9 degrees, a Pythagorean
        // rotation) and stretched 3.5x along it. Rational cos/sin and whole tiles per
        // CLOUD_WRAP / 5 keep the pattern periodic over the offset wrap (any integer tile counts
        // work: 0.8 * 5 and 0.6 * 5 are integers).
        const mat2 ALIGN = mat2(0.8, -0.6, 0.6, 0.8);
        vec2 q = (ALIGN * xz) * (vec2(2.0, 7.0) / (CLOUD_WRAP / 5.0));
        // The noise texture has no mipmaps: octaves finer than the pixel footprint would alias into
        // sparkling streaks near the horizon (seen in game with an earlier pack), so each octave
        // fades to its mean once a texel is smaller than ~2 pixels.
        float footprint = tc * pixelAngularSize() * float(CLOUD_RES) / max(abs(dir.y), 0.03);   // metres
        float texel = CLOUD_WRAP / 35.0 / 512.0;                                              // metres per texel across the strands, octave 1
        float f1 = 1.0 - smoothstep(1.0, 3.0, footprint / texel);
        float f2 = 1.0 - smoothstep(1.0, 3.0, footprint * 3.0 / texel);
        float f3 = 1.0 - smoothstep(1.0, 3.0, footprint * 7.0 / texel);
        float n = mix(0.5, texture(noise2dTex, q).r, f1) * 0.6
                + mix(0.5, texture(noise2dTex, q * 3.0 + 0.21).g, f2) * 0.3
                + mix(0.5, texture(noise2dTex, q * 7.0).a, f3) * 0.1;
        // Cirrus run ahead of weather systems: more of it where the large-scale field is lower
        // pressure, little under settled high pressure. Sparse (mean cover ~0.34, so about 15 %
        // of the sky shows strands) and thin: it should never dominate the sky.
        float cov = 0.18 + 0.32 * cloudSystems(worldXZ - state.weatherOffset.xy) + 0.2 * rainStrength;
        float od = saturate((n - (1.0 - cov)) * 2.5) * 0.3 * CIRRUS_AMOUNT;
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
    #if DEBUG_VIEW == 25
    // Weather map where the ray enters the layer: r coverage (cloud fraction), g type (0.1 stratus,
    // 0.35 stratocumulus, 0.6 cumulus, 1 cumulonimbus), b size (small .. large cumulus).
    vec3 wpDbg = cameraPosition + dir * tStart;
    CloudWeather wDbg = cloudWeatherAt(wpDbg.xz);
    scatter = vec3(wDbg.coverage, wDbg.type, wDbg.size);
    #elif DEBUG_VIEW == 26
    // Lighting: r direct sun and moon scattering, g sky ambient (x4), b optical depth (1 - T).
    scatter = vec3(luminance(dbgDirect), luminance(dbgAmbient) * 4.0, 0.0) * state.exposure;
    scatter = vec3(1.0 - exp(-scatter.rg), 1.0 - dot(T, vec3(1.0 / 3.0)));
    #endif
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

// Temporal super-resolution: the history is full resolution. Each frame the march takes one
// sample per low-resolution pixel at a sub-pixel position that cycles through an R2 sequence;
// every full-resolution pixel takes in that sample in proportion to how close it fell, so over a
// few frames each full-resolution pixel gathers samples from its own area. Before, the history
// was low resolution and each jittered sample was stored as if taken at the pixel centre: the
// accumulation box-filtered the detail away and the consumers stretched the result bilinearly,
// so cloud edges were soft and smeared.
void main() {
    #ifndef VOLUMETRIC_CLOUDS
    return;
    #endif
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(cloudHistA);
    if (any(greaterThanEqual(px, size))) return;
    ivec2 lowSize = textureSize(cloudMarchSampler, 0);
    vec2 uv = (vec2(px) + 0.5) / vec2(size);
    ivec2 lp = min(ivec2(uv * vec2(lowSize)), lowSize - 1);

    // 3x3 low-resolution neighbourhood of the current frame: bounds for the history.
    vec4 mn = vec4(1e9), mx = vec4(-1e9), m1 = vec4(0.0), m2 = vec4(0.0);
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        vec4 s = texelFetch(cloudMarchSampler, clamp(lp + ivec2(i, j), ivec2(0), lowSize - 1), 0);
        mn = min(mn, s); mx = max(mx, s);
        m1 += s; m2 += s * s;
    }
    m1 /= 9.0; m2 /= 9.0;
    vec4 sd = sqrt(max(m2 - m1 * m1, 0.0));
    // This frame's sample of the low-resolution pixel and where it was taken (as in the march).
    vec4 smp = texelFetch(cloudMarchSampler, lp, 0);
    vec2 smpUv = (vec2(lp) + r2(float(NOISE_FRAME % 64))) / vec2(lowSize);
    vec2 dPix = (smpUv - uv) * vec2(size);                       // in full-resolution pixels
    float near = exp(-dot(dPix, dPix) * 1.4);                     // ~1 inside this pixel, ~0.25 one pixel away

    // Reproject through the cloud's distance.
    float dist = min(texelFetch(cloudDistSampler, lp, 0).r, 2e5);
    vec3 viewPos = screenToView(uv, 1.0, gbufferProjectionInverse);
    vec3 dir = normalize(mat3(gbufferModelViewInverse) * viewPos);
    vec3 worldP = dir * dist + cameraPosition;
    // The cloud itself moved downwind since the last frame (same rate as begin.csh integrates).
    worldP.xz -= windDirection() * ((6.0 + 14.0 * windStrength()) * CLOUD_SPEED * clamp(frameTime, 0.0, 0.1));
    vec3 prevPlayer = worldP - previousCameraPosition;
    vec3 prevView = mat3(gbufferPreviousModelView) * prevPlayer;
    vec3 prevScreen = viewToScreen(prevView, gbufferPreviousProjection);
    bool valid = all(greaterThan(prevScreen.xy, vec2(0.0))) && all(lessThan(prevScreen.xy, vec2(1.0))) && prevView.z < 0.0;

    vec4 res;
    if (valid) {
        vec4 hist = (frameCounter & 1) == 0 ? texture(cloudHistSamplerB, prevScreen.xy) : texture(cloudHistSamplerA, prevScreen.xy);
        // Variance clipping keeps history from ghosting when the clouds or the view change.
        hist = clamp(hist, max(mn, m1 - sd * 1.25), min(mx, m1 + sd * 1.25));
        // A sample that fell in this pixel counts fully; the neighbours' samples (interpolated) a
        // little, so no pixel goes stale. Faster response when the camera moves quickly.
        float a = max(0.2 * near, saturate(length(cameraPosition - previousCameraPosition) * 0.05));
        res = mix(hist, texture(cloudMarchSampler, uv), 0.03);
        res = mix(res, smp, a);
    } else {
        res = texture(cloudMarchSampler, uv);
    }
    if (any(isnan(res))) res = vec4(0, 0, 0, 1);
    #if DEBUG_VIEW == 27
    // Temporal reconstruction: red where the history could not be reprojected (disocclusion, screen
    // edge), green how strongly this frame's sample was taken in (0.2 = a sample fell in the pixel).
    res = vec4(valid ? 0.0 : 1.0, valid ? max(0.2 * near, saturate(length(cameraPosition - previousCameraPosition) * 0.05)) * 5.0 : 0.0, 0.0, 1.0);
    #endif
    if ((frameCounter & 1) == 0) imageStore(cloudHistA, px, res);
    else imageStore(cloudHistB, px, res);
}
#endif

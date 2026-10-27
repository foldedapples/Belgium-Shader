#ifndef MERIDIAN_CLOUDS_COMMON
#define MERIDIAN_CLOUDS_COMMON

#include "/lib/common/math.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

// Volumetric cloud model shared by the cloud march (deferred compute), the cloud shadow map
// (prepare compute) and the consumers (lighting, fog).
//
// Geometry: a spherical shell around a planet of PLANET_RADIUS from cloudShellBase() (the lowest
// stratus) to cloudTop() (towering cumulus; 9 km cumulonimbus with anvils in thunderstorms). Each
// column has its own cloud type, base and top. Cirrus is a separate thin layer at 8.5 km
// (program/deferred/clouds.csh).
//
// Where clouds form and what they look like are separate controls (cloudWeatherAt):
//   sky cover   the fraction of the sky seen covered, from CLOUD_COVERAGE, ~40 km weather systems
//               (high pressure: open sky; low pressure: banks), a daily regime (some days are
//               clearer than others), rain and thunder
//   groups      a domain-warped 0.5-3.6 km field: clouds form in groups with clear sky between;
//               in a sparse sky the groups are loose fields of small cumulus, in a full sky they
//               merge into banks with gaps
//   coverage    the fraction of the volume inside a group that is cloud, derived from the sky
//               cover and the column's thickness (tall clouds overlap more when seen from below;
//               calibrated with tools/cloud_preview.py)
//   type, size, base, top, density, anvil   per column, from the systems and an instability field
// The density function (cloudDensity) then carves the clouds out of a 3D noise whose values are
// equalised to roughly uniform, so `coverage` really is the cloud fraction: at 0.2 the noise's
// peaks become separate cumulus, at 0.8 they merge into a bank with holes. The old model
// thresholded a noise that was 0.69 +- 0.14 against coverage 0.4-0.85, so every group became one
// solid grey mass with odd openings.
//
// Tiling: the wind offsets wrap every CLOUD_WRAP metres (program/begin/frame_setup.csh). Every
// noise sampled at (x - offset) therefore repeats a whole number of times per wrap, or clouds
// would jump at the wrap. The tile counts per wrap (1, 3, 5, 11, 23, 32, 64, 128, 256) are chosen
// so the patterns never line up visibly. Formations drift with state.weatherOffset (80 % of the
// cloud speed), the cloud elements with state.cloudOffset: clouds slowly form at one side of a
// group and dissolve at the other instead of the whole pattern sliding rigidly.

uniform sampler3D cloudShapeTex;   // r Perlin-Worley, gba inverted Worley octaves (128^3)
uniform sampler3D cloudDetailTex;  // rgb Worley octaves (32^3)
uniform sampler2D noise2dTex;

const float CLOUD_WRAP = 131072.0;
const float CLOUD_BASE = float(CLOUD_ALTITUDE);                 // cumulus base, m above sea level
const float STRATUS_BASE = max(CLOUD_BASE * 0.55, 450.0);
const float CLOUD_SHELL_BASE = min(STRATUS_BASE, CLOUD_BASE - 250.0);
const float CLOUD_TOP_LOW = CLOUD_BASE + 2600.0;                // tallest cumulus congestus
const float CLOUD_TOP_STORM = 9000.0;
const float ANVIL_BASE = 7000.0;                                // cumulonimbus anvils spread above this
const float CIRRUS_ALTITUDE = 8500.0;
const float SHAPE_TILE = CLOUD_WRAP / 32.0;     // 4096 m: large cumulus, congestus
const float SHAPE_TILE_S = CLOUD_WRAP / 64.0;   // 2048 m: small fair-weather cumulus
const float SHAPE_TILE_2 = CLOUD_WRAP / 23.0;   // 5699 m: Worley modulation, breaks up repetition
const float FINE_TILE = CLOUD_WRAP / 128.0;     // 1024 m: fine billows (40-80 m) from the shape texture
const float DETAIL_TILE = CLOUD_WRAP / 256.0;   // 512 m: erosion (85-250 m)
// Vertical frequency of the shape noise relative to horizontal: below 1 a cloud is coherent from
// base to top (towers rather than stacked blobs).
const vec3 SHAPE_STRETCH = vec3(1.0, 0.65, 1.0);
// Share of the cellular channel (inverted Worley) in the shape: cells stay separate up to higher
// cloud fractions than Perlin-Worley alone, which merges into one mass near half coverage (in a
// 2D slice at 40 % cover the largest cloud holds 5 % of the cloud instead of 16 %).
const float CELL_SHARE = 0.65;

float cloudShellBase() { return CLOUD_SHELL_BASE; }
float cloudTop() {
    #ifdef CUMULONIMBUS
    return mix(CLOUD_TOP_LOW, CLOUD_TOP_STORM, thunderStrength);
    #else
    return CLOUD_TOP_LOW;
    #endif
}

struct CloudWeather {
    float coverage;  // 0..1 fraction of the volume that is cloud (where the noise exceeds 1 - coverage)
    float type;      // 0.08 stratus, 0.35 stratocumulus, 0.6 cumulus, 1 cumulonimbus
    float base;      // m above sea level
    float top;
    float density;   // local density (liquid water), independent of coverage
    float size;      // 0 small humilis .. 1 large congestus
    float anvil;     // cumulonimbus anvil above ANVIL_BASE, 0..1
};

vec4 weatherNoise(vec2 x, float tilesPerWrap) { return texture(noise2dTex, x * (tilesPerWrap / CLOUD_WRAP)); }

// Large-scale weather systems, 0 (high pressure) .. 1 (low pressure). The noise channels are
// roughly normal; a smoothstep over +-2 sigma maps them to ~uniform (distributions measured
// from textures/noise2d.png), a second one pushes more of the area towards settled extremes:
// whole skies that are nearly clear or mostly cloudy, not one partly cloudy sky everywhere.
float systemsFrom(vec4 a, vec4 b) {
    return smoothstep(0.1, 0.9, smoothstep(0.236, 0.799, a.r * 0.8 + b.b * 0.2));
}

float cloudSystems(vec2 p) {
    #ifdef WEATHER_CLOUDS
    return systemsFrom(weatherNoise(p, 1.0), weatherNoise(p + 7919.0, 3.0));
    #else
    return 0.5;
    #endif
}

CloudWeather cloudWeatherAt(vec2 xz) {
    vec2 p = xz - state.weatherOffset.xy;
    vec4 a = weatherNoise(p, 1.0);
    vec4 b = weatherNoise(p + 7919.0, 3.0);
    #ifdef WEATHER_CLOUDS
    float systems = systemsFrom(a, b);
    float day = state.weatherOffset.z;      // daily regime, eased in frame_setup.csh
    #else
    float systems = 0.5;
    float day = 0.0;
    #endif
    // Domain warp from the large fields bends the group field into irregular shapes.
    vec2 warp = (vec2(a.g, b.g) - 0.5) * 2600.0;
    vec4 c = weatherNoise(p + warp, 11.0);
    vec4 d = weatherNoise(p + warp * 0.5 + 3313.0, 5.0);
    float cluster = smoothstep(0.328, 0.748, d.g * 0.55 + c.g * 0.30 + c.a * 0.15);
    float convective = smoothstep(0.226, 0.854, d.b);

    // Sky cover: CLOUD_COVERAGE on average, from almost none under high pressure to mostly
    // cloudy under low pressure. The swing shrinks near 0 and 1 so clipping does not shift the
    // average, and stays below 0.9 so the default sky is never overcast without rain.
    const float SWING = min(0.9, 2.0 * min(CLOUD_COVERAGE, 1.0 - CLOUD_COVERAGE));
    float target = CLOUD_COVERAGE + (systems - 0.5) * SWING + day + rainStrength * 0.5 + thunderStrength * 0.2;
    target = saturate(target);

    // Type: fair-weather cumulus, stratocumulus under low pressure, towers where unstable,
    // stratus only in a nearly overcast deep low with stable air and in steady rain,
    // cumulonimbus cells in thunder.
    float t = mix(0.34, 0.62, 1.0 - smoothstep(0.35, 0.8, systems));
    t = clamp(t + (convective - 0.5) * 0.35, 0.2, 0.8);
    t = mix(t, 0.1, smoothstep(0.8, 0.95, target) * smoothstep(0.85, 1.0, systems) * smoothstep(0.55, 0.8, 1.0 - convective));
    t = mix(t, 0.08, rainStrength * (1.0 - thunderStrength) * 0.8);
    #ifdef CUMULONIMBUS
    t = mix(t, 1.0, thunderStrength * smoothstep(0.55, 0.8, convective));
    #endif
    float stratus = 1.0 - smoothstep(0.1, 0.3, t);
    float cu = smoothstep(0.35, 0.62, t);
    float cb = smoothstep(0.82, 1.0, t);

    CloudWeather w;
    w.type = t;
    // Size: small humilis where the air is stable, large congestus where it is unstable.
    w.size = saturate(0.65 * convective + 0.35 * smoothstep(0.3, 0.7, c.r));
    // Bases: higher where the air is unstable (higher condensation level), stratus low.
    w.base = mix(CLOUD_BASE + (convective - 0.5) * 400.0, STRATUS_BASE, stratus);
    // Thickness: stratus ~450 m, stratocumulus ~800 m, cumulus 0.35 (humilis) to 2.5 km
    // (congestus), cumulonimbus to 9 km.
    float thick = mix(450.0, 800.0, smoothstep(0.08, 0.35, t));
    thick = mix(thick, 350.0 + 2200.0 * w.size * sqrt(w.size), cu);
    thick = mix(thick, CLOUD_TOP_STORM - w.base, cb);
    w.top = min(w.base + thick, cloudTop());

    // Groups: about `share` of the area is inside a group, which itself is `inGroup` covered as
    // seen from below. A sparse sky: most of the area holds loose groups; a full sky: dense banks.
    float inGroup = 0.2 + 0.75 * target;
    float share = min(target / inGroup, 1.0);
    float group = smoothstep(1.0 - share - 0.12, 1.0 - share + 0.12, cluster);
    // Volume fraction that gives that sky cover: seen from below, a column of n independent
    // layers is covered 1 - (1 - c)^n; n grows with the cloud's thickness (measured on the shape
    // noise with tools/cloud_preview.py: ~1.3 for stratocumulus, 1 + 1.25 per km for cumulus).
    float n = mix(1.3, 1.0 + 1.25e-3 * (w.top - w.base), cu);
    w.coverage = (1.0 - pow(1.0 - min(inGroup, 0.995), 1.0 / n)) * group;
    // Overcast in rain: a near-continuous sheet (nimbostratus) with slight variation.
    w.coverage = max(w.coverage, rainStrength * (0.85 + 0.15 * smoothstep(0.2, 0.7, c.b)));

    // Local density: more liquid water in unstable air and in storms, less in stratus; varies
    // from cloud to cloud so a group is not uniformly bright.
    w.density = mix(0.75, 1.15, convective) * mix(0.85, 1.15, c.b);
    w.density = mix(w.density, 0.6, stratus) * (1.0 + 0.5 * rainStrength) * mix(1.0, 1.6, cb);

    // Anvils spread from the storm cells downwind over a wider area than the cells themselves.
    w.anvil = 0.0;
    #ifdef CUMULONIMBUS
    if (thunderStrength > 0.0) {
        float upwind = weatherNoise(p + warp * 0.5 + 3313.0 - windDirection() * 3000.0, 5.0).b;
        w.anvil = thunderStrength * smoothstep(0.35, 0.65, smoothstep(0.226, 0.854, max(upwind, d.b)));
    }
    #endif
    return w;
}

// Fraction of the column's coverage present at height h01 (0 base .. 1 top). Applied to the
// threshold rather than as a density multiplier, so the cloud's cross-section narrows upward
// (domes, towers) and the base is flat, instead of the whole cloud fading.
float coverageProfile(float h01, float type) {
    float cu = smoothstep(0.35, 0.62, type);
    float st = 1.0 - smoothstep(0.1, 0.3, type);
    float cb = smoothstep(0.82, 1.0, type);
    float bottom = smoothstep(0.0, mix(mix(0.15, 0.06, cu), 0.25, st), h01);
    float t0 = mix(mix(mix(0.55, 0.2, cu), 0.6, st), 0.8, cb);
    float top = 1.0 - smoothstep(t0, 1.0, h01);
    return bottom * pow(top, mix(1.0, 0.7, cu));
}

// Map a roughly normal noise (mean, sd) to roughly uniform 0..1.
float equalise(float x, float mean, float sd) { return smoothstep(mean - 2.0 * sd, mean + 2.0 * sd, x); }

// Erosion drift, rounded to whole tiles per hour so the frameTimeCounter wrap at 3600 s is
// invisible.
const float DETAIL_DRIFT = round(0.004 * CLOUD_SPEED * 3600.0) / 3600.0;
const float FINE_DRIFT = round(0.002 * CLOUD_SPEED * 3600.0) / 3600.0;

// lod 0: one shape fetch (far light samples only: an approximation); 1: two-scale shape with the
// Worley modulation (the empty-space probe and the shadow map, so both match the visible clouds);
// 2: plus edge erosion (primary samples). `footprint` is the pixel size in metres at the sample:
// the 40-80 m billows fade out where they would alias (shimmering edges under TAA).
float cloudDensity(vec3 worldPos, CloudWeather w, int lod, float footprint) {
    float alt = worldPos.y - 62.0;
    // Wind shear: higher parts lean downwind by a fixed slope along the current wind (0.06 ..
    // 0.18 m per metre of height, stronger in storms).
    vec3 p = worldPos;
    p.xz -= state.cloudOffset.xy + windDirection() * ((alt - w.base) * (0.06 + 0.12 * windStrength()));

    float anvil = 0.0;
    #ifdef CUMULONIMBUS
    if (w.anvil > 0.01 && alt > ANVIL_BASE && alt < CLOUD_TOP_STORM) {
        // A flat sheet, thickest in the middle, thinning to fibrous edges.
        float a01 = (alt - ANVIL_BASE) / (CLOUD_TOP_STORM - ANVIL_BASE);
        float prof = smoothstep(0.0, 0.35, a01) * (1.0 - smoothstep(0.6, 1.0, a01));
        float n = texture(cloudShapeTex, p / SHAPE_TILE_2 * vec3(1.0, 2.5, 1.0)).g;
        anvil = remap(n * prof, 1.0 - w.anvil * 0.85, 1.0) * 0.6;
    }
    #endif

    float h01 = (alt - w.base) / (w.top - w.base);
    if (h01 <= 0.0 || h01 >= 1.0 || w.coverage <= 0.01) return anvil;
    float covH = w.coverage * coverageProfile(h01, w.type);
    if (covH <= 0.005) return anvil;

    // Shape: cells (Perlin-Worley and inverted Worley) at two scales (small humilis, large
    // congestus) mixed by the column's size with the variance restored, then modulated by Worley
    // fbm from an incommensurate tile and equalised (moments measured on
    // textures/clouds/cloud_shape.bin).
    vec4 sL = texture(cloudShapeTex, p / SHAPE_TILE * SHAPE_STRETCH);
    float pw = mix(sL.r, sL.g, CELL_SHARE);
    float worley = 0.5;
    if (lod > 0) {
        vec4 sS = texture(cloudShapeTex, (p + vec3(517.0, 0.0, 1291.0)) / SHAPE_TILE_S * SHAPE_STRETCH);
        pw = (mix(mix(sS.r, sS.g, CELL_SHARE), pw, w.size) - 0.514) * inversesqrt(w.size * w.size + (1.0 - w.size) * (1.0 - w.size)) + 0.514;
        vec4 f = texture(cloudShapeTex, (p + vec3(1733.0, 911.0, -2437.0)) / SHAPE_TILE_2 * vec3(1.0, 0.8, 1.0));
        worley = f.g * 0.625 + f.b * 0.25 + f.a * 0.125;
    }
    float u = equalise(pw - (1.0 - worley) * 0.3, 0.362, 0.15);
    // Stratocumulus: cellular rolls; stratus: an almost uniform sheet with soft variation.
    float sc = saturate(1.0 - abs(w.type - 0.35) / 0.2);
    float st = 1.0 - smoothstep(0.1, 0.3, w.type);
    u = mix(u, equalise(worley, 0.5, 0.14), 0.5 * sc);
    u = mix(u, 0.7 + 0.3 * u, st);
    // Where the noise exceeds 1 - covH there is cloud; density rises over 0.2 of the noise range,
    // so the edges are soft but the silhouettes stay distinct.
    float d = saturate((u - (1.0 - covH)) * 5.0);
    if (d > 0.0 && lod >= 2) {
        // Erosion: Worley detail (85-250 m) and billows from the shape texture's high octaves
        // (40-80 m), billowy (cauliflower) low and wispy towards the top. It only removes density
        // where it is low, so the interiors keep their shape.
        vec4 dn = texture(cloudDetailTex, p / DETAIL_TILE + vec3(0.0, -frameTimeCounter * DETAIL_DRIFT, 0.0));
        float df = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
        vec4 fs = texture(cloudShapeTex, p / FINE_TILE + vec3(0.0, -frameTimeCounter * FINE_DRIFT, 0.0));
        float ff = mix(0.5, fs.b * 0.5 + fs.a * 0.5, 1.0 - smoothstep(8.0, 30.0, footprint));
        float ero = df * 0.6 + (1.0 - ff) * 0.4;
        ero = mix(ero, 1.0 - ero, saturate(h01 * 3.0 - 1.2) * (1.0 - st));
        d = remap(d, ero * mix(0.45, 0.25, st), 1.0);
    }
    // More liquid water higher in a cumulus (it grows above the base), so bases are softer.
    d *= w.density * mix(1.0, mix(0.6, 1.0, saturate(h01 * 2.0)), smoothstep(0.35, 0.62, w.type));
    return max(d, anvil);
}
float cloudDensity(vec3 worldPos, CloudWeather w, int lod) { return cloudDensity(worldPos, w, lod, 0.0); }

// Extinction coefficient per metre for a density value (density 1 ~ 25 m mean free path).
float cloudExtinction(float density) {
    return density * 0.04 * CLOUD_DENSITY;
}

// Dual-lobe Henyey-Greenstein mix (strong forward peak for the silver lining).
float cloudPhase(float c) { return mix(phaseHG(c, -0.2), phaseHG(c, 0.82), 0.62); }

// ---- consumers
const float CLOUD_SHADOW_EXTENT = 4096.0;   // metres covered by the cloud shadow map (256^2)
const int CLOUD_SHADOW_RES = 256;

#ifndef CLOUD_PRODUCER
uniform sampler2D cloudHistSamplerA;   // reconstructed clouds (rgb in-scatter, a transmittance),
uniform sampler2D cloudHistSamplerB;   // ping-pong by frame parity; the newest is (frameCounter & 1)
uniform sampler2D cloudShadowSampler;  // optical depth through the layer above each point

vec4 sampleClouds(vec2 uv) {
    return (frameCounter & 1) == 0 ? texture(cloudHistSamplerA, uv) : texture(cloudHistSamplerB, uv);
}

float cloudShadowAt(vec3 worldPos, vec3 lightDir) {
    if (lightDir.y <= 0.02) return 1.0;
    float mid = 62.0 + CLOUD_BASE + 500.0;
    vec2 xz = worldPos.xz + lightDir.xz / lightDir.y * max(mid - worldPos.y, 0.0);
    // The map is centred on a texel-snapped point (state.misc.zw) so it never crawls.
    vec2 uv = (xz - state.misc.zw) / CLOUD_SHADOW_EXTENT + 0.5;
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return 1.0;
    float od = texture(cloudShadowSampler, uv).r;
    // Light scattered forward through thin cloud keeps some of it: soften with a floor.
    return mix(exp(-od / max(lightDir.y, 0.15)), 1.0, 0.08);
}
#endif

#endif

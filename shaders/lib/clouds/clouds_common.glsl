#ifndef MERIDIAN_CLOUDS_COMMON
#define MERIDIAN_CLOUDS_COMMON

#include "/lib/common/math.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

// Volumetric cloud model shared by the cloud march (deferred compute), the cloud shadow map
// (prepare compute) and the consumers (lighting, fog).
//
// Geometry: a spherical shell around a planet of PLANET_RADIUS from cloudShellBase() (the lowest
// stratus) to cloudTop() (towering cumulus; 9 km cumulonimbus in thunderstorms). Each column has
// its own cloud type, base and top, so cloud heights vary across the sky. Cirrus is a separate
// thin layer at 8.5 km (program/deferred/clouds.csh).
//
// Weather map (world xz in metres, cloudWeatherAt), three fields from the tileable noise texture:
//   systems     ~40 km weather systems: high pressure (open sky, scattered fair-weather cumulus)
//               to low pressure (broad stratocumulus banks, stratus); WEATHER_CLOUDS
//   cluster     domain-warped 0.5-3.6 km field that groups clouds: in a sparse sky only its peaks
//               form isolated groups, in a fuller sky they merge into clusters and banks with gaps
//   convective  instability: towering cumulus, higher bases, and (in thunder) cumulonimbus cells
// The old map was one noise at two scales remapped by a global coverage, so the same blob size
// and spacing filled the whole sky.
//
// Tiling: the wind offsets wrap every CLOUD_WRAP metres (program/begin/frame_setup.csh). Every
// noise sampled at (x - offset) therefore repeats a whole number of times per wrap, or clouds
// would jump at the wrap. The tile counts per wrap (1, 3, 5, 11, 23, 32, 256) are coprime, so the
// small-scale pattern never repeats visibly, while each texture alone repeats every few km.
// Formations drift with state.weatherOffset (80 % of the cloud speed), the cloud elements with
// state.cloudOffset: clouds slowly form at one side of a cluster and dissolve at the other
// instead of the whole pattern sliding rigidly.
//
// Density = two-scale shape noise (Perlin-Worley remapped by a Worley fbm from a second,
// incommensurate tile), shaped per type, remapped by the column's coverage and eroded at the
// edges by detail Worley noise.

uniform sampler3D cloudShapeTex;
uniform sampler3D cloudDetailTex;
uniform sampler2D noise2dTex;

const float CLOUD_WRAP = 131072.0;
const float CLOUD_BASE = float(CLOUD_ALTITUDE);                 // cumulus base, m above sea level
const float STRATUS_BASE = max(CLOUD_BASE * 0.55, 450.0);
const float CLOUD_SHELL_BASE = min(STRATUS_BASE, CLOUD_BASE - 250.0);
const float CLOUD_TOP_LOW = CLOUD_BASE + 2600.0;                // tallest cumulus congestus
const float CLOUD_TOP_STORM = 9000.0;
const float CIRRUS_ALTITUDE = 8500.0;
const float SHAPE_TILE = CLOUD_WRAP / 32.0;     // 4096 m
const float SHAPE_TILE_2 = CLOUD_WRAP / 23.0;   // 5699 m: breaks up the repetition of the first
const float DETAIL_TILE = CLOUD_WRAP / 256.0;   // 512 m

float cloudShellBase() { return CLOUD_SHELL_BASE; }
float cloudTop() {
    #ifdef CUMULONIMBUS
    return mix(CLOUD_TOP_LOW, CLOUD_TOP_STORM, thunderStrength);
    #else
    return CLOUD_TOP_LOW;
    #endif
}

struct CloudWeather {
    float coverage;  // 0..1 how much of this column is cloud
    float type;      // 0.08 stratus, 0.35 stratocumulus, 0.6 cumulus, 1 cumulonimbus
    float base;      // m above sea level
    float top;
};

vec4 weatherNoise(vec2 x, float tilesPerWrap) { return texture(noise2dTex, x * (tilesPerWrap / CLOUD_WRAP)); }

// Large-scale weather systems, 0 (high pressure) .. 1 (low pressure). The noise channels are
// roughly normal; a smoothstep over +-2 sigma maps them to ~uniform (distributions measured
// from textures/noise2d.png), a second one pushes more of the area towards settled extremes:
// whole skies that are nearly clear or mostly overcast, not one partly cloudy sky everywhere.
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
    #else
    float systems = 0.5;
    #endif
    // Domain warp from the large fields bends the cluster field into irregular groups.
    vec2 warp = (vec2(a.g, b.g) - 0.5) * 2600.0;
    vec4 c = weatherNoise(p + warp, 11.0);
    vec4 d = weatherNoise(p + warp * 0.5 + 3313.0, 5.0);
    float cluster = smoothstep(0.328, 0.748, d.g * 0.55 + c.g * 0.30 + c.a * 0.15);
    float convective = smoothstep(0.226, 0.854, d.b);

    // Regional coverage: CLOUD_COVERAGE on average, from almost none under high pressure to
    // banks under low pressure; rain and thunder fill the sky. The swing shrinks near 0 and 1 so
    // clipping does not shift the average (tools/tests/test_cloud_weather.py).
    const float SWING = min(1.125, 2.25 * min(CLOUD_COVERAGE, 1.0 - CLOUD_COVERAGE));
    float target = CLOUD_COVERAGE + (systems - 0.5) * SWING + rainStrength * 0.5 + thunderStrength * 0.2;
    target = saturate(target);
    // Thresholding the cluster field: about `target` of the area is inside a cloud group. Within
    // a group the 3D noise still carves individual clouds: a sparse sky's groups are loose fields
    // of cumulus (0.4), a full sky's groups dense banks (0.85). With the 3D shape this puts the
    // median vertical optical depth of a cloudy column near 3.5 at the default coverage (old
    // model 2.2, but with 90th percentile 6.3 instead of 8.2: fewer heavy grey masses).
    float cov = smoothstep(1.0 - target - 0.18, 1.0 - target + 0.18, cluster);
    cov *= mix(0.4, 0.85, target);
    // Overcast in rain: a coverage floor so rain and storms are grey from horizon to horizon,
    // with only slight variation (nimbostratus is a continuous sheet).
    cov = max(cov, rainStrength * (0.78 + 0.22 * smoothstep(0.2, 0.7, c.b)));

    // Type: fair weather cumulus, stratocumulus under low pressure, towers where unstable,
    // stratus in deep lows and steady rain, cumulonimbus cells in thunder.
    float t = mix(0.34, 0.62, 1.0 - smoothstep(0.35, 0.8, systems));
    t = clamp(t + (convective - 0.5) * 0.35, 0.2, 0.8);
    // Stratus: deep lows with a full sky and stable air (no convection to break the layer up).
    t = mix(t, 0.1, smoothstep(0.85, 1.0, systems) * smoothstep(0.6, 0.9, target) * smoothstep(0.55, 0.8, 1.0 - convective));
    t = mix(t, 0.08, rainStrength * (1.0 - thunderStrength) * 0.8);
    #ifdef CUMULONIMBUS
    t = mix(t, 1.0, thunderStrength * smoothstep(0.55, 0.8, convective));
    #endif

    CloudWeather w;
    w.coverage = cov;
    w.type = t;
    // Bases: higher where the air is unstable (higher condensation level), stratus low.
    float stratus = 1.0 - smoothstep(0.1, 0.3, t);
    w.base = mix(CLOUD_BASE + (convective - 0.5) * 400.0, STRATUS_BASE, stratus);
    // Thickness: stratus ~450 m, stratocumulus ~800 m, cumulus 0.9-2.4 km, cumulonimbus to 9 km.
    float thick = mix(450.0, 800.0, smoothstep(0.08, 0.35, t));
    thick = mix(thick, 900.0 + 1500.0 * convective, smoothstep(0.35, 0.62, t));
    thick = mix(thick, CLOUD_TOP_STORM - w.base, smoothstep(0.82, 1.0, t));
    w.top = min(w.base + thick, cloudTop());
    return w;
}

// Density profile over the normalised height of the column (0 base .. 1 top).
float heightProfile(float h01, float type) {
    // Flat bases for convective clouds, softer for layers.
    float bottom = smoothstep(0.0, mix(0.22, 0.07, type), h01);
    float top = 1.0 - smoothstep(mix(0.45, 0.62, type), 1.0, h01);
    // Cumulus thin out towards the top (rounded domes), stratus are nearly uniform.
    float round = mix(1.0, 1.0 - h01 * 0.4, saturate(type * 1.6));
    return bottom * top * round;
}

// Detail erosion drift, rounded to whole detail tiles per hour so the frameTimeCounter wrap at
// 3600 s is invisible (it used to jump 14.4 tiles every hour).
const float DETAIL_DRIFT = round(0.004 * CLOUD_SPEED * 3600.0) / 3600.0;

// lod 0: one shape fetch (far light samples only: an approximation); 1: two-scale shape (the
// empty-space probe and the shadow map, so both match the visible clouds); 2: plus edge erosion
// (primary samples).
float cloudDensity(vec3 worldPos, CloudWeather w, int lod) {
    float alt = worldPos.y - 62.0;
    float h01 = (alt - w.base) / (w.top - w.base);
    if (h01 <= 0.0 || h01 >= 1.0 || w.coverage <= 0.01) return 0.0;
    float profile = heightProfile(h01, w.type);
    if (profile <= 0.0) return 0.0;

    // Wind shear: higher parts lean downwind by a fixed slope along the current wind (0.06 ..
    // 0.18 m per metre of height, stronger in storms). Tying the lean to the accumulated drift made
    // it grow without bound, shearing clouds into streaks.
    vec3 p = worldPos;
    p.xz -= state.cloudOffset.xy + windDirection() * ((alt - w.base) * (0.06 + 0.12 * windStrength()));
    vec4 s = texture(cloudShapeTex, p / SHAPE_TILE * vec3(1.0, 1.6, 1.0));
    vec4 f = lod > 0 ? texture(cloudShapeTex, (p + vec3(1733.0, 911.0, -2437.0)) / SHAPE_TILE_2 * vec3(1.0, 1.3, 1.0)) : s;
    float worley = f.g * 0.625 + f.b * 0.25 + f.a * 0.125;
    // Billowy Perlin-Worley, its low frequencies modulated by the other tile's Worley fbm.
    float shape = remapUnclamped(s.r, worley - 1.0, 1.0, 0.0, 1.0);
    // Stratocumulus: cellular rolls with gaps; stratus: an almost uniform sheet.
    float sc = saturate(1.0 - abs(w.type - 0.35) / 0.2);
    shape = mix(shape, worley, 0.4 * sc);
    shape = mix(shape, 0.55 + 0.45 * worley, 1.0 - smoothstep(0.08, 0.28, w.type));
    float d = remap(shape * profile, 1.0 - w.coverage, 1.0) * w.coverage;
    if (d <= 0.0 || lod < 2) return d;

    // Erode edges: billowy (inverted Worley) at the bottom, wispy at the top. Soft exteriors keep
    // the internal detail: erosion only removes density where it is already low.
    vec3 q = p / DETAIL_TILE + vec3(0.0, -frameTimeCounter * DETAIL_DRIFT, 0.0);
    vec4 dn = texture(cloudDetailTex, q);
    float df = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
    df = mix(df, 1.0 - df, saturate(h01 * 4.0));
    d = remap(d, df * mix(0.32, 0.2, 1.0 - smoothstep(0.08, 0.28, w.type)), 1.0);
    return d;
}

// Extinction coefficient per metre for a density value (density 1 ~ 30 m mean free path in
// cumulus; stratus is thinner).
float cloudExtinction(float density, float type) {
    return density * mix(0.028, 0.045, type) * (1.0 + 0.6 * rainStrength) * CLOUD_DENSITY;
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

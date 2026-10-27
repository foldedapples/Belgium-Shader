#ifndef MERIDIAN_CLOUDS_COMMON
#define MERIDIAN_CLOUDS_COMMON

#include "/lib/common/math.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

// Volumetric cloud model shared by the cloud march (deferred compute), the cloud shadow map
// (prepare compute) and the consumers (lighting, fog).
//
// Geometry: a spherical shell around a planet of PLANET_RADIUS. The low/middle layer spans
// CLOUD_ALTITUDE .. CLOUD_ALTITUDE + 2200 m by default; storm towers reach 9 km. Cirrus is a
// separate thin layer at 8.5 km.
//
// Weather map (world xz, metres, moving with the integrated wind in state.cloudOffset; noise is
// sampled at x - offset so features travel along +windDirection(), like rain and plants):
//   coverage  where clouds exist; rises with CLOUD_COVERAGE, rain and thunder
//   type      0 stratus, 0.35 stratocumulus, 0.6 cumulus, 1 cumulonimbus (rain favours stratus,
//             thunder favours cumulonimbus)
// Density = shape noise (Perlin-Worley) remapped by coverage, shaped by a per-type height profile,
// eroded at the edges by detail Worley noise.

uniform sampler3D cloudShapeTex;
uniform sampler3D cloudDetailTex;
uniform sampler2D noise2dTex;

const float CLOUD_BASE = float(CLOUD_ALTITUDE);
const float CLOUD_TOP_LOW = CLOUD_BASE + 2200.0;
const float CLOUD_TOP_STORM = 9000.0;
const float CIRRUS_ALTITUDE = 8500.0;
const float SHAPE_TILE = 4096.0;        // metres per shape-noise tile (divides 131072)
const float DETAIL_TILE = 512.0;
const float WEATHER_TILE = 32768.0;

float cloudTop() { return mix(CLOUD_TOP_LOW, CLOUD_TOP_STORM, thunderStrength); }

struct CloudWeather {
    float coverage;
    float type;
};

CloudWeather cloudWeatherAt(vec2 xz) {
    vec2 p = (xz - state.cloudOffset.xy) / WEATHER_TILE;
    vec4 n = texture(noise2dTex, p);
    vec4 n2 = texture(noise2dTex, p * 4.0 + 0.37);
    CloudWeather w;
    float base = n.r * 0.65 + n2.r * 0.35;
    float cov = CLOUD_COVERAGE + rainStrength * 0.45 + thunderStrength * 0.2;
    w.coverage = saturate(remap(base, 1.0 - cov - 0.25, 1.0 - cov + 0.35));
    // Overcast in rain: a coverage floor so rain and storms are grey from horizon to horizon,
    // with only slight variation (nimbostratus is a continuous sheet).
    w.coverage = max(w.coverage, rainStrength * (0.78 + 0.22 * smoothstep(0.2, 0.7, n2.b)));
    float t = saturate(n.g * 1.1 - 0.05);
    t = mix(t, 0.12, rainStrength * (1.0 - thunderStrength) * 0.7);
    t = mix(t, max(t, 0.9), thunderStrength * smoothstep(0.35, 0.75, n2.g));
    w.type = t;
    return w;
}

// Normalised height (0 base .. 1 top of this column's cloud type) and its density profile.
float heightProfile(float h01, float type) {
    // Each type occupies a fraction of the shell and has its own vertical shape.
    float topFrac = mix(0.3, 1.0, smoothstep(0.0, 1.0, type));        // stratus ~650 m, Cb full depth
    float x = h01 / topFrac;
    if (x >= 1.0) return 0.0;
    float bottom = smoothstep(0.0, mix(0.25, 0.08, type), x);
    float top = 1.0 - smoothstep(mix(0.5, 0.65, type), 1.0, x);
    // Cumulus are rounder towards the top, stratus nearly flat.
    float round = mix(1.0, 1.0 - x * 0.35, saturate(type * 1.6));
    return bottom * top * round;
}

float cloudDensity(vec3 worldPos, CloudWeather w, bool detail) {
    float alt = worldPos.y - 62.0;
    float top = mix(CLOUD_TOP_LOW, CLOUD_TOP_STORM, w.type * thunderStrength);
    float h01 = (alt - CLOUD_BASE) / (top - CLOUD_BASE);
    if (h01 <= 0.0 || h01 >= 1.0 || w.coverage <= 0.01) return 0.0;
    float profile = heightProfile(h01, w.type);
    if (profile <= 0.0) return 0.0;

    // Wind shear: higher parts lean downwind. The lean is a fixed slope along the current wind
    // (0.06 .. 0.18 m per metre of height, stronger in storms; 0.3 .. 0.8 slanted a 2 km cloud by
    // up to 1.8 km, which read as long stretched streaks from below). It used to be 0.35 * h01 times the
    // wind displacement accumulated since loading, which grows without bound: after ~10 km of
    // drift a 220 m step in height sampled the noise 350 m away, so clouds leaned further every
    // minute until they sheared into flat streaks, and they jumped when the offset wrapped.
    vec3 p = worldPos;
    p.xz -= state.cloudOffset.xy + windDirection() * ((alt - CLOUD_BASE) * (0.06 + 0.12 * windStrength()));
    vec4 s = texture(cloudShapeTex, p / SHAPE_TILE * vec3(1.0, 1.6, 1.0));
    float fbm = s.g * 0.625 + s.b * 0.25 + s.a * 0.125;
    float shape = remapUnclamped(s.r, fbm - 1.0, 1.0, 0.0, 1.0);
    float d = remap(shape * profile, 1.0 - w.coverage, 1.0) * w.coverage;
    if (d <= 0.0 || !detail) return d;

    // Erode edges: billowy (inverted Worley) at the bottom, wispy at the top.
    vec3 q = p / DETAIL_TILE + vec3(0.0, -frameTimeCounter * 0.004 * CLOUD_SPEED, 0.0);
    vec4 dn = texture(cloudDetailTex, q);
    float df = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
    df = mix(df, 1.0 - df, saturate(h01 * 4.0));
    d = remap(d, df * 0.32, 1.0);
    return d;
}

// Extinction coefficient per metre for a density value (density 1 ~ 30 m mean free path in
// cumulus; stratus is thinner).
float cloudExtinction(float density, float type) {
    return density * mix(0.028, 0.045, type) * (1.0 + 0.6 * rainStrength);
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

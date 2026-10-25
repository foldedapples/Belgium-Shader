#ifndef ATMOSPHERE_ATMOSPHERE_GLSL
#define ATMOSPHERE_ATMOSPHERE_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/phase_functions.glsl"

// Physically based Earth-like atmosphere (ORIGINAL_ARCHITECTURE.md sec. 6). Distances in km.
// Coefficients are standard measured values for clear air (Rayleigh at 680/550/440 nm, a
// continental aerosol Mie layer, and the Chappuis-band ozone absorption).

const float ATM_GROUND = 6360.0;
const float ATM_TOP    = 6460.0;
const vec3  RAYLEIGH_SCATTERING = vec3(5.802e-3, 13.558e-3, 33.1e-3);
const float RAYLEIGH_HEIGHT = 8.0;
const float MIE_SCATTERING = 3.996e-3;
const float MIE_EXTINCTION = 4.440e-3;
const float MIE_HEIGHT = 1.2;
const float MIE_G = 0.8;
const vec3  OZONE_ABSORPTION = vec3(0.650e-3, 1.881e-3, 0.085e-3);
const float OZONE_CENTER = 25.0;
const float OZONE_HALF_WIDTH = 15.0;
const vec3  GROUND_ALBEDO = vec3(0.12, 0.13, 0.1);

// Top-of-atmosphere solar irradiance in scene units. Chosen so the sun disk radiance stays
// inside RGBA16F range at the smallest BE_SUN_SIZE; every other light is defined relative to it.
const float SUN_IRRADIANCE = 4.0;
// Full-moon irradiance relative to the sun. Reality is ~2.5e-6; we compress the dynamic
// range to 1/1500 so moonlit nights stay readable (documented artistic choice).
const float MOON_IRRADIANCE_RATIO = 1.0 / 1500.0;

struct AtmosphereSample {
    vec3  rayleigh;   // scattering
    float mie;        // scattering
    vec3  extinction;
};

AtmosphereSample sampleAtmosphere(float altitude) {
    altitude = max(altitude, 0.0);
    float dr = exp(-altitude / RAYLEIGH_HEIGHT);
    float dm = exp(-altitude / MIE_HEIGHT);
    float doz = max(0.0, 1.0 - abs(altitude - OZONE_CENTER) / OZONE_HALF_WIDTH);
    AtmosphereSample s;
    s.rayleigh = RAYLEIGH_SCATTERING * dr;
    s.mie = MIE_SCATTERING * dm;
    s.extinction = s.rayleigh + MIE_EXTINCTION * dm + OZONE_ABSORPTION * doz;
    return s;
}

// Camera altitude above the virtual planet, in km. Minecraft sea level (63) is altitude 0.
float cameraAltitudeKm(float worldY) {
    return clamp((worldY - 62.0) * 1e-3, 0.0, ATM_TOP - ATM_GROUND - 0.5) + 0.0005;
}

// Distance along (r, mu) to the top of the atmosphere / ground (Bruneton notation).
float distanceToTop(float r, float mu) {
    float disc = r * r * (mu * mu - 1.0) + ATM_TOP * ATM_TOP;
    return max(-r * mu + sqrt(max(disc, 0.0)), 0.0);
}
float distanceToGround(float r, float mu) {
    float disc = r * r * (mu * mu - 1.0) + ATM_GROUND * ATM_GROUND;
    return max(-r * mu - sqrt(max(disc, 0.0)), 0.0);
}
bool rayHitsGround(float r, float mu) {
    return mu < 0.0 && r * r * (mu * mu - 1.0) + ATM_GROUND * ATM_GROUND >= 0.0;
}

// ---- Transmittance LUT parameterisation (Bruneton 2017 style, our implementation) ----
const vec2 TRANSMITTANCE_LUT_SIZE = vec2(256.0, 64.0);

vec2 transmittanceLutUv(float r, float mu) {
    float H = sqrt(ATM_TOP * ATM_TOP - ATM_GROUND * ATM_GROUND);
    float rho = sqrt(max(r * r - ATM_GROUND * ATM_GROUND, 0.0));
    float d = distanceToTop(r, mu);
    float dMin = ATM_TOP - r;
    float dMax = rho + H;
    float xMu = (d - dMin) / max(dMax - dMin, EPSILON);
    float xR = rho / H;
    // Keep samples on texel centres at the edges.
    vec2 uv = vec2(xMu, xR);
    return (uv * (TRANSMITTANCE_LUT_SIZE - 1.0) + 0.5) / TRANSMITTANCE_LUT_SIZE;
}

void transmittanceLutParams(vec2 uv, out float r, out float mu) {
    vec2 x = (uv * TRANSMITTANCE_LUT_SIZE - 0.5) / (TRANSMITTANCE_LUT_SIZE - 1.0);
    x = saturate(x);
    float H = sqrt(ATM_TOP * ATM_TOP - ATM_GROUND * ATM_GROUND);
    float rho = H * x.y;
    r = sqrt(rho * rho + ATM_GROUND * ATM_GROUND);
    float dMin = ATM_TOP - r;
    float dMax = rho + H;
    float d = dMin + x.x * (dMax - dMin);
    mu = d == 0.0 ? 1.0 : (H * H - rho * rho - d * d) / (2.0 * r * d);
    mu = clamp(mu, -1.0, 1.0);
}

// Numerical optical depth from (r, mu) to the top of the atmosphere.
vec3 opticalDepthToTop(float r, float mu, int steps) {
    float len = distanceToTop(r, mu);
    float dt = len / float(steps);
    vec3 od = vec3(0.0);
    for (int i = 0; i < steps; i++) {
        float t = (float(i) + 0.5) * dt;
        float ri = sqrt(r * r + t * t + 2.0 * r * mu * t);
        od += sampleAtmosphere(ri - ATM_GROUND).extinction * dt;
    }
    return od;
}

// Analytic-free fallback transmittance for stages without the LUT (Nether/End begin).
vec3 transmittanceNumeric(float r, float mu) {
    if (rayHitsGround(r, mu)) return vec3(0.0);
    return exp(-opticalDepthToTop(r, mu, 24));
}

#ifdef ATMOSPHERE_LUTS
uniform sampler2D transmittanceLutTex;
uniform sampler2D multiScatterLutTex;

vec3 transmittanceToTop(float r, float mu) {
    if (rayHitsGround(r, mu)) return vec3(0.0);
    return texture(transmittanceLutTex, transmittanceLutUv(r, mu)).rgb;
}

// Transmittance to the sun including the soft planet-shadow terminator across the solar disk.
vec3 sunTransmittance(float r, float muS, float sunRadius) {
    float horizonMu = -sqrt(max(1.0 - sq(ATM_GROUND / r), 0.0));
    float visible = smoothstep(-sunRadius, sunRadius, asin(clamp(muS, -1.0, 1.0)) - asin(clamp(horizonMu, -1.0, 1.0)));
    return texture(transmittanceLutTex, transmittanceLutUv(r, max(muS, horizonMu + 1e-4))).rgb * visible;
}

const vec2 MULTISCATTER_LUT_SIZE = vec2(32.0, 32.0);
vec3 multiScatter(float r, float muS) {
    vec2 uv = vec2(muS * 0.5 + 0.5, (r - ATM_GROUND) / (ATM_TOP - ATM_GROUND));
    uv = (uv * (MULTISCATTER_LUT_SIZE - 1.0) + 0.5) / MULTISCATTER_LUT_SIZE;
    return texture(multiScatterLutTex, uv).rgb;
}
#endif

#endif

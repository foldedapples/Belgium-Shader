#ifndef MERIDIAN_ATMOSPHERE
#define MERIDIAN_ATMOSPHERE

// Physically based single + multiple scattering atmosphere, after Hillaire 2020 ("A Scalable and
// Production Ready Sky and Atmosphere Rendering Technique") and Bruneton & Neyret 2008, with Earth
// parameters from those papers. Units: metres; 1 block = 1 m. LUTs are rebuilt every frame in
// prepare (they are small), so haze can follow the weather.
//
// LUTs (custom images, see shaders.properties):
//   transmittanceLut  256 x 64  RGBA16F  transmittance to the top of the atmosphere
//   multiScatterLut    32 x 32  RGBA16F  isotropic multiple-scattering transfer (Hillaire 2020 sec. 5.5)
//   skyViewLut        256 x 128 RGBA16F  sky radiance around the camera for sun + moon light

const float PLANET_RADIUS = 6360e3;
const float ATMOSPHERE_RADIUS = 6460e3;
const vec3  RAYLEIGH_SCATTER = vec3(5.802e-6, 13.558e-6, 33.1e-6);
const float RAYLEIGH_HEIGHT = 8000.0;
const float MIE_SCATTER_BASE = 3.996e-6;
const float MIE_ABSORB_BASE = 0.444e-6;
const float MIE_HEIGHT = 1200.0;
const vec3  OZONE_ABSORB = vec3(0.650e-6, 1.881e-6, 0.085e-6);
const float OZONE_CENTER = 25000.0;
const float OZONE_HALF_WIDTH = 15000.0;
const vec3  GROUND_ALBEDO = vec3(0.30, 0.30, 0.28);

const ivec2 TRANSMITTANCE_SIZE = ivec2(256, 64);
const ivec2 MULTISCATTER_SIZE = ivec2(32, 32);
const ivec2 SKYVIEW_SIZE = ivec2(256, 128);

// Weather-dependent aerosol amount. Rain and thunder fill the low atmosphere with haze.
float aerosolFactor() {
    return HAZE_DENSITY * (1.0 + 2.5 * rainStrength + 1.5 * thunderStrength);
}

struct Medium {
    vec3 rayleigh;   // scattering
    float mie;       // scattering
    vec3 extinction;
};

Medium mediumAt(float altitude, float aerosol) {
    Medium m;
    float h = max(altitude, 0.0);
    float dr = exp(-h / RAYLEIGH_HEIGHT);
    float dm = exp(-h / MIE_HEIGHT) * aerosol;
    float dozone = max(0.0, 1.0 - abs(h - OZONE_CENTER) / OZONE_HALF_WIDTH);
    m.rayleigh = RAYLEIGH_SCATTER * dr;
    m.mie = MIE_SCATTER_BASE * dm;
    m.extinction = m.rayleigh + vec3((MIE_SCATTER_BASE + MIE_ABSORB_BASE) * dm) + OZONE_ABSORB * dozone;
    return m;
}

// Henyey-Greenstein phase function.
float phaseHG(float c, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * c, 1.5));
}

float phaseRayleigh(float c) { return 3.0 / (16.0 * PI) * (1.0 + c * c); }

// Cornette-Shanks phase function (better behaved than plain Henyey-Greenstein near g = 0.8).
float phaseMie(float c, float g) {
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * c;
    return 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + c * c)) / ((2.0 + g2) * denom * sqrt(denom));
}

// ---- transmittance LUT parameterisation (Bruneton 2017 mapping) ----
vec2 transmittanceUv(float r, float mu) {
    float H = sqrt(ATMOSPHERE_RADIUS * ATMOSPHERE_RADIUS - PLANET_RADIUS * PLANET_RADIUS);
    float rho = sqrt(max(r * r - PLANET_RADIUS * PLANET_RADIUS, 0.0));
    float disc = r * r * (mu * mu - 1.0) + ATMOSPHERE_RADIUS * ATMOSPHERE_RADIUS;
    float d = max(-r * mu + sqrt(max(disc, 0.0)), 0.0);
    float dMin = ATMOSPHERE_RADIUS - r;
    float dMax = rho + H;
    return vec2((d - dMin) / (dMax - dMin), rho / H);
}

void transmittanceRMu(vec2 uv, out float r, out float mu) {
    float H = sqrt(ATMOSPHERE_RADIUS * ATMOSPHERE_RADIUS - PLANET_RADIUS * PLANET_RADIUS);
    float rho = H * uv.y;
    r = sqrt(rho * rho + PLANET_RADIUS * PLANET_RADIUS);
    float dMin = ATMOSPHERE_RADIUS - r;
    float dMax = rho + H;
    float d = dMin + uv.x * (dMax - dMin);
    mu = d == 0.0 ? 1.0 : (H * H - rho * rho - d * d) / (2.0 * r * d);
    mu = clamp(mu, -1.0, 1.0);
}

// Distance from radius r along direction cosine mu to the top of the atmosphere / the ground.
float distanceToTop(float r, float mu) {
    float disc = r * r * (mu * mu - 1.0) + ATMOSPHERE_RADIUS * ATMOSPHERE_RADIUS;
    return max(-r * mu + sqrt(max(disc, 0.0)), 0.0);
}

bool rayHitsGround(float r, float mu) {
    return mu < 0.0 && r * r * (mu * mu - 1.0) + PLANET_RADIUS * PLANET_RADIUS >= 0.0;
}

// Camera radius from world height (sea level at y = 63).
float cameraRadius(float worldY) {
    return PLANET_RADIUS + clamp(worldY - 62.0, 1.0, 60000.0);
}

#ifdef ATMOSPHERE_SAMPLERS
uniform sampler2D transmittanceLutSampler;
uniform sampler2D multiScatterLutSampler;
uniform sampler2D skyViewLutSampler;

vec3 transmittanceToTop(float r, float mu) {
    if (rayHitsGround(r, mu)) return vec3(0.0);
    vec2 uv = transmittanceUv(r, mu);
    uv = (uv * vec2(TRANSMITTANCE_SIZE - 1) + 0.5) / vec2(TRANSMITTANCE_SIZE);
    return texture(transmittanceLutSampler, uv).rgb;
}

vec3 multiScatter(float r, float muSun) {
    vec2 uv = vec2(muSun * 0.5 + 0.5, saturate((r - PLANET_RADIUS) / (ATMOSPHERE_RADIUS - PLANET_RADIUS)));
    uv = (uv * vec2(MULTISCATTER_SIZE - 1) + 0.5) / vec2(MULTISCATTER_SIZE);
    return texture(multiScatterLutSampler, uv).rgb;
}

// Sky-view LUT: azimuth (world) along x, elevation along y with samples concentrated at the
// horizon (Hillaire 2020 sec. 5.3).
vec2 skyViewUv(vec3 dir) {
    float el = asin(clamp(dir.y, -1.0, 1.0));
    float v = 0.5 + 0.5 * sign(el) * sqrt(abs(el) / HALF_PI);
    float u = atan(dir.z, dir.x) / TAU + 0.5;
    return vec2(u, v);
}

vec3 skyViewDir(vec2 uv) {
    float s = uv.y * 2.0 - 1.0;
    float el = sign(s) * s * s * HALF_PI;
    float az = (uv.x - 0.5) * TAU;
    return vec3(cos(el) * cos(az), sin(el), cos(el) * sin(az));
}

vec3 sampleSkyView(vec3 dir) {
    vec2 uv = skyViewUv(dir);
    uv.y = (uv.y * float(SKYVIEW_SIZE.y - 1) + 0.5) / float(SKYVIEW_SIZE.y);
    // Azimuth wraps: the image clamps, so blend across the seam manually.
    float x = uv.x * float(SKYVIEW_SIZE.x) - 0.5;
    float x0 = floor(x);
    float f = x - x0;
    float xa = mod(x0, float(SKYVIEW_SIZE.x)), xb = mod(x0 + 1.0, float(SKYVIEW_SIZE.x));
    vec3 a = texture(skyViewLutSampler, vec2((xa + 0.5) / float(SKYVIEW_SIZE.x), uv.y)).rgb;
    vec3 b = texture(skyViewLutSampler, vec2((xb + 0.5) / float(SKYVIEW_SIZE.x), uv.y)).rgb;
    return mix(a, b, f);
}
#endif

#endif

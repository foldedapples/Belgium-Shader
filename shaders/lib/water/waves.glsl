#ifndef WATER_WAVES_GLSL
#define WATER_WAVES_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"

// Layer A: analytic wind waves (ORIGINAL_ARCHITECTURE.md sec. 8.1).
//
// N trochoidal components. Wavelengths are a geometric series from 1.7x the spectral peak
// down to ~0.3 blocks; the peak follows the Pierson-Moskowitz relation omega_p = 0.877 g / U,
// so higher wind gives longer, taller waves. Each component obeys deep-water dispersion
// omega = sqrt(g k). Directions spread around the wind with a golden-angle sequence (never a
// repeating pattern), wider for short waves. Steepness is shaped per band so the summed
// Gerstner steepness stays below 1 (no looping crests).
//
// waveSurface() returns the height, slope and Hessian, all analytic. Components whose
// wavelength is shorter than ~2 pixel footprints are faded out (no shimmer at distance).

const float GRAVITY = 9.81;

struct WaveSample {
    float height;
    vec2  slope;    // dh/dx, dh/dz
    vec3  hessian;  // d2h/dx2, d2h/dz2, d2h/dxdz
};

float windSpeed() {
    // Storms raise the wind; WATER_WIND_SPEED is the fair-weather value in m/s.
    return WATER_WIND_SPEED * (1.0 + 0.6 * fsWeather.z + 1.1 * fsWeather.y);
}

vec2 windDirection() {
    float a = radians(WATER_WIND_ANGLE);
    return vec2(cos(a), sin(a));
}

// `openness` 0..1: 1 open ocean, ~0.3 rivers and small lakes. `footprint`: world size of a
// pixel at the sample (0 for no filtering).
WaveSample waveSurface(vec2 xz, float t, float openness, float footprint) {
    WaveSample w;
    w.height = 0.0; w.slope = vec2(0.0); w.hessian = vec3(0.0);

    float U = windSpeed();
    float omegaP = 0.877 * GRAVITY / max(U, 0.5);
    float kPeak = omegaP * omegaP / GRAVITY;
    float lambdaPeak = min(TAU / kPeak, 48.0);
    // Sheltered water has short fetch: its longest waves stay small.
    float lambdaMax = mix(min(lambdaPeak * 1.7, 9.0), min(lambdaPeak * 1.7, 80.0), openness);
    const float lambdaMin = 0.3;
    vec2 wind = windDirection();
    float windAngle = atan(wind.y, wind.x);

    const int N = WATER_WAVE_COUNT;
    float ratio = pow(lambdaMin / lambdaMax, 1.0 / float(N - 1));

    // Pass 1: spectral shape (log-normal around the peak plus a capillary floor).
    float shapeSum = 0.0;
    float lambda = lambdaMax;
    for (int i = 0; i < N; i++) {
        shapeSum += exp(-0.6 * sq(log(lambda / lambdaPeak))) + 0.25;
        lambda *= ratio;
    }
    // Total Gerstner steepness stays well below 1 so crests never fold.
    float totalSteepness = 0.7 * WATER_WAVE_HEIGHT * mix(0.45, 1.0, openness);
    float scale = min(totalSteepness, 0.95) / shapeSum;

    // Pass 2: synthesis.
    lambda = lambdaMax;
    for (int i = 0; i < N; i++) {
        float k = TAU / lambda;
        float fi = float(i) / float(N - 1);
        // Angular spread widens for short waves; golden-angle offsets avoid regular patterns.
        float spread = mix(0.35, 1.25, fi);
        float offset = (fract(float(i) * 0.61803398875 + 0.17) * 2.0 - 1.0) * spread;
        float ang = windAngle + offset;
        vec2 dir = vec2(cos(ang), sin(ang));
        float s = (exp(-0.6 * sq(log(lambda / lambdaPeak))) + 0.25) * scale;
        float amp = s / k;
        // Anti-aliasing: fade components narrower than ~2.5 pixels.
        float aa = footprint > 0.0 ? 1.0 - smoothstep(0.4, 1.0, footprint * 2.5 / lambda) : 1.0;
        amp *= aa;
        if (amp > 0.0) {
            float omega = sqrt(GRAVITY * k) * WATER_WAVE_SPEED;
            float phase = fract(float(i) * 0.7548776662) * TAU;
            float theta = k * dot(dir, xz) - omega * t + phase;
            float sn = sin(theta), cs = cos(theta);
            // Sharpen crests toward a trochoid profile without folding.
            float crest = 1.0 + 0.6 * s * (1.0 + sn);
            w.height += amp * sn * crest;
            w.slope += dir * (amp * k * cs * crest);
            w.hessian += vec3(dir.x * dir.x, dir.y * dir.y, dir.x * dir.y) * (-amp * k * k * sn);
        }
        lambda *= ratio;
    }
    return w;
}

// How exposed a water surface is to wind fetch: oceans are open, rivers and enclosed ponds
// (low sky light) are calm. Biome factors are smoothed custom uniforms (shaders.properties).
float waterOpenness(float skyLight) {
    float biome = mix(0.35, 1.0, biomeOceanSmooth) * (1.0 - 0.5 * biomeRiverSmooth);
    return biome * smoothstep(0.55, 1.0, skyLight);
}

vec3 waveNormal(vec2 slope) { return normalize(vec3(-slope.x, 1.0, -slope.y)); }

// Wave clock in seconds; frameTimeCounter wraps hourly, which is acceptable for waves whose
// periods are a few seconds (a one-off phase jump once per hour of play).
float waveTime() { return frameTimeCounter; }

#endif

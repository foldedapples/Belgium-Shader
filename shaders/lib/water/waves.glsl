#ifndef MERIDIAN_WAVES
#define MERIDIAN_WAVES

// Surface waves as a sum of directional trains drawn from a wind-sea spectrum, plus advected
// gradient-noise chop. Each train obeys deep-water dispersion (omega^2 = g k). Amplitudes come
// from a steepness budget so the summed slope never exceeds a limit (no spikes or folds).
//
// Water bodies differ through WaterParams: open ocean gets long swells, lakes get only short
// wind ripples, flowing water gets chop advected down-slope, storms raise everything.

struct WaterParams {
    float swell;     // 0..1 long-wave energy (ocean, open water)
    float chop;      // 0..1 short wind waves
    float calm;      // 0..1 sheltered water suppresses everything but ripples
    vec2  flow;      // world-space flow velocity in blocks/second (flowing water)
    vec2  wind;      // unit wind direction
    float storm;     // 0..1 thunder
};

const float GRAVITY = 9.81;
const int WAVE_TRAINS = 12;

// Deterministic per-train parameters: direction spread around the wind, wavelength ladder.
void waveTrain(int i, WaterParams p, out vec2 dir, out float k, out float amp, out float phase0) {
    float fi = float(i);
    float u = fract(fi * 0.618034 + 0.13);
    // Spread grows for shorter waves (they respond to gusts, long swells are coherent).
    float lambdaMax = mix(9.0, 46.0, p.swell);
    float lambdaMin = 0.55;
    float lambda = lambdaMax * pow(lambdaMin / lambdaMax, fi / float(WAVE_TRAINS - 1));
    float spread = mix(0.35, 1.25, fi / float(WAVE_TRAINS - 1));
    float ang = (u * 2.0 - 1.0) * spread + (fract(fi * 0.371) - 0.5) * 0.25;
    dir = rotate2d(ang) * p.wind;
    k = TAU / lambda;
    // Steepness budget: long waves only exist with swell, short ones with chop.
    float longness = 1.0 - fi / float(WAVE_TRAINS - 1);
    float energy = mix(p.chop, p.swell, longness * longness);
    energy *= mix(1.0, 0.25, p.calm * longness);
    energy *= 1.0 + 0.9 * p.storm;
    float steep = 0.075 * energy;             // k * A per train
    amp = steep / k;
    phase0 = fi * 2.399963;                   // golden angle decorrelates trains
}

// Height (blocks, ~zero mean) and gradient d(h)/d(xz) at a world position.
vec3 waveHeightGrad(vec2 xz, float t, WaterParams p) {
    float h = 0.0;
    vec2 g = vec2(0.0);
    t *= WAVE_SPEED;
    vec2 pos = xz - p.flow * t;
    for (int i = 0; i < WAVE_TRAINS; i++) {
        vec2 d; float k, a, ph;
        waveTrain(i, p, d, k, a, ph);
        float w = sqrt(GRAVITY * k);
        float x = k * dot(d, pos) - w * t + ph;
        // Trochoid-like crest sharpening: sin plus a small second harmonic (keeps slopes bounded).
        float s = sin(x), c = cos(x);
        float sharp = 0.25 * min(k * a * 6.0, 1.0);
        h += a * (s + sharp * (0.5 - 0.5 * cos(2.0 * x)));
        float dh = a * k * (c + sharp * sin(2.0 * x));
        g += dh * d;
    }
    // Advected chop: two octaves of gradient noise drifting with the wind, for small detail that
    // never repeats.
    vec2 q = pos * 0.9 + p.wind * t * 0.6;
    vec3 n1 = gradientNoiseD(q);
    vec3 n2 = gradientNoiseD(q * 2.3 + vec2(17.0, -9.0) - p.wind * t * 0.4);
    float detail = (0.022 + 0.03 * p.chop + 0.03 * p.storm) * (1.0 - 0.5 * p.calm);
    h += detail * (n1.x + 0.45 * n2.x);
    g += detail * (n1.yz * 0.9 + 0.45 * n2.yz * 2.07);
    return vec3(h * WAVE_HEIGHT, g * WAVE_HEIGHT);
}

// Low-frequency part only, for vertex displacement (cheap, no aliasing at one vertex per block).
float waveSwellHeight(vec2 xz, float t, WaterParams p) {
    float h = 0.0;
    t *= WAVE_SPEED;
    vec2 pos = xz - p.flow * t;
    for (int i = 0; i < 4; i++) {
        vec2 d; float k, a, ph;
        waveTrain(i, p, d, k, a, ph);
        float w = sqrt(GRAVITY * k);
        h += a * sin(k * dot(d, pos) - w * t + ph);
    }
    return h * WAVE_HEIGHT;
}

float waveSwellAmplitude(WaterParams p) {
    float s = 0.0;
    for (int i = 0; i < 4; i++) {
        vec2 d; float k, a, ph;
        waveTrain(i, p, d, k, a, ph);
        s += a;
    }
    return s * WAVE_HEIGHT;
}

// Parameters for a water fragment from what a shader can know about it.
//   normal   geometric water-surface normal (tilted when the water flows)
//   skyLight 0..1 vanilla sky light at the surface (open water vs. caves and pools)
WaterParams waterParamsAt(vec3 normal, float skyLight) {
    WaterParams p;
    p.wind = windDirection();
    p.storm = thunderStrength;
    float open = smoothstep(0.55, 0.95, skyLight);
    p.swell = open * mix(0.12, 1.0, biomeOcean) * (1.0 - 0.6 * biomeRiver) * (1.0 - 0.6 * biomeSwamp);
    p.chop = mix(0.25, 0.75, open) * (0.6 + 0.4 * windStrength()) + 0.3 * rainStrength;
    p.calm = (1.0 - open) * 0.8 + biomeSwamp * 0.5;
    p.flow = vec2(0.0);
    float slope = length(normal.xz);
    if (slope > 0.02) {
        p.flow = normalize(normal.xz) * min(slope * 9.0, 2.5);
        p.chop = max(p.chop, 0.55);
        p.swell *= 0.2;
    } else if (biomeRiver > 0.01) {
        p.flow = p.wind * 0.35 * biomeRiver;
    }
    return p;
}

#endif

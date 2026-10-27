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

// Angular frequency of a train (deep-water dispersion, times WAVE_SPEED), rounded to a whole
// number of cycles per hour. frameTimeCounter wraps to 0 every 3600 s; with arbitrary
// frequencies every train jumped to an unrelated phase at that moment and the whole sea popped.
// Rounding moves omega by at most pi/3600 = 8.7e-4 rad/s.
float waveOmega(float k) {
    const float CYCLE = TAU / 3600.0;
    return max(round(sqrt(GRAVITY * k) * WAVE_SPEED / CYCLE), 1.0) * CYCLE;
}

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

// Prefilter of a wave component of wavenumber k (rad/block) over the pixel footprint `f`
// (blocks): a sinusoid averaged over a Gaussian with the second moment of a box pixel of width f
// (sigma = f / sqrt(12)) keeps exp(-k^2 f^2 / 24) of its amplitude. Without it the short trains
// (0.55-block wavelength) were evaluated far below the pixel size at range, so distant water
// normals aliased and the sun glitter sparkled. (A wider sigma = f/2 over-blurred near water;
// tools/tests/test_wave_filter.py compares both against the supersampled pixel average.)
float waveFilter(float k, float footprint) { return exp(-sq(k * footprint) * (1.0 / 24.0)); }

// Height (blocks, ~zero mean) and gradient d(h)/d(xz) at a world position, prefiltered over a
// pixel footprint (0 = unfiltered). `lostSlopeVar` returns the slope variance the filter removed;
// it belongs in the surface roughness (GGX alpha^2 ~ 2 x slope variance), so filtered water keeps
// the right amount of glitter as a broad highlight instead of losing it or aliasing.
vec3 waveHeightGradFiltered(vec2 xz, float t, WaterParams p, float footprint, out float lostSlopeVar) {
    float h = 0.0;
    vec2 g = vec2(0.0);
    lostSlopeVar = 0.0;
    float t0 = t;
    t *= WAVE_SPEED;
    vec2 pos = xz - p.flow * t;
    for (int i = 0; i < WAVE_TRAINS; i++) {
        vec2 d; float k, a, ph;
        waveTrain(i, p, d, k, a, ph);
        float wf = waveFilter(k, footprint);
        lostSlopeVar += 0.5 * sq(a * k) * (1.0 - wf * wf);
        if (wf < 0.01) continue;
        float x = k * dot(d, pos) - waveOmega(k) * t0 + ph;
        // Trochoid-like crest sharpening: sin plus a small second harmonic (keeps slopes bounded).
        float s = sin(x), c = cos(x);
        float sharp = 0.25 * min(k * a * 6.0, 1.0);
        h += wf * a * (s + sharp * (0.5 - 0.5 * cos(2.0 * x)));
        float dh = a * k * (c + sharp * sin(2.0 * x));
        g += wf * dh * d;
    }
    // Advected chop: two octaves of gradient noise drifting with the wind, for small detail that
    // never repeats (base frequencies ~0.9 and ~2.1 cycles per block).
    vec2 q = pos * 0.9 + p.wind * t * 0.6;
    float detail = (0.022 + 0.03 * p.chop + 0.03 * p.storm) * (1.0 - 0.5 * p.calm);
    float w1 = waveFilter(TAU * 0.9, footprint), w2 = waveFilter(TAU * 2.07, footprint);
    lostSlopeVar += 0.5 * sq(detail * 0.9) * (1.0 - w1 * w1) + 0.5 * sq(detail * 0.93) * (1.0 - w2 * w2);
    if (w1 > 0.01) {
        vec3 n1 = gradientNoiseD(q);
        h += w1 * detail * n1.x;
        g += w1 * detail * n1.yz * 0.9;
    }
    if (w2 > 0.01) {
        vec3 n2 = gradientNoiseD(q * 2.3 + vec2(17.0, -9.0) - p.wind * t * 0.4);
        h += w2 * detail * 0.45 * n2.x;
        g += w2 * detail * 0.45 * n2.yz * 2.07;
    }
    lostSlopeVar *= WAVE_HEIGHT * WAVE_HEIGHT;
    return vec3(h * WAVE_HEIGHT, g * WAVE_HEIGHT);
}

vec3 waveHeightGrad(vec2 xz, float t, WaterParams p) {
    float unused;
    return waveHeightGradFiltered(xz, t, p, 0.0, unused);
}

// Extra GGX alpha for the slope variance a footprint filter removed, and its 8-bit encoding in
// the water's colortex5 alpha (sqrt for precision near 0; glass uses that channel for opacity).
float waveLostAlpha(float lostSlopeVar) { return saturate(sqrt(2.0 * lostSlopeVar)); }
float encodeWaterRoughness(float a) { return sqrt(saturate(a)); }
float decodeWaterRoughness(float e) { return e * e; }

// Low-frequency part only, for vertex displacement (cheap, no aliasing at one vertex per block).
float waveSwellHeight(vec2 xz, float t, WaterParams p) {
    float h = 0.0;
    float t0 = t;
    t *= WAVE_SPEED;
    vec2 pos = xz - p.flow * t;
    for (int i = 0; i < 4; i++) {
        vec2 d; float k, a, ph;
        waveTrain(i, p, d, k, a, ph);
        h += a * sin(k * dot(d, pos) - waveOmega(k) * t0 + ph);
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

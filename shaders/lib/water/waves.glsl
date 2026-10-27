#ifndef MERIDIAN_WAVES
#define MERIDIAN_WAVES

// Surface waves: a fixed set of directional trains (a discretised wind-sea spectrum) plus advected
// gradient-noise chop. Each train obeys deep-water dispersion (omega^2 = g k).
//
// Wave speed must depend only on the wave, never on where the camera is. The phase of a train is
// k . x - omega t, so the wave vector k must be constant in time: if it changes, the phase at
// position x drifts by x . dk/dt, which is huge at large x. The previous model rotated every train
// with the slowly turning wind and stretched the long ones with the (smoothed) biome of the
// player, and advected by flow * t with a flow that also followed the player's biome. Waves
// therefore ran faster further from 0,0, and sped up whenever the player walked into a river or
// ocean biome (tools/tests/test_wave_speed.py). Now:
//   * wave vectors are fixed: a wavelength ladder with directions spread by the golden angle;
//     wind, weather and biome change only the amplitudes (a directional spreading function);
//   * the vectors lie on the lattice 2 pi / WORLD_WRAP and are evaluated in exact wrapped world
//     coordinates (world_coord.glsl), so the phase is exact at any distance from 0,0;
//   * advection (flowing water, drifting chop) uses two copies offset by at most one short period
//     and cross-faded (the usual flow-map scheme), so offsets stay bounded and changing the flow
//     changes only the direction of travel, never the position of the pattern.
//
// All entry points take the camera-relative (player-space) xz.

#include "/lib/common/world_coord.glsl"

struct WaterParams {
    float swell;     // 0..1 long-wave energy (ocean, open water)
    float chop;      // 0..1 short wind waves
    float calm;      // 0..1 sheltered water suppresses everything but ripples
    vec2  flow;      // world-space flow velocity in blocks/second (flowing water)
    vec2  wind;      // unit wind direction
    float storm;     // 0..1 thunder
};

const float GRAVITY = 9.81;
const int WAVE_TRAINS = 16;
const float WAVE_LATTICE = TAU / float(WORLD_WRAP);
const float FLOW_PERIOD = 6.0;      // seconds per advection cycle of the two-phase scheme

// Angular frequency of a train (deep-water dispersion, times WAVE_SPEED), rounded to a whole
// number of cycles per hour. frameTimeCounter wraps to 0 every 3600 s; with arbitrary
// frequencies every train jumped to an unrelated phase at that moment and the whole sea popped.
// Rounding moves omega by at most pi/3600 = 8.7e-4 rad/s.
float waveOmega(float k) {
    const float CYCLE = TAU / 3600.0;
    return max(round(sqrt(GRAVITY * k) * WAVE_SPEED / CYCLE), 1.0) * CYCLE;
}

// Fixed wave vector of train i: wavelengths from 46 down to 0.55 blocks, directions spread around
// the circle by the golden angle, snapped to the lattice (direction change < 2 % for the longest).
vec2 waveVector(int i) {
    float fi = float(i);
    float lambda = 46.0 * pow(0.55 / 46.0, fi / float(WAVE_TRAINS - 1));
    float ang = fi * 2.399963 + 0.5;
    vec2 kv = vec2(cos(ang), sin(ang)) * (TAU / lambda);
    return round(kv / WAVE_LATTICE) * WAVE_LATTICE;
}

// Amplitude of train i (blocks) from the steepness budget: long waves need swell, short ones
// chop; trains running with the wind carry most energy and those against it little (so turning
// wind re-weights trains smoothly instead of rotating them).
float waveAmplitude(int i, vec2 kv, WaterParams p) {
    float k = length(kv);
    float longness = 1.0 - float(i) / float(WAVE_TRAINS - 1);
    float energy = mix(p.chop, p.swell, longness * longness);
    energy *= mix(1.0, 0.25, p.calm * longness);
    energy *= 1.0 + 0.9 * p.storm;
    float along = dot(kv / k, p.wind);
    float spread = mix(0.1, 1.0, sq(saturate(0.5 + 0.5 * along)));
    return 0.1 * energy * spread / k;
}

// Two-phase advection: weights and offsets of the two copies for velocity v at time t.
void flowPhases(vec2 v, float t, out vec2 off0, out vec2 off1, out float w0) {
    float p0 = fract(t / FLOW_PERIOD);
    float p1 = fract(t / FLOW_PERIOD + 0.5);
    off0 = v * (p0 * FLOW_PERIOD);
    off1 = v * (p1 * FLOW_PERIOD) + vec2(13.7, -7.3);   // decorrelate the copies
    w0 = 1.0 - abs(2.0 * p0 - 1.0);                       // triangle: w0 + w1 = 1, each 0 at its reset
}

// Prefilter of a wave component of wavenumber k (rad/block) over the pixel footprint `f`
// (blocks): a sinusoid averaged over a Gaussian with the second moment of a box pixel of width f
// (sigma = f / sqrt(12)) keeps exp(-k^2 f^2 / 24) of its amplitude. Without it the short trains
// (0.55-block wavelength) were evaluated far below the pixel size at range, so distant water
// normals aliased and the sun glitter sparkled. (A wider sigma = f/2 over-blurred near water;
// tools/tests/test_wave_filter.py compares both against the supersampled pixel average.)
float waveFilter(float k, float footprint) { return exp(-sq(k * footprint) * (1.0 / 24.0)); }

// Sum of the trains at wrapped position x: (height, gradient).
vec3 waveTrainSum(vec2 x, float t, WaterParams p, float footprint) {
    float h = 0.0;
    vec2 g = vec2(0.0);
    for (int i = 0; i < WAVE_TRAINS; i++) {
        vec2 kv = waveVector(i);
        float k = length(kv);
        float wf = waveFilter(k, footprint);
        if (wf < 0.01) continue;
        float a = waveAmplitude(i, kv, p);
        float ph = dot(kv, x) - waveOmega(k) * t + float(i) * 2.399963;
        // Trochoid-like crest sharpening: sin plus a small second harmonic (keeps slopes bounded).
        float s = sin(ph), c = cos(ph);
        float sharp = 0.25 * min(k * a * 6.0, 1.0);
        h += wf * a * (s + sharp * (0.5 - 0.5 * cos(2.0 * ph)));
        g += wf * a * (c + sharp * sin(2.0 * ph)) * kv;
    }
    return vec3(h, g);
}

// Gradient noise whose cells repeat every `period` cells (so it repeats with the world wrap).
vec3 gradientNoiseDPeriodic(vec2 p, int period) {
    ivec2 i = ivec2(floor(p));
    vec2 f = fract(p);
    vec2 u  = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
    ivec2 i0 = ivec2(wrapInt(i.x, period), wrapInt(i.y, period));
    ivec2 i1 = ivec2(wrapInt(i.x + 1, period), wrapInt(i.y + 1, period));
    vec2 ga = hash2(i0) * 2.0 - 1.0;
    vec2 gb = hash2(ivec2(i1.x, i0.y)) * 2.0 - 1.0;
    vec2 gc = hash2(ivec2(i0.x, i1.y)) * 2.0 - 1.0;
    vec2 gd = hash2(i1) * 2.0 - 1.0;
    float va = dot(ga, f);
    float vb = dot(gb, f - vec2(1, 0));
    float vc = dot(gc, f - vec2(0, 1));
    float vd = dot(gd, f - vec2(1, 1));
    float v = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd);
    vec2 d = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
           + du * (u.yx * (va - vb - vc + vd) + vec2(vb, vc) - va);
    return vec3(v * 1.41421356, d * 1.41421356);
}

// Chop noise scales: whole numbers of cells per wrap period (~0.9 and ~2.07 cycles per block).
const int CHOP_CELLS_1 = 1382;
const int CHOP_CELLS_2 = 3179;

vec3 waveChop(vec2 x, float footprint, float w1, float w2) {
    vec3 r = vec3(0.0);
    const float S1 = float(CHOP_CELLS_1) / float(WORLD_WRAP);
    const float S2 = float(CHOP_CELLS_2) / float(WORLD_WRAP);
    if (w1 > 0.01) {
        vec3 n1 = gradientNoiseDPeriodic(x * S1, CHOP_CELLS_1);
        r += w1 * vec3(n1.x, n1.yz * S1);
    }
    if (w2 > 0.01) {
        vec3 n2 = gradientNoiseDPeriodic(x * S2 + vec2(17.0, -9.0), CHOP_CELLS_2);
        r += w2 * 0.45 * vec3(n2.x, n2.yz * S2);
    }
    return r;
}

// Height (blocks, ~zero mean) and gradient d(h)/d(xz) at a camera-relative position, prefiltered
// over a pixel footprint (0 = unfiltered). `lostSlopeVar` returns the slope variance the filter
// removed; it belongs in the surface roughness (GGX alpha^2 ~ 2 x slope variance), so filtered
// water keeps its glitter as a broad highlight instead of losing it or aliasing.
vec3 waveHeightGradFiltered(vec2 playerXZ, float t, WaterParams p, float footprint, out float lostSlopeVar) {
    vec2 x = wrappedWorldXZ(playerXZ);
    lostSlopeVar = 0.0;
    for (int i = 0; i < WAVE_TRAINS; i++) {
        vec2 kv = waveVector(i);
        float k = length(kv);
        float wf = waveFilter(k, footprint);
        lostSlopeVar += 0.5 * sq(waveAmplitude(i, kv, p) * k) * (1.0 - wf * wf);
    }

    vec2 o0, o1;
    float w0;
    vec3 hg;
    if (dot(p.flow, p.flow) > 1e-6) {
        flowPhases(p.flow * WAVE_SPEED, t, o0, o1, w0);
        hg = waveTrainSum(x - o0, t, p, footprint) * w0 + waveTrainSum(x - o1, t, p, footprint) * (1.0 - w0);
    } else {
        hg = waveTrainSum(x, t, p, footprint);
    }

    // Chop drifts with the wind (and the flow); two phases keep its offset bounded.
    float detail = (0.022 + 0.03 * p.chop + 0.03 * p.storm) * (1.0 - 0.5 * p.calm);
    float w1 = waveFilter(TAU * 0.9, footprint), w2 = waveFilter(TAU * 2.07, footprint);
    lostSlopeVar += 0.5 * sq(detail * 0.9) * (1.0 - w1 * w1) + 0.5 * sq(detail * 0.93) * (1.0 - w2 * w2);
    flowPhases((p.flow + p.wind * 0.6) * WAVE_SPEED, t, o0, o1, w0);
    hg += detail * (waveChop(x - o0, footprint, w1, w2) * w0 + waveChop(x - o1, footprint, w1, w2) * (1.0 - w0));

    lostSlopeVar *= WAVE_HEIGHT * WAVE_HEIGHT;
    return hg * WAVE_HEIGHT;
}

vec3 waveHeightGrad(vec2 playerXZ, float t, WaterParams p) {
    float unused;
    return waveHeightGradFiltered(playerXZ, t, p, 0.0, unused);
}

// Extra GGX alpha for the slope variance a footprint filter removed, and its 8-bit encoding in
// the water's colortex5 alpha (sqrt for precision near 0; glass uses that channel for opacity).
float waveLostAlpha(float lostSlopeVar) { return saturate(sqrt(2.0 * lostSlopeVar)); }
float encodeWaterRoughness(float a) { return sqrt(saturate(a)); }
float decodeWaterRoughness(float e) { return e * e; }

// Longest trains only, for vertex displacement of still water (no aliasing at one vertex per block).
const int SWELL_TRAINS = 4;

float waveSwellHeight(vec2 playerXZ, float t, WaterParams p) {
    vec2 x = wrappedWorldXZ(playerXZ);
    float h = 0.0;
    for (int i = 0; i < SWELL_TRAINS; i++) {
        vec2 kv = waveVector(i);
        h += waveAmplitude(i, kv, p) * sin(dot(kv, x) - waveOmega(length(kv)) * t + float(i) * 2.399963);
    }
    return h * WAVE_HEIGHT;
}

float waveSwellAmplitude(WaterParams p) {
    float s = 0.0;
    for (int i = 0; i < SWELL_TRAINS; i++) s += waveAmplitude(i, waveVector(i), p);
    return s * WAVE_HEIGHT;
}

// Parameters for a water fragment from what a shader can know about it.
//   normal   geometric water-surface normal (tilted when the water flows)
//   skyLight 0..1 vanilla sky light at the surface (open water vs. caves and pools)
// Biome and weather only scale amplitudes; flow comes only from the surface's own slope (the
// player's biome used to add a river current to every water surface on screen).
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
    }
    return p;
}

#endif

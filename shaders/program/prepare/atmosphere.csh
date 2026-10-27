// prepare: atmosphere look-up tables. One source, four entry points selected by the wrapper:
//   ATMO_TRANSMITTANCE  prepare.csh    transmittance to the top of the atmosphere (256 x 64)
//   ATMO_MULTISCATTER   prepare_a.csh  multiple-scattering transfer (32 x 32), Hillaire 2020 sec. 5.5
//   ATMO_SKYVIEW        prepare_b.csh  sky radiance around the camera, sun + moon (256 x 128)
//   ATMO_SKY_SH         prepare_c.csh  order-2 spherical-harmonic projection of the sky for ambient light

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/state.glsl"
#define ATMOSPHERE_SAMPLERS
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/sky/celestial.glsl"

#ifdef ATMO_TRANSMITTANCE
layout(local_size_x = 16, local_size_y = 16) in;
const ivec3 workGroups = ivec3(16, 4, 1);
layout(rgba16f) uniform writeonly image2D transmittanceLut;

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(px, TRANSMITTANCE_SIZE))) return;
    vec2 uv = (vec2(px) + 0.5) / vec2(TRANSMITTANCE_SIZE);
    uv = (uv * vec2(TRANSMITTANCE_SIZE) - 0.5) / vec2(TRANSMITTANCE_SIZE - 1);
    float r, mu;
    transmittanceRMu(saturate(uv), r, mu);
    float len = distanceToTop(r, mu);
    float aer = aerosolFactor();
    vec3 depth = vec3(0.0);
    const int N = 40;
    float dt = len / float(N);
    for (int i = 0; i < N; i++) {
        float t = (float(i) + 0.5) * dt;
        float ri = sqrt(r * r + t * t + 2.0 * r * mu * t);
        depth += mediumAt(ri - PLANET_RADIUS, aer).extinction * dt;
    }
    imageStore(transmittanceLut, px, vec4(exp(-depth), 1.0));
}
#endif

#ifdef ATMO_MULTISCATTER
layout(local_size_x = 8, local_size_y = 8) in;
const ivec3 workGroups = ivec3(4, 4, 1);
layout(rgba16f) uniform writeonly image2D multiScatterLut;

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(px, MULTISCATTER_SIZE))) return;
    vec2 uv = vec2(px) / vec2(MULTISCATTER_SIZE - 1);
    float muSun = uv.x * 2.0 - 1.0;
    float r = PLANET_RADIUS + uv.y * (ATMOSPHERE_RADIUS - PLANET_RADIUS) + 1.0;
    vec3 sunDir = vec3(sqrt(max(1.0 - muSun * muSun, 0.0)), muSun, 0.0);
    vec3 pos = vec3(0.0, r, 0.0);
    float aer = aerosolFactor();

    vec3 lumTotal = vec3(0.0), fms = vec3(0.0);
    const int DIRS = 64;
    for (int d = 0; d < DIRS; d++) {
        // Uniform sphere directions (Fibonacci).
        float z = 1.0 - (float(d) + 0.5) * 2.0 / float(DIRS);
        float a = float(d) * GOLDEN_ANGLE;
        float s = sqrt(max(1.0 - z * z, 0.0));
        vec3 dir = vec3(s * cos(a), z, s * sin(a));
        float mu = dir.y;
        bool ground = rayHitsGround(r, mu);
        vec2 hitG = raySphere(pos, dir, PLANET_RADIUS);
        float len = ground ? hitG.x : distanceToTop(r, mu);
        const int N = 20;
        float dt = len / float(N);
        vec3 T = vec3(1.0), L = vec3(0.0), F = vec3(0.0);
        for (int i = 0; i < N; i++) {
            vec3 p = pos + dir * ((float(i) + 0.5) * dt);
            float ri = length(p);
            Medium m = mediumAt(ri - PLANET_RADIUS, aer);
            vec3 scat = m.rayleigh + vec3(m.mie);
            vec3 stepT = exp(-m.extinction * dt);
            vec3 Tsun = transmittanceToTop(ri, dot(p / ri, sunDir));
            // Isotropic phase for the multiple-scattering estimate (Hillaire 2020 eq. 6-8).
            vec3 S = scat * Tsun * INV_4PI;
            vec3 integ = (S - S * stepT) / max(m.extinction, vec3(1e-12));
            L += T * integ;
            vec3 fInteg = (scat - scat * stepT) / max(m.extinction, vec3(1e-12));
            F += T * fInteg;
            T *= stepT;
        }
        if (ground) {
            vec3 p = pos + dir * len;
            vec3 n = normalize(p);
            vec3 Tsun = transmittanceToTop(PLANET_RADIUS + 1.0, dot(n, sunDir));
            L += T * Tsun * saturate(dot(n, sunDir)) * GROUND_ALBEDO * INV_PI;
        }
        lumTotal += L * (4.0 * PI / float(DIRS)) * INV_4PI;
        fms += F * (4.0 * PI / float(DIRS)) * INV_4PI;
    }
    vec3 psi = lumTotal / max(1.0 - fms, vec3(1e-3));
    imageStore(multiScatterLut, px, vec4(psi, 1.0));
}
#endif

#if defined ATMO_SKYVIEW || defined ATMO_SKY_SH
// In-scattered radiance along `dir` from the camera, lit by the sun and the moon.
vec3 integrateSky(vec3 dir, SkyLights L) {
    float r = cameraRadius(cameraPosition.y);
    vec3 pos = vec3(0.0, r, 0.0);
    float mu = dir.y;
    bool ground = rayHitsGround(r, mu);
    vec2 hitG = raySphere(pos, dir, PLANET_RADIUS);
    float len = ground ? hitG.x : distanceToTop(r, mu);
    len = min(len, 400e3);
    float aer = aerosolFactor();
    float cs = dot(dir, L.sunDir), cm = dot(dir, L.moonDir);
    float prS = phaseRayleigh(cs), pmS = phaseMie(cs, 0.8);
    float prM = phaseRayleigh(cm), pmM = phaseMie(cm, 0.8);
    vec3 eSun = vec3(L.sunIllum), eMoon = L.moonIllum;
    const int N = 28;
    vec3 T = vec3(1.0), sum = vec3(0.0);
    float tPrev = 0.0;
    for (int i = 0; i < N; i++) {
        // Quadratic step distribution: dense near the camera where the air is thickest.
        float t = len * sq((float(i) + 1.0) / float(N));
        float dt = t - tPrev;
        vec3 p = pos + dir * (tPrev + 0.5 * dt);
        tPrev = t;
        float ri = length(p);
        vec3 up = p / ri;
        Medium m = mediumAt(ri - PLANET_RADIUS, aer);
        vec3 stepT = exp(-m.extinction * dt);
        vec3 Ts = transmittanceToTop(ri, dot(up, L.sunDir));
        vec3 Tm = transmittanceToTop(ri, dot(up, L.moonDir));
        vec3 msS = multiScatter(ri, dot(up, L.sunDir));
        vec3 msM = multiScatter(ri, dot(up, L.moonDir));
        vec3 scat = m.rayleigh + vec3(m.mie);
        vec3 S = eSun * (Ts * (m.rayleigh * prS + m.mie * pmS) + msS * scat)
               + eMoon * (Tm * (m.rayleigh * prM + m.mie * pmM) + msM * scat);
        sum += T * (S - S * stepT) / max(m.extinction, vec3(1e-12));
        T *= stepT;
    }
    if (ground) {
        vec3 p = pos + dir * len;
        vec3 n = normalize(p);
        vec3 Ts = transmittanceToTop(PLANET_RADIUS + 1.0, dot(n, L.sunDir));
        vec3 Tm = transmittanceToTop(PLANET_RADIUS + 1.0, dot(n, L.moonDir));
        sum += T * GROUND_ALBEDO * INV_PI * (eSun * Ts * saturate(dot(n, L.sunDir)) + eMoon * Tm * saturate(dot(n, L.moonDir)));
    }
    return sum;
}
#endif

#ifdef ATMO_SKYVIEW
layout(local_size_x = 16, local_size_y = 16) in;
const ivec3 workGroups = ivec3(16, 8, 1);
layout(rgba16f) uniform writeonly image2D skyViewLut;

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(px, SKYVIEW_SIZE))) return;
    vec2 uv = (vec2(px) + 0.5) / vec2(SKYVIEW_SIZE);
    // Elevation texel centres span the full range including the horizon row.
    uv.y = float(px.y) / float(SKYVIEW_SIZE.y - 1);
    vec3 dir = skyViewDir(uv);
    SkyLights L = skyLights();
    imageStore(skyViewLut, px, vec4(integrateSky(dir, L), 1.0));
}
#endif

#ifdef ATMO_SKY_SH
// Project the sky-view LUT onto order-2 SH (9 coefficients) with one workgroup and a shared-memory
// reduction. Result in state.skySH (already convolved with the clamped cosine for irradiance).
layout(local_size_x = 256) in;
const ivec3 workGroups = ivec3(1, 1, 1);

shared vec3 partial[256][9];

void main() {
    uint tid = gl_LocalInvocationIndex;
    SkyLights Ls = skyLights();
    vec3 acc[9];
    for (int i = 0; i < 9; i++) acc[i] = vec3(0.0);
    // 32 x 16 directions (equal-area in z), each thread handles 2.
    for (uint s = tid; s < 512u; s += 256u) {
        float fx = (float(s % 32u) + 0.5) / 32.0;
        float fz = (float(s / 32u) + 0.5) / 16.0;
        float y = 1.0 - 2.0 * fz;
        float rr = sqrt(max(1.0 - y * y, 0.0));
        float a = fx * TAU;
        vec3 d = vec3(rr * cos(a), y, rr * sin(a));
        vec3 L = sampleSkyView(d);
        // Below the horizon the "sky" is the lit ground seen through the air; keep it but damp it,
        // since in Minecraft the real ground is already lit separately.
        if (d.y < 0.0) L *= 0.5;
        // Night-sky light the LUT does not contain: airglow and integrated starlight. Without it a
        // moonless night has no ambient light at all and shadows are pure black.
        if (d.y > 0.0) {
            float k = SUN_ILLUMINANCE * MOON_PHYSICAL_RATIO * Ls.skyGain;
            float vr = min(inversesqrt(max(1.0 - 0.972 * (1.0 - d.y * d.y), 1e-3)), 3.0);
            L += vec3(0.85, 1.0, 0.8) * (3.5e-4 * vr + 2.0e-4) * k * (1.0 - rainStrength * 0.8);
        }
        // Under cloud cover the sky dome is grey cloud, not clear blue sky: the cloud layer's
        // brightness is roughly the diffuse sunlight it transmits. Blend by the weather's cover.
        float cover = saturate(rainStrength * 0.9 + CLOUD_COVERAGE * 0.3);
        float grey = luminance(L) * 0.55;
        L = mix(L, vec3(grey) * vec3(0.95, 0.98, 1.0), cover * 0.85);
        float sh[9] = float[9](0.282095, 0.488603 * d.y, 0.488603 * d.z, 0.488603 * d.x,
                               1.092548 * d.x * d.y, 1.092548 * d.y * d.z, 0.315392 * (3.0 * d.z * d.z - 1.0),
                               1.092548 * d.x * d.z, 0.546274 * (d.x * d.x - d.y * d.y));
        for (int i = 0; i < 9; i++) acc[i] += L * sh[i];
    }
    for (int i = 0; i < 9; i++) partial[tid][i] = acc[i];
    barrier();
    for (uint stride = 128u; stride > 0u; stride >>= 1u) {
        if (tid < stride) for (int i = 0; i < 9; i++) partial[tid][i] += partial[tid + stride][i];
        barrier();
    }
    if (tid == 0u) {
        float w = 4.0 * PI / 512.0;
        // Cosine-lobe convolution (Ramamoorthi & Hanrahan 2001): A0 = pi, A1 = 2pi/3, A2 = pi/4.
        const float A[9] = float[9](PI, 2.0943951, 2.0943951, 2.0943951, 0.7853982, 0.7853982, 0.7853982, 0.7853982, 0.7853982);
        for (int i = 0; i < 9; i++) state.skySH[i] = vec4(partial[0][i] * w * A[i] * INV_PI, 0.0);
    }
}
#endif

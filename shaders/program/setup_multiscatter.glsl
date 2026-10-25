// setup_a.csh - multiple-scattering LUT (32x32 over sun zenith cosine x altitude).
// Approximates all orders of scattering beyond the first as isotropic, following the energy
// argument of Hillaire 2020: second-order radiance L2 and the transfer factor f_ms give the
// geometric series L2 / (1 - f_ms). Written for unit sun irradiance.
#include "/lib/core/common.glsl"
#define ATMOSPHERE_LUTS
#include "/lib/atmosphere/atmosphere.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const ivec3 workGroups = ivec3(4, 4, 1);

layout(rgba16f) uniform writeonly image2D multiScatterLut;

const int DIR_SQRT = 8;     // 64 directions, stratified on the sphere
const int STEPS = 24;

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(px, ivec2(MULTISCATTER_LUT_SIZE)))) return;
    vec2 x = vec2(px) / (MULTISCATTER_LUT_SIZE - 1.0);
    float muS = x.x * 2.0 - 1.0;
    float r = ATM_GROUND + max(x.y, 0.001) * (ATM_TOP - ATM_GROUND - 0.01);
    vec3 pos = vec3(0.0, r, 0.0);
    vec3 sunDir = vec3(sqrt(max(1.0 - muS * muS, 0.0)), muS, 0.0);

    vec3 l2 = vec3(0.0);
    vec3 fms = vec3(0.0);
    const float isotropic = 1.0 / (4.0 * PI);

    for (int i = 0; i < DIR_SQRT; i++) for (int j = 0; j < DIR_SQRT; j++) {
        // Uniform sphere sampling from a stratified unit square.
        float u = (float(i) + 0.5) / float(DIR_SQRT);
        float v = (float(j) + 0.5) / float(DIR_SQRT);
        float cosT = 1.0 - 2.0 * u;
        float sinT = sqrt(max(1.0 - cosT * cosT, 0.0));
        float phi = TAU * v;
        vec3 rd = vec3(sinT * cos(phi), cosT, sinT * sin(phi));

        float mu = rd.y;
        bool ground = rayHitsGround(r, mu);
        float len = ground ? distanceToGround(r, mu) : distanceToTop(r, mu);
        float dt = len / float(STEPS);

        vec3 throughput = vec3(1.0);
        vec3 lDir = vec3(0.0), fDir = vec3(0.0);
        for (int s = 0; s < STEPS; s++) {
            float t = (float(s) + 0.5) * dt;
            vec3 p = pos + rd * t;
            float pr = length(p);
            AtmosphereSample a = sampleAtmosphere(pr - ATM_GROUND);
            vec3 scat = a.rayleigh + a.mie;
            vec3 stepT = exp(-a.extinction * dt);
            vec3 sunT = transmittanceToTop(pr, dot(p / pr, sunDir));
            // Integrate analytically over the step: (1 - exp(-sigma_t dt)) / sigma_t.
            vec3 integ = (1.0 - stepT) / max(a.extinction, vec3(1e-7));
            lDir += throughput * scat * sunT * isotropic * integ;
            fDir += throughput * scat * integ;
            throughput *= stepT;
        }
        if (ground) {
            vec3 gp = pos + rd * len;
            float gr = length(gp);
            vec3 gn = gp / gr;
            vec3 sunT = transmittanceToTop(gr, dot(gn, sunDir));
            lDir += throughput * sunT * saturate(dot(gn, sunDir)) * GROUND_ALBEDO * INV_PI;
        }
        l2 += lDir;
        fms += fDir;
    }
    float n = float(DIR_SQRT * DIR_SQRT);
    // Both integrals are taken against the isotropic phase function over the sphere, which for
    // uniform stratified directions is the plain mean.
    l2 /= n;
    fms = min(fms / n, vec3(0.99));
    vec3 psi = l2 / (1.0 - fms);
    imageStore(multiScatterLut, px, vec4(psi, 1.0));
}
#endif

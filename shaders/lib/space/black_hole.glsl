#ifndef MERIDIAN_BLACK_HOLE
#define MERIDIAN_BLACK_HOLE
#include "/lib/common/math.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/lighting/emitters.glsl"


// A Schwarzschild black hole with a thin accretion disk, ray traced per pixel.
//
// Geodesics: for a photon in the Schwarzschild metric the orbit equation is
// d^2u/dphi^2 + u = (3/2) r_s u^2 (u = 1/r). The same orbits follow from integrating the
// Cartesian "acceleration" a = -(3/2) r_s h^2 r / |r|^5 with h = |r x v| (conserved), which is
// what we step (velocity Verlet, step proportional to r). Units: r_s = 1.
//
// Disk: thin, Keplerian, inner edge at the ISCO (3 r_s), temperature
// T(r) ~ r^-3/4 (1 - sqrt(r_in / r))^1/4 (Shakura & Sunyaev 1973). Observed colour includes the
// Doppler factor of the orbiting gas and gravitational redshift sqrt(1 - r_s/r); intensity scales
// with g^4 (bolometric beaming). Turbulent structure is advected with the Keplerian angular
// velocity so inner rings visibly outrun outer ones.
//
// Physics simplifications (documented): the observer is static far away; the disk is optically
// thin-ish and emits isotropically in its rest frame; Kerr spin is not modelled.

const float BH_RS = 1.0;
const float BH_ISCO = 3.0;
const float BH_DISK_OUTER = 14.0;
const float BH_OBSERVER_DIST = 60.0;

// Angular radius of the shadow as seen by the observer: (3 sqrt 3 / 2) r_s / D.
float bhShadowAngle() { return 2.598076 * BH_RS / BH_OBSERVER_DIST; }

// Sky angular scale: the black hole's shadow appears this large (radians) on screen.
float bhApparentShadow() { return 0.065 * BH_SIZE; }

vec3 bhBlackbody(float t) {
    // Normalised Planckian locus approximation (shared with emitters.glsl).
    return blackbody(clamp(t, 1000.0, 40000.0));
}

struct BHResult {
    vec3 radiance;     // disk light along the ray (already includes everything in front of escape)
    float transmit;    // fraction of the background still visible
    vec3 escapeDir;    // direction of the ray after lensing (local BH frame -> caller converts)
    bool captured;
};

// Gas structure of the disk at radius r, azimuth phi: fractal noise on a cylinder (log r, cos a,
// sin a), so it is continuous all the way round (no seam) and streaks are stretched along the
// orbit. The material orbits at the Keplerian rate (slowed for display).
float diskGas(float r, float a) {
    vec3 p = vec3(log(r) * 7.0, cos(a) * 2.2, sin(a) * 2.2);
    float n = 0.0, amp = 0.5;
    for (int i = 0; i < 4; i++) {
        n += amp * valueNoise(p + float(i) * 11.7);
        p *= vec3(2.1, 1.7, 1.7);
        amp *= 0.5;
    }
    return n / 0.9375;
}

// Differential rotation winds any pattern into ever tighter rings: after time t, radii r1 and r2
// differ in angle by (omega(r1) - omega(r2)) t, which grows without bound. The old pattern
// advected by phi + omega t (plus a spiral sinusoid) therefore turned into the fine concentric
// bands seen in game, worse the longer the session. Here two copies are advected over a bounded
// window of DISK_PERIOD seconds, half a period apart, and cross-faded (the flow-map scheme), so the
// gas visibly orbits - inner parts faster - but the winding never exceeds one window's worth.
const float DISK_PERIOD = 8.0;
float diskTurbulence(float r, float phi, float t) {
    float omega = 0.5 * pow(r, -1.5) * 3.0;            // Keplerian ~ r^-3/2, display rate
    float p0 = fract(t / DISK_PERIOD), p1 = fract(t / DISK_PERIOD + 0.5);
    float w0 = 1.0 - abs(2.0 * p0 - 1.0);
    float n = diskGas(r, phi + omega * p0 * DISK_PERIOD) * w0
            + diskGas(r * 1.07, phi + omega * p1 * DISK_PERIOD + 2.1) * (1.0 - w0);
    return saturate((n - 0.25) * 1.6);
}

// Traces a ray in the BH frame: origin `ro` (|ro| = BH_OBSERVER_DIST), direction `rd`.
// The disk lies in the plane with normal `diskN`.
BHResult traceBlackHole(vec3 ro, vec3 rd, vec3 diskN, float time) {
    BHResult res;
    res.radiance = vec3(0.0);
    res.transmit = 1.0;
    res.captured = false;
    vec3 pos = ro;
    vec3 vel = rd;
    vec3 hv = cross(pos, vel);
    float h2 = dot(hv, hv);
    float prevSide = dot(pos, diskN);
    for (int i = 0; i < BH_LENSING_STEPS * 2; i++) {
        float r = length(pos);
        if (r < BH_RS * 1.0005) { res.captured = true; res.transmit = 0.0; break; }
        if (r > BH_OBSERVER_DIST * 1.5 && dot(pos, vel) > 0.0) break;
        float dt = clamp(r * 0.09, 0.02, 4.0);
        vec3 acc = -1.5 * BH_RS * h2 * pos / pow(r, 5.0);
        vel += acc * dt * 0.5;
        vec3 next = pos + vel * dt;
        float rn = length(next);
        vec3 accN = -1.5 * BH_RS * h2 * next / pow(rn, 5.0);
        vel += accN * dt * 0.5;
        vel = normalize(vel);
        float side = dot(next, diskN);
        if (side * prevSide < 0.0) {
            // Crossed the disk plane: interpolate the crossing point.
            float f = prevSide / (prevSide - side);
            vec3 hit = mix(pos, next, f);
            float rh = length(hit);
            if (rh > BH_ISCO && rh < BH_DISK_OUTER) {
                vec3 tangent = normalize(cross(diskN, hit));
                vec3 e1 = normalize(cross(diskN, abs(diskN.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
                vec3 e2 = cross(diskN, e1);
                float phi = atan(dot(hit, e2), dot(hit, e1));
                // Keplerian speed (c units) and the Doppler factor towards the observer (the photon
                // travels opposite to our backward-traced ray).
                float beta = sqrt(BH_RS / (2.0 * max(rh - BH_RS, 0.5)));
                beta = min(beta, 0.7);
                float gamma = inversesqrt(1.0 - beta * beta);
                float cosA = dot(tangent, -vel);
                float doppler = 1.0 / (gamma * (1.0 - beta * cosA));
                float grav = sqrt(max(1.0 - BH_RS / rh, 0.0));
                float g = doppler * grav;
                float x = BH_ISCO / rh;
                // Peak ~4600 K before Doppler / gravitational shifts: warm gold overall, white-hot
                // on the approaching side, deep orange on the receding side and at the outer edge.
                float temp = 4600.0 * pow(x, 0.75) * pow(max(1.0 - sqrt(x), 0.0), 0.25) / 0.4884;
                float turb = diskTurbulence(rh, phi, time);
                float density = smoothstep(BH_DISK_OUTER, BH_DISK_OUTER * 0.6, rh) * smoothstep(BH_ISCO, BH_ISCO * 1.15, rh);
                density *= mix(0.35, 1.0, turb);
                vec3 col = bhBlackbody(temp * g);
                // Normalised so the brightest part of the disk is ~1 before the caller's scaling.
                float emiss = pow(x, 2.0) * pow(g, 4.0) * 0.5;
                float alpha = saturate(density * 0.85);
                res.radiance += res.transmit * col * emiss * density * (0.6 + 0.8 * turb);
                res.transmit *= 1.0 - alpha;
                if (res.transmit < 0.01) break;
            }
        }
        prevSide = side;
        pos = next;
    }
    res.escapeDir = vel;
    return res;
}

#endif

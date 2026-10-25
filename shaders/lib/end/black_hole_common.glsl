#ifndef END_BLACK_HOLE_COMMON_GLSL
#define END_BLACK_HOLE_COMMON_GLSL
#include "/lib/core/common.glsl"

// Schwarzschild black hole in units of the Schwarzschild radius (r_s = 1).
// Null geodesics obey, with u = 1/r and phi the orbital angle,
//     d2u/dphi2 = 1.5 u^2 - u,      (du/dphi)^2 = 1/b^2 - u^2 (1 - u),
// where b is the impact parameter. The photon sphere is at r = 1.5 and rays with
// b < b_c = 3 sqrt(3) / 2 are captured. ISCO (inner edge of a thin disk) is r = 3.

const float BH_CRITICAL_B = 2.5980762;
const float BH_ISCO = 3.0;
const float BH_PHI_MAX = 4.0 * PI;      // longest orbit traced (two full turns)
const int   BH_LUT_B = 512;             // impact-parameter columns
const int   BH_LUT_PHI = 256;           // orbit-angle rows (row 0 holds metadata)

// Observer distance from the hole; BH_SIZE scales the apparent size.
float bhObserverDistance() { return 36.0 / BH_SIZE; }

// Column mapping concentrated logarithmically around the critical impact parameter, where
// the photon ring and higher-order images live.
float bhImpactFromX(float x) { return BH_CRITICAL_B * exp((x * 2.0 - 1.0) * 2.2); }
float bhXFromImpact(float b) { return (log(max(b, 1e-4) / BH_CRITICAL_B) / 2.2 + 1.0) * 0.5; }
float bhMinImpact() { return bhImpactFromX(0.0); }
float bhMaxImpact() { return bhImpactFromX(1.0); }

// RK4 step of the orbit equation for state (u, du/dphi).
vec2 bhDerivative(vec2 s) { return vec2(s.y, 1.5 * s.x * s.x - s.x); }
vec2 bhRk4(vec2 s, float h) {
    vec2 k1 = bhDerivative(s);
    vec2 k2 = bhDerivative(s + 0.5 * h * k1);
    vec2 k3 = bhDerivative(s + 0.5 * h * k2);
    vec2 k4 = bhDerivative(s + h * k3);
    return s + h / 6.0 * (k1 + 2.0 * k2 + 2.0 * k3 + k4);
}

// Initial state for a ray leaving the observer inward with impact parameter b.
vec2 bhInitialState(float b, float D) {
    float u0 = 1.0 / D;
    float du2 = 1.0 / (b * b) - u0 * u0 * (1.0 - u0);
    return vec2(u0, sqrt(max(du2, 0.0)));
}

#endif

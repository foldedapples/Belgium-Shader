#ifndef CORE_PHASE_FUNCTIONS_GLSL
#define CORE_PHASE_FUNCTIONS_GLSL
#include "/lib/core/math.glsl"

// Scattering phase functions (normalised over the sphere).

float rayleighPhase(float cosTheta) { return 3.0 / (16.0 * PI) * (1.0 + cosTheta * cosTheta); }

// Cornette-Shanks variant of Henyey-Greenstein, better suited to aerosols.
float miePhase(float cosTheta, float g) {
    float g2 = g * g;
    float num = 3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta);
    float den = 8.0 * PI * (2.0 + g2) * pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5);
    return num / den;
}

float henyeyGreenstein(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5));
}

#endif

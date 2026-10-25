#ifndef WATER_CAUSTICS_GLSL
#define WATER_CAUSTICS_GLSL
#include "/lib/core/common.glsl"
#include "/lib/water/waves.glsl"
#include "/lib/water/water_params.glsl"

// Caustics on surfaces lit through water (ORIGINAL_ARCHITECTURE.md sec. 8.3).
// A light ray refracted at a surface with slope s is deflected by about (1 - 1/n) s, so after
// a depth d it lands displaced by -(1 - 1/n) d grad(h). The map from surface point to floor
// point has Jacobian J = I - (1 - 1/n) d H(h), and energy conservation gives the floor
// irradiance factor 1/|det J|. H is the analytic Hessian of the wave field, so no caustic
// texture is needed and the pattern moves exactly with the visible waves.

float causticFactor(vec3 worldPos, vec3 lightDir, float waterDepth, float openness, float footprint) {
    if (waterDepth <= 0.02) return 1.0;
    float L = max(lightDir.y, 0.2);
    float vertical = waterDepth * L;
    // Point on the surface where this ray entered the water.
    vec2 entry = worldPos.xz + lightDir.xz / L * vertical;
    WaveSample w = waveSurface(entry, waveTime(), openness, footprint);
    float k = (1.0 - 1.0 / WATER_IOR) * min(vertical, 6.0);
    mat2 J = mat2(1.0 - k * w.hessian.x, -k * w.hessian.z,
                  -k * w.hessian.z, 1.0 - k * w.hessian.y);
    float det = abs(J[0][0] * J[1][1] - J[0][1] * J[1][0]);
    float intensity = 1.0 / max(det, 0.12);
    // Soft compression of the singular focal lines, then fade with depth (scattering blurs
    // the pattern) and with distance (footprint) handled inside waveSurface.
    intensity = intensity / (1.0 + 0.25 * max(intensity - 1.0, 0.0));
    float strength = WATER_CAUSTICS * exp(-vertical * 0.12);
    return mix(1.0, intensity, strength);
}

#endif

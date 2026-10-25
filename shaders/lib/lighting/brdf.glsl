#ifndef LIGHTING_BRDF_GLSL
#define LIGHTING_BRDF_GLSL
#include "/lib/core/math.glsl"

// Microfacet BRDF building blocks (alpha = GGX roughness = perceptual^2).

float ggxDistribution(float nDotH, float alpha) {
    float a2 = alpha * alpha;
    float d = nDotH * nDotH * (a2 - 1.0) + 1.0;
    return a2 / max(PI * d * d, 1e-8);
}

// Height-correlated Smith masking-shadowing folded with the 1/(4 nDotL nDotV) denominator
// (Heitz 2014): returns V = G2 / (4 nDotL nDotV).
float smithVisibilityCorrelated(float nDotV, float nDotL, float alpha) {
    float a2 = alpha * alpha;
    float gv = nDotL * sqrt(nDotV * nDotV * (1.0 - a2) + a2);
    float gl = nDotV * sqrt(nDotL * nDotL * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-6);
}

vec3 fresnelSchlick(vec3 f0, float cosTheta) {
    return f0 + (1.0 - f0) * pow5(1.0 - saturate(cosTheta));
}
float fresnelSchlick(float f0, float cosTheta) {
    return f0 + (1.0 - f0) * pow5(1.0 - saturate(cosTheta));
}

// Exact unpolarised Fresnel reflectance of a dielectric interface (eta = n2 / n1).
float fresnelDielectric(float cosI, float eta) {
    cosI = saturate(cosI);
    float sin2T = (1.0 - cosI * cosI) / (eta * eta);
    if (sin2T >= 1.0) return 1.0; // total internal reflection
    float cosT = sqrt(1.0 - sin2T);
    float rs = (cosI - eta * cosT) / (cosI + eta * cosT);
    float rp = (eta * cosI - cosT) / (eta * cosI + cosT);
    return 0.5 * (rs * rs + rp * rp);
}

// Exact unpolarised Fresnel reflectance of a conductor with complex IOR n + ik (per channel).
vec3 fresnelConductor(float cosI, vec3 n, vec3 k) {
    cosI = clamp(cosI, 1e-4, 1.0);
    float c2 = cosI * cosI;
    float s2 = 1.0 - c2;
    vec3 n2 = n * n, k2 = k * k;
    vec3 t0 = n2 - k2 - s2;
    vec3 a2b2 = sqrt(t0 * t0 + 4.0 * n2 * k2);
    vec3 a = sqrt(max(0.5 * (a2b2 + t0), vec3(0.0)));
    vec3 rsNum = a2b2 + c2 - 2.0 * a * cosI;
    vec3 rsDen = a2b2 + c2 + 2.0 * a * cosI;
    vec3 rs = rsNum / max(rsDen, vec3(1e-6));
    vec3 rpNum = c2 * a2b2 + s2 * s2 - 2.0 * a * cosI * s2;
    vec3 rpDen = c2 * a2b2 + s2 * s2 + 2.0 * a * cosI * s2;
    vec3 rp = rs * rpNum / max(rpDen, vec3(1e-6));
    return saturate(0.5 * (rs + rp));
}

#endif

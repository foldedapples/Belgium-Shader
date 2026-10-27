#ifndef MERIDIAN_BRDF
#define MERIDIAN_BRDF

// Microfacet BRDF: GGX / Trowbridge-Reitz distribution (Walter et al. 2007), height-correlated
// Smith visibility (Heitz 2014), Fresnel from the material (exact conductor for LabPBR metals,
// Schlick otherwise), multiple-scattering energy compensation (Turquin 2019 / Fdez-Aguera 2019)
// using a DFG table built by tools/gen_dfg.py, and an energy-conserving diffuse lobe.

uniform sampler2D dfgLut;   // RG16F 32x32: x = scale A, y = bias B of the split-sum DFG term

float D_GGX(float NoH, float a) {
    float a2 = a * a;
    float d = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 / (PI * d * d);
}

float V_SmithCorrelated(float NoV, float NoL, float a) {
    float a2 = a * a;
    float gv = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float gl = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-6);
}

// Split-sum environment term: specular albedo for unit-intensity white light = f0 * A + B.
vec2 dfgTerm(float NoV, float a) {
    vec2 uv = vec2(saturate(NoV), saturate(sqrt(a)));
    uv = (uv * 31.0 + 0.5) / 32.0;
    return texture(dfgLut, uv).rg;
}

vec3 specularAlbedo(vec3 f0, float NoV, float a) {
    vec2 ab = dfgTerm(NoV, a);
    return f0 * ab.x + ab.y;
}

// Energy compensation factor for multiple scattering between microfacets.
vec3 multiScatterCompensation(vec3 f0, float NoV, float a) {
    vec2 ab = dfgTerm(NoV, a);
    return 1.0 + f0 * (1.0 / max(ab.x + ab.y, 1e-3) - 1.0);
}

struct LightSample {
    vec3 diffuse;   // multiply by albedo outside
    vec3 specular;
};

// Response to a directional light of unit irradiance arriving from `l`.
LightSample evalDirectional(Material m, vec3 n, vec3 v, vec3 l) {
    LightSample s;
    float NoL = dot(n, l);
    float NoV = max(dot(n, v), 1e-4);
    if (NoL <= 0.0) { s.diffuse = vec3(0.0); s.specular = vec3(0.0); return s; }
    vec3 h = normalize(l + v);
    float NoH = saturate(dot(n, h));
    float VoH = saturate(dot(v, h));
    vec3 F = materialFresnel(m, VoH);
    float D = D_GGX(NoH, m.alpha);
    float V = V_SmithCorrelated(NoV, NoL, m.alpha);
    s.specular = F * (D * V * NoL) * multiScatterCompensation(m.f0, NoV, m.alpha);
    // Diffuse keeps the energy the specular lobe does not reflect (both directions).
    vec3 eo = specularAlbedo(m.f0, NoV, m.alpha);
    vec3 ei = specularAlbedo(m.f0, NoL, m.alpha);
    s.diffuse = m.metal ? vec3(0.0) : (1.0 - eo) * (1.0 - ei) * (1.05 * NoL * INV_PI);
    return s;
}

// Light transmitted through thin translucent material (leaves, grass, snow) from behind.
// `thickness` is the shadow-map distance to the first caster in blocks.
vec3 subsurfaceTransmission(Material m, vec3 n, vec3 v, vec3 l, float thickness) {
    if (m.sss <= 0.0) return vec3(0.0);
    float back = saturate(-dot(n, l));
    float forward = pow(saturate(dot(-v, l)), 4.0);
    float att = exp(-max(thickness, 0.0) * mix(6.0, 1.2, m.sss));
    vec3 tint = sqrt(max(m.albedo, 0.0));
    return tint * m.sss * att * (0.25 * back + 0.55 * forward + 0.08) * INV_PI;
}

#endif

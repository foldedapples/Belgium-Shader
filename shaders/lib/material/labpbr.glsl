#ifndef MERIDIAN_LABPBR
#define MERIDIAN_LABPBR

// LabPBR 1.3 decoding (https://shaderlabs.org/wiki/LabPBR_Material_Standard).
//
// The G-buffer stores the specular texture's four bytes unchanged (or the hardcoded fallback
// written in the same encoding), so every consumer decodes with the functions below.

struct Material {
    vec3  albedo;      // linear
    float alpha;       // GGX alpha = (1 - perceptual smoothness)^2
    vec3  f0;          // normal-incidence reflectance (dielectric: grey; metal: tinted)
    bool  metal;
    int   metalIndex;  // 0..7 for the predefined LabPBR metals, -1 albedo-tinted, -2 dielectric
    float porosity;    // 0..1
    float sss;         // 0..1 subsurface scattering amount
    float emission;    // 0..1
    float ao;          // material ambient occlusion (1 = unoccluded)
};

// Complex refractive indices (n, k) of the eight predefined metals, at R/G/B, as tabulated in
// the LabPBR specification.
const vec3 METAL_N[8] = vec3[8](
    vec3(2.9114, 2.9497, 2.5845),   // 230 iron
    vec3(0.18299, 0.42108, 1.3734), // 231 gold
    vec3(1.3456, 0.96521, 0.61722), // 232 aluminium
    vec3(3.1071, 3.1812, 2.3230),   // 233 chrome
    vec3(0.27105, 0.67693, 1.3164), // 234 copper
    vec3(1.9100, 1.8300, 1.4400),   // 235 lead
    vec3(2.3757, 2.0847, 1.8453),   // 236 platinum
    vec3(0.15943, 0.14512, 0.13547) // 237 silver
);
const vec3 METAL_K[8] = vec3[8](
    vec3(3.0893, 2.9318, 2.7670),
    vec3(3.4242, 2.3459, 1.7704),
    vec3(7.4746, 6.3995, 5.3031),
    vec3(3.3314, 3.3291, 3.1350),
    vec3(3.6092, 2.6248, 2.2921),
    vec3(3.5100, 3.4000, 3.1800),
    vec3(4.2655, 3.7153, 3.1365),
    vec3(3.9291, 3.1900, 2.3808)
);

// Exact unpolarised Fresnel reflectance of a conductor with index n + ik (per channel).
vec3 fresnelConductor(float cosTheta, vec3 n, vec3 k) {
    float c2 = cosTheta * cosTheta;
    float s2 = 1.0 - c2;
    vec3 n2 = n * n, k2 = k * k;
    vec3 t0 = n2 - k2 - s2;
    vec3 a2b2 = sqrt(t0 * t0 + 4.0 * n2 * k2);
    vec3 a = sqrt(max(0.5 * (a2b2 + t0), 0.0));
    vec3 t1 = a2b2 + c2;
    vec3 t2 = 2.0 * a * cosTheta;
    vec3 rs = (t1 - t2) / (t1 + t2);
    vec3 t3 = c2 * a2b2 + s2 * s2;
    vec3 t4 = t2 * s2;
    vec3 rp = rs * (t3 - t4) / (t3 + t4);
    return saturate(0.5 * (rp + rs));
}

// Reflectance at normal incidence from n, k (used for F0-based approximations and debug views).
vec3 conductorF0(vec3 n, vec3 k) {
    return ((n - 1.0) * (n - 1.0) + k * k) / ((n + 1.0) * (n + 1.0) + k * k);
}

// Decode raw specular bytes (each 0..255 as a float in [0,1]) and albedo into a Material.
Material decodeMaterial(vec3 albedoLinear, vec4 spec, float materialAO) {
    Material m;
    m.albedo = albedoLinear;
    m.ao = materialAO;

    float smoothness = spec.r;
    m.alpha = max(sq(1.0 - smoothness), 0.0016);

    int g = int(spec.g * 255.0 + 0.5);
    if (g >= 230) {
        m.metal = true;
        m.metalIndex = g <= 237 ? g - 230 : -1;
        m.f0 = m.metalIndex >= 0 ? conductorF0(METAL_N[m.metalIndex], METAL_K[m.metalIndex]) : albedoLinear;
    } else {
        m.metal = false;
        m.metalIndex = -2;
        // G = 0 would mean "no reflection at all", which no real dielectric has; LabPBR packs
        // never author it, so 0 is read as "not provided" and replaced by the common 4 %.
        float f0 = g == 0 ? 0.04 : float(g) / 255.0;
        m.f0 = vec3(f0);
    }

    int b = int(spec.b * 255.0 + 0.5);
    m.porosity = b <= 64 ? float(b) / 64.0 : 0.0;
    m.sss      = b >= 65 ? float(b - 65) / 190.0 : 0.0;

    int a = int(spec.a * 255.0 + 0.5);
    m.emission = a < 255 ? float(a) / 254.0 : 0.0;
    return m;
}

// Fresnel for any material at the given cosine (to the half vector or the view direction).
vec3 materialFresnel(Material m, float cosTheta) {
    cosTheta = saturate(cosTheta);
    if (m.metal && m.metalIndex >= 0) {
        // Exact conductor Fresnel, tinted by albedo the way LabPBR intends for predefined metals.
        vec3 f = fresnelConductor(cosTheta, METAL_N[m.metalIndex], METAL_K[m.metalIndex]);
        return f;
    }
    return m.f0 + (1.0 - m.f0) * pow5(1.0 - cosTheta);
}

// Decode a LabPBR normal-map texel (rgba in [0,1]) to tangent space. Returns xyz normal and AO.
vec4 decodeLabNormal(vec4 tex, float strength) {
    vec2 xy = tex.rg * 2.0 - 1.0;
    #ifdef NORMAL_MAP_Y_FLIP
    xy.y = -xy.y;
    #endif
    // A texture with all channels zero is a missing map that Iris substituted badly; treat flat.
    if (dot(tex, tex) < 1e-6) return vec4(0.0, 0.0, 1.0, 1.0);
    xy *= strength;
    float z = sqrt(saturate(1.0 - dot(xy, xy)));
    return vec4(normalize(vec3(xy, max(z, 1e-3))), tex.b);
}

#endif

#ifndef MATERIAL_LABPBR_GLSL
#define MATERIAL_LABPBR_GLSL
#include "/lib/core/math.glsl"
#include "/lib/core/color.glsl"
#include "/lib/material/material_ids.glsl"

// LabPBR 1.3 (shaderlabs.org, read 2026-10-24):
//   _n: R,G normal XY in DirectX convention (G: 0 = up, 255 = down), B = AO (255 = none),
//       A = height (255 = surface, 0 = 25 % depth). Z is reconstructed.
//   _s: R perceptual smoothness, roughness = (1 - R)^2
//       G 0..229 linear F0, 230..237 predefined metals (complex IOR), 238..254 reserved
//         (treated as albedo metal), 255 albedo-as-F0 metal
//       B 0..64 porosity, 65..255 subsurface scattering
//       A 0..254 emission, 255 = none
// colortex3 stores those four bytes unchanged; vanilla blocks get synthesised bytes.

struct Material {
    vec3  albedo;     // linear
    float roughness;  // GGX alpha
    float smoothness; // perceptual
    vec3  f0;         // normal-incidence reflectance
    bool  metal;
    int   metalCode;  // 230..237 for IOR metals, 255 for albedo metal, 0 otherwise
    float porosity;   // 0..1
    float sss;        // 0..1
    float emission;   // 0..1
    float ao;         // texture AO * vertex AO
    int   id;
};

// Complex refractive indices (n, k) at R/G/B for the LabPBR hardcoded metals.
void labMetalIor(int code, out vec3 n, out vec3 k) {
    if (code == 230)      { n = vec3(2.9114, 2.9497, 2.5845);  k = vec3(3.0893, 2.9318, 2.7670); } // iron
    else if (code == 231) { n = vec3(0.18299, 0.42108, 1.3734); k = vec3(3.4242, 2.3459, 1.7704); } // gold
    else if (code == 232) { n = vec3(1.3456, 0.96521, 0.61722); k = vec3(7.4746, 6.3995, 5.3031); } // aluminium
    else if (code == 233) { n = vec3(3.1071, 3.1812, 2.3230);  k = vec3(3.3314, 3.3291, 3.1350); } // chrome
    else if (code == 234) { n = vec3(0.27105, 0.67693, 1.3164); k = vec3(3.6092, 2.6248, 2.2921); } // copper
    else if (code == 235) { n = vec3(1.9100, 1.8300, 1.4400);  k = vec3(3.5100, 3.4000, 3.1800); } // lead
    else if (code == 236) { n = vec3(2.3757, 2.0847, 1.8453);  k = vec3(4.2655, 3.7153, 3.1365); } // platinum
    else                  { n = vec3(0.15943, 0.14512, 0.13547); k = vec3(3.9291, 3.1900, 2.3808); } // silver
}

// Normal-incidence reflectance of a conductor: ((n-1)^2 + k^2) / ((n+1)^2 + k^2).
vec3 conductorF0(vec3 n, vec3 k) {
    return (sq(n - 1.0) + k * k) / (sq(n + 1.0) + k * k);
}

Material decodeMaterial(vec3 albedoLinear, vec4 specBytes, float ao, int id) {
    Material m;
    m.albedo = albedoLinear;
    m.id = id;
    m.ao = ao;
    m.smoothness = specBytes.r;
    // Clamp alpha away from 0: perfectly smooth GGX is a delta lobe and would alias.
    m.roughness = max(sq(1.0 - specBytes.r), 0.0016);

    int g = int(specBytes.g * 255.0 + 0.5);
    m.metalCode = 0;
    m.metal = g >= 230;
    if (!m.metal) {
        m.f0 = vec3(float(g) / 255.0);
    } else if (g <= 237) {
        vec3 n, k;
        labMetalIor(g, n, k);
        m.metalCode = g;
        m.f0 = conductorF0(n, k);
    } else {
        m.metalCode = 255;
        m.f0 = albedoLinear;
    }

    int b = int(specBytes.b * 255.0 + 0.5);
    m.porosity = b <= 64 ? float(b) / 64.0 : 0.0;
    m.sss = b >= 65 ? float(b - 65) / 190.0 : 0.0;

    int a = int(specBytes.a * 255.0 + 0.5);
    m.emission = a < 255 ? float(a) / 254.0 : 0.0;
    return m;
}

// Synthesised LabPBR bytes (as 0..1 floats) for blocks without a resource-pack specular map.
// Conservative by design: vanilla art is not authored for PBR, so most surfaces stay rough
// dielectrics and only clearly special materials get distinct responses.
vec4 synthesizeSpecular(int id, vec3 albedoSrgb, float vanillaMetals) {
    float lum = luminance(albedoSrgb);
    float smoothness = 0.18;
    float f0Byte = 10.0;          // F0 ~ 0.04
    float bByte = 0.0;            // porosity / SSS
    float emission = 0.0;

    if (id == MAT_WATER || id == MAT_ICE) { smoothness = 0.96; f0Byte = 5.0; }
    else if (id == MAT_GLASS || id == MAT_GLASS_STAINED) { smoothness = 0.97; f0Byte = 10.0; }
    else if (id == MAT_SLIME) { smoothness = 0.8; f0Byte = 9.0; bByte = 65.0 + 0.5 * 190.0; }
    else if (id == MAT_POLISHED) { smoothness = 0.62; }
    else if (id == MAT_SNOW) { smoothness = 0.28; bByte = 65.0 + 0.35 * 190.0; }
    else if (id == MAT_SAND) { smoothness = 0.08; bByte = 64.0; }
    else if (id == MAT_LEAVES) { smoothness = 0.32; bByte = 65.0 + 0.7 * 190.0; }
    else if (id >= MAT_PLANT_SHORT && id <= MAT_VINE || id == MAT_WATER_PLANT || id == MAT_LILY_PAD) {
        smoothness = 0.26; bByte = 65.0 + 0.55 * 190.0;
    }
    else if (vanillaMetals > 0.5 && id == MAT_METAL_IRON)   { smoothness = 0.58; f0Byte = 230.0; }
    else if (vanillaMetals > 0.5 && id == MAT_METAL_GOLD)   { smoothness = 0.64; f0Byte = 231.0; }
    else if (vanillaMetals > 0.5 && id == MAT_METAL_COPPER) { smoothness = 0.52; f0Byte = 234.0; }
    else if (vanillaMetals > 0.5 && id == MAT_METAL_DARK)   { smoothness = 0.55; f0Byte = 255.0; }
    else { bByte = 12.0; } // generic terrain: slightly porous so rain darkens it a little

    if (id == MAT_LAVA) {
        emission = 1.0;
    } else if (isEmitter(id)) {
        // Only the bright texels of an emitter glow (flame, not the torch stick). The mask is
        // relative to the texel's own saturation-aware brightness.
        float peak = maxOf(albedoSrgb);
        emission = smoothstep(0.45, 0.85, peak) * (id == MAT_EMIT_MAGMA ? 0.6 : 1.0);
        if (id == MAT_EMIT_LANTERN || id == MAT_EMIT_COOL || id == MAT_EMIT_WHITE) emission = smoothstep(0.3, 0.75, lum);
    } else if (id == MAT_NETHER_PORTAL) {
        emission = 0.9;
    }
    return vec4(smoothness, f0Byte / 255.0, bByte / 255.0, emission >= 1.0 ? 254.0 / 255.0 : emission * 254.0 / 255.0);
}

// Iris binds an all-zero specular texture when the resource pack has none: treat "all zero"
// as "no data" (a real LabPBR texel with F0 = 0 and smoothness = 0 is physically meaningless).
bool hasLabSpecular(vec4 s) { return dot(s, vec4(1.0)) > 0.0; }

#endif

#ifndef MERIDIAN_WETNESS
#define MERIDIAN_WETNESS

// Rain wetness and puddles, applied to the decoded material in the deferred lighting pass.
//
// * Exposure: only surfaces open to the sky get wet (vanilla sky light 14-15).
// * Drying: Iris's `wetness` uniform rises during rain and decays afterwards (wetnessHalflife /
//   drynessHalflife), giving gradual wetting and drying.
// * Porous materials (LabPBR porosity) absorb water: they darken (water fills pores and raises
//   the effective refractive index, Lekner & Dorf 1988) and stay rough; non-porous materials
//   gain a water film that makes them glossier.
// * Puddles form on upward faces where low-frequency noise and the LabPBR height map are low,
//   growing as wetness rises; they are mirror-flat water with rain ripples.

const float wetnessHalflife = 300.0;
const float drynessHalflife = 120.0;

float puddleNoise(vec2 xz) {
    float n = valueNoise(xz * 0.07) * 0.6 + valueNoise(xz * 0.21 + 13.7) * 0.3 + valueNoise(xz * 0.63 - 4.1) * 0.1;
    return n;
}

// Returns the puddle coverage (0..1) and modifies material and normal in place.
float applyWetness(inout Material m, inout vec3 n, vec3 geoN, vec2 lm, vec3 worldPos, int flags, float height) {
    #ifdef WET_SURFACES
    float exposed = smoothstep(0.86, 0.96, lm.y);
    float wet = saturate(wetness * 1.2) * exposed * biomeWet;
    if (wet <= 0.001) return 0.0;
    float up = saturate(geoN.y * 1.25 - 0.25);
    float film = wet * mix(0.35, 1.0, up);

    // Porous darkening and gloss.
    float poro = m.porosity;
    m.albedo = mix(m.albedo, pow(m.albedo, vec3(1.0 + 1.4 * poro)) * (1.0 - 0.25 * poro), film);
    float glossTarget = mix(0.03, m.alpha, poro * 0.85);
    m.alpha = mix(m.alpha, glossTarget, film * (1.0 - poro * 0.6));
    if (!m.metal) m.f0 = mix(m.f0, max(m.f0, vec3(0.02)), film);

    float puddle = 0.0;
    #ifdef PUDDLES
    if (!hasFlag(flags, FLAG_NO_PUDDLE) && up > 0.9) {
        float level = wet * PUDDLE_AMOUNT;
        float field = puddleNoise(worldPos.xz) * 0.8 + (1.0 - height) * 0.35;
        float threshold = 1.05 - level * 0.75;
        puddle = smoothstep(threshold - 0.08, threshold + 0.02, field) * up;
        if (puddle > 0.0) {
            m.albedo *= mix(1.0, 0.72, puddle);
            m.alpha = mix(m.alpha, 0.0016, puddle);
            if (!m.metal) m.f0 = mix(m.f0, vec3(0.02), puddle);
            vec3 flatN = geoN;
            #ifdef RAIN_RIPPLES
            vec2 g = rainRippleGradient(worldPos.xz, frameTimeCounter) * rainStrength;
            flatN = normalize(vec3(-g.x, 1.0, -g.y));
            #endif
            n = normalize(mix(n, flatN, puddle));
        }
    }
    #endif
    return puddle;
    #else
    return 0.0;
    #endif
}

#endif

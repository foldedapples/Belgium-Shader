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

// Puddle field: domain-warped fractal value noise, so puddles are irregular (lobed, elongated,
// merging) rather than round blobs. Feature size ~9 blocks at PUDDLE_SIZE 1.
float puddleNoise(vec2 xz) {
    vec2 w = vec2(valueNoise(xz * 0.05), valueNoise(xz * 0.05 + vec2(31.7, 11.3))) * 2.0 - 1.0;
    vec2 p = xz * (0.11 / PUDDLE_SIZE) + w * 1.2;
    return valueNoise(p) * 0.65 + valueNoise(p * 2.7 + vec2(5.1, -3.3)) * 0.25 + valueNoise(p * 7.3) * 0.10;
}

// Threshold for a share of ground covered: calibrated on the field above (tools/tests and
// docs/REGRESSION_AUDIT.md): 0.726 covers 8 %, each doubling of PUDDLE_AMOUNT adds ~2.5x area.
// The old rule (field 0.8 x noise against 1.05 - 0.75 x wetness) covered 77 % of open ground.
float puddleThreshold(float wet) {
    float full = 0.726 - 0.085 * log2(PUDDLE_AMOUNT);
    return full + (1.0 - wet) * 0.25;          // puddles grow in as the ground soaks
}

// Returns the puddle coverage (0..1) and modifies material and normal in place. `playerPos` is the
// camera-relative position (ripples need its precision), `worldPos` = playerPos + cameraPosition.
float applyWetness(inout Material m, inout vec3 n, vec3 geoN, vec2 lm, vec3 playerPos, vec3 worldPos, int flags, float height) {
    #ifdef WET_SURFACES
    float exposed = smoothstep(0.86, 0.96, lm.y);
    float wet = saturate(wetness * 1.2) * exposed * biomeWet;
    if (wet <= 0.001) return 0.0;
    float up = saturate(geoN.y * 1.25 - 0.25);
    float film = wet * mix(0.35, 1.0, up);

    // Porous darkening and gloss.
    float poro = m.porosity;
    m.albedo = mix(m.albedo, pow(m.albedo, vec3(1.0 + 1.4 * poro)) * (1.0 - 0.25 * poro), film);
    // A wet film is a sheen, not a mirror (alpha >= 0.09, perceptual roughness ~0.3); only puddles
    // become mirror-flat. At 0.03 every wet surface without porosity data turned glassy.
    float glossTarget = mix(min(m.alpha, 0.09), m.alpha, poro * 0.85);
    m.alpha = mix(m.alpha, glossTarget, film * (1.0 - poro * 0.6));
    if (!m.metal) m.f0 = mix(m.f0, max(m.f0, vec3(0.02)), film);

    float puddle = 0.0;
    #ifdef PUDDLES
    if (!hasFlag(flags, FLAG_NO_PUDDLE) && up > 0.9) {
        // LabPBR height lowers the threshold in the texture's recesses (1 = flat / no height map).
        float field = puddleNoise(worldPos.xz) + (1.0 - height) * 0.15;
        float threshold = puddleThreshold(wet);
        puddle = smoothstep(threshold - 0.03, threshold + 0.012, field) * up;
        if (puddle > 0.0) {
            m.albedo *= mix(1.0, 0.72, puddle);
            m.alpha = mix(m.alpha, 0.0016, puddle);
            if (!m.metal) m.f0 = mix(m.f0, vec3(0.02), puddle);
            vec3 flatN = geoN;
            #ifdef RAIN_RIPPLES
            vec2 g = rainRippleGradient(playerPos.xz, frameTimeCounter) * rainStrength;
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

// Snow cover in snowy biomes (material level, no extra geometry): settles on the tops of
// sky-exposed surfaces, thinning out on slopes and along a world-space noise edge so cover is
// patchy rather than a uniform white sheet, and grows while it snows (Iris wetness rises with any
// precipitation). Covered parts become snow: bright, moderately rough, slightly translucent,
// never metal. Entities, the hand and emitters stay clear. Returns the cover (0..1).
float applySnow(inout Material m, inout vec3 n, vec3 geoN, vec2 lm, vec3 worldPos, int flags) {
    #ifdef SNOW_OVERLAY
    if (biomeSnowy <= 0.01 || hasFlag(flags, FLAG_ENTITY) || hasFlag(flags, FLAG_HAND) || m.emission > 0.01) return 0.0;
    float exposed = smoothstep(0.8, 0.95, lm.y);
    float up = saturate((geoN.y - 0.55) * 2.6);
    if (exposed * up <= 0.0) return 0.0;
    float amount = biomeSnowy * SNOW_AMOUNT * (0.6 + 0.4 * saturate(wetness * 1.5));
    float field = valueNoise(worldPos.xz * 0.35) * 0.7 + valueNoise(worldPos.xz * 1.7 + 9.1) * 0.3;
    float t = 1.0 - 0.55 * amount;
    float cover = smoothstep(t - 0.08, t + 0.08, field * 0.4 + up * 0.6) * exposed;
    if (cover <= 0.0) return 0.0;
    m.albedo = mix(m.albedo, vec3(0.80, 0.83, 0.88), cover);
    m.alpha = mix(m.alpha, 0.30, cover);
    m.f0 = mix(m.f0, vec3(0.02), cover);
    if (cover > 0.5) { m.metal = false; m.metalIndex = -2; }
    m.sss = mix(m.sss, 0.45, cover);
    m.porosity = mix(m.porosity, 0.0, cover);
    n = normalize(mix(n, geoN, cover * 0.8));
    return cover;
    #else
    return 0.0;
    #endif
}

#endif

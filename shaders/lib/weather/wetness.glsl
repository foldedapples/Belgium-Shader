#ifndef WEATHER_WETNESS_GLSL
#define WEATHER_WETNESS_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/material/labpbr.glsl"

// Rain on surfaces (ORIGINAL_ARCHITECTURE.md sec. 17).
// * Wetness: only where rain reaches (open sky light, precipitation biome, not snow) and more
//   on up-facing faces; it accumulates and dries with Minecraft's smoothed `wetness`.
// * Porous materials (LabPBR porosity) darken as they absorb water; non-porous ones gain a
//   water film and become smoother. Nothing becomes a mirror except puddles.
// * Puddles: low-frequency noise on up-facing surfaces, controlled by PUDDLE_AMOUNT.
// * Ripples: procedural rings from raindrops on puddles and water.

#include "/lib/core/textures.glsl"

float rainReach(vec3 geoNormal, float skyLight) {
    float open = smoothstep(0.86, 0.97, skyLight);
    float facing = mix(0.35, 1.0, smoothstep(-0.2, 0.7, geoNormal.y));
    float climate = biomePrecipSmooth * (1.0 - biomeSnowSmooth);
    return open * facing * climate;
}

float surfaceWetness(vec3 geoNormal, float skyLight) {
    #ifdef WETNESS
        return saturate(fsWeather.x * rainReach(geoNormal, skyLight));
    #else
        return 0.0;
    #endif
}

float puddleMask(vec3 worldPos, vec3 geoNormal, float wet) {
    #if defined WETNESS && defined PUDDLES
        if (geoNormal.y < 0.95 || wet <= 0.0) return 0.0;
        vec2 xz = mod(worldPos.xz, 16384.0);
        float n = texture(noise2dTex, xz / 96.0).r * 0.7 + texture(noise2dTex, xz / 23.0).g * 0.3;
        float threshold = 1.0 - PUDDLE_AMOUNT * wet * 0.55;
        return smoothstep(threshold, threshold + 0.06, n) * smoothstep(0.3, 0.8, wet);
    #else
        return 0.0;
    #endif
}

// Slope of expanding rain-drop rings (blocks/block). Two layers of jittered cells, each with
// its own drop period, so the pattern never visibly repeats.
vec2 rainRippleSlope(vec2 xz, float time, float intensity) {
    vec2 slope = vec2(0.0);
    if (intensity <= 0.0) return slope;
    for (int layer = 0; layer < 2; layer++) {
        float scale = layer == 0 ? 2.6 : 1.7;
        vec2 p = xz * scale + float(layer) * 17.3;
        ivec2 base = ivec2(floor(p));
        for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
            ivec2 c = base + ivec2(x, y);
            vec2 h = hash22(c + ivec2(layer * 131, 7));
            vec2 centre = vec2(c) + 0.15 + 0.7 * h;
            float period = 0.85 + 0.6 * h.x;
            float phase = fract(time / period + h.y);
            vec2 d = p - centre;
            float r = length(d);
            float ring = r - phase * 1.1;
            float w = 0.12;
            if (abs(ring) > 3.0 * w) continue;
            float amp = sq(1.0 - phase) * 0.06;
            const float k = TAU / 0.22;
            float env = exp(-sq(ring / w));
            float dfdr = amp * (k * cos(k * ring) - 2.0 * ring / (w * w) * sin(k * ring)) * env;
            slope += (d / max(r, 1e-3)) * dfdr * scale;
        }
    }
    return slope * intensity * 0.05;
}

// Modifies a decoded material and its normal for rain. `worldPos` is absolute (for noise).
void applyWetness(inout Material m, inout vec3 n, vec3 geoNormal, float wet, float puddle, vec3 worldPos) {
    if (wet <= 0.0) return;
    // Darkening from absorbed water, strongest for porous materials.
    float darken = wet * mix(0.12, 0.5, m.porosity);
    m.albedo *= 1.0 - darken;
    // A thin film raises smoothness on non-porous surfaces.
    float film = wet * (1.0 - 0.7 * m.porosity);
    m.smoothness = mix(m.smoothness, max(m.smoothness, 0.72), film * 0.75);
    if (puddle > 0.0) {
        m.smoothness = mix(m.smoothness, 0.97, puddle);
        if (!m.metal) m.f0 = mix(m.f0, vec3(0.02), puddle);
        n = normalize(mix(n, geoNormal, puddle));
        #ifdef RAIN_RIPPLES
            vec2 s = rainRippleSlope(worldPos.xz, frameTimeCounter, fsWeather.z) * puddle;
            n = normalize(n + vec3(-s.x, 0.0, -s.y));
        #endif
    }
    m.roughness = max(sq(1.0 - m.smoothness), 0.0016);
}

#endif

#ifndef MERIDIAN_NETHER
#define MERIDIAN_NETHER

// The Nether: no sky, no sun. Light comes from lava seas, fire and glowing blocks, and the air is
// thick with smoke and ash. The biome's own fog colour (Iris `fogColor`, which follows the biome:
// crimson, warped, soul sand valley, basalt deltas, wastes) tints the haze, so each biome keeps its
// identity. The haze itself is ray marched in the composite fog pass (lib/nether/nether_fog.glsl).

const float NETHER_LAVA_LEVEL = 31.0;

vec3 netherHazeColor() {
    // Vanilla fog colours are dim and low-saturation; lift them into a warm, physically plausible
    // range and keep their hue.
    vec3 c = srgbToLinear(max(fogColor, vec3(0.02)));
    float l = luminance(c);
    c = c / max(l, 1e-3) * 0.08;
    return c;
}

// Glow of the lava sea seen from above or below: strongest near the lava level.
vec3 lavaGlow(float worldY) {
    float h = max(worldY - NETHER_LAVA_LEVEL, 0.0);
    return vec3(1.0, 0.32, 0.06) * 0.6 * exp(-h / 28.0);
}

vec3 netherSkyRadiance(vec3 dir) {
    // Looking up into the void above the roof (seen only through gaps): dark smoke lit from below.
    vec3 haze = netherHazeColor();
    return haze * (0.6 + 0.4 * saturate(-dir.y)) + lavaGlow(cameraPosition.y) * 0.05;
}

// Diffuse ambient (irradiance / pi) on a surface in the Nether.
vec3 netherAmbient(vec3 n, vec3 worldPos) {
    vec3 haze = netherHazeColor() * 0.5;
    vec3 fromBelow = lavaGlow(worldPos.y) * saturate(-n.y * 0.6 + 0.4);
    return haze + fromBelow * 0.25;
}

#endif

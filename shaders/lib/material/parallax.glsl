#ifndef MATERIAL_PARALLAX_GLSL
#define MATERIAL_PARALLAX_GLSL
#include "/lib/core/math.glsl"

// Parallax occlusion mapping from the LabPBR height channel (_n alpha: 1 = surface,
// 0 = 25 % depth). The ray is marched in tangent space inside the texture's own atlas tile
// (wrapped so it never reads a neighbouring texture), then refined linearly between the last
// two layers. Sampling uses the gradients of the *unshifted* UVs so mip selection does not
// jump at the shifted coordinates.

vec2 wrapInTile(vec2 uv, vec2 tileOrigin, vec2 tileSize) {
    return tileOrigin + fract((uv - tileOrigin) / tileSize) * tileSize;
}

// viewTs: unit vector toward the camera in tangent space (z up out of the surface).
vec2 parallaxUv(sampler2D heightTex, vec2 uv, vec2 tileOrigin, vec2 tileSize, vec3 viewTs, float fade) {
    if (fade <= 0.0 || viewTs.z <= 0.05) return uv;
    vec2 dx = dFdx(uv), dy = dFdy(uv);
    const int STEPS = PARALLAX_SAMPLES;
    float layer = 1.0 / float(STEPS);
    // Full depth (height 0) corresponds to 25 % of the tile, scaled by the user setting.
    vec2 shift = viewTs.xy / viewTs.z * 0.25 * PARALLAX_DEPTH * fade * tileSize;
    vec2 stepUv = -shift * layer;
    vec2 cur = uv;
    float depth = 0.0;
    float h = textureGrad(heightTex, cur, dx, dy).a;
    float prevDiff = (1.0 - h) - depth;
    for (int i = 0; i < STEPS; i++) {
        if (1.0 - h <= depth) break;
        cur = wrapInTile(cur + stepUv, tileOrigin, tileSize);
        depth += layer;
        float hn = textureGrad(heightTex, cur, dx, dy).a;
        prevDiff = (1.0 - h) - (depth - layer);
        h = hn;
    }
    // Linear refinement between the last two layers.
    float diff = (1.0 - h) - depth;
    float t = saturate(diff / (diff - prevDiff + 1e-5));
    vec2 refined = wrapInTile(cur - stepUv * t, tileOrigin, tileSize);
    return refined;
}

#endif

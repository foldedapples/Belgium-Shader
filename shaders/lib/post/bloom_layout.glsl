#ifndef POST_BLOOM_LAYOUT_GLSL
#define POST_BLOOM_LAYOUT_GLSL
#include "/lib/core/uniforms.glsl"

uniform sampler2D bloomAtlasTex;

// Bloom pyramid packed into one image (bloomAtlas, 0.75 x 0.5 of the screen):
//   level 1 (1/2 res) at (0, 0)
//   level k >= 2 (1/2^k res) in a column at x = W/2, stacked from y = 0 downward:
//   level 2 at y = 0, level 3 at y = H/4, level 4 at y = H/4 + H/8, ...
// All coordinates are atlas pixels; W, H are the screen size.

const int BLOOM_LEVELS = 5;

ivec2 bloomLevelSize(int level) {
    ivec2 screen = ivec2(viewWidth, viewHeight);
    return max(screen >> level, ivec2(1));
}

ivec2 bloomLevelOffset(int level) {
    if (level <= 1) return ivec2(0);
    ivec2 screen = ivec2(viewWidth, viewHeight);
    int y = 0;
    for (int k = 2; k < level; k++) y += max(screen.y >> k, 1);
    return ivec2(screen.x >> 1, y);
}

// The allocated size (Iris rounds the relative size to whole texels).
vec2 bloomAtlasSize() { return vec2(textureSize(bloomAtlasTex, 0)); }

// Normalised atlas uv of a point `uv` (0..1) inside `level`, clamped half a texel inside the
// level so bilinear taps never bleed into a neighbouring level.
vec2 bloomLevelUv(int level, vec2 uv) {
    vec2 size = vec2(bloomLevelSize(level));
    vec2 p = clamp(uv * size, vec2(0.5), size - 0.5);
    return (vec2(bloomLevelOffset(level)) + p) / bloomAtlasSize();
}

#endif

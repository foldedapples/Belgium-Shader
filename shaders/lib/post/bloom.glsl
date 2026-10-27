#ifndef MERIDIAN_BLOOM
#define MERIDIAN_BLOOM

// Tile layout of the bloom atlas (colortex9, half resolution). Tile for blur level L (2..7) has
// size 2^-(L-1) of the atlas (level 2 = half the atlas width). Level 2 sits top-left, the others
// in a row beneath it, with 4-pixel gaps so bilinear taps never cross tiles.

const int BLOOM_FIRST = 2;
const int BLOOM_LAST = 7;

vec4 bloomTileRect(int level) {
    vec2 atlas = vec2(viewWidth, viewHeight) * 0.5;
    float gap = 4.0;
    vec2 size = atlas * exp2(-float(level - 1));
    if (level == BLOOM_FIRST) return vec4(vec2(gap) / atlas, size / atlas);
    // Smaller levels sit in a row under the first tile.
    float x = gap;
    for (int l = BLOOM_FIRST + 1; l < level; l++) x += atlas.x * exp2(-float(l - 1)) + gap;
    return vec4(vec2(x, atlas.y * 0.5 + 2.0 * gap) / atlas, size / atlas);
}

bool bloomTileFromAtlas(vec2 atlasUv, out int level, out vec2 local) {
    for (int l = BLOOM_FIRST; l <= BLOOM_LAST; l++) {
        vec4 r = bloomTileRect(l);
        vec2 q = (atlasUv - r.xy) / r.zw;
        if (all(greaterThanEqual(q, vec2(0.0))) && all(lessThan(q, vec2(1.0)))) {
            level = l;
            local = q;
            return true;
        }
    }
    level = 0;
    local = vec2(0.0);
    return false;
}

#ifdef BLOOM_COMBINE
vec3 sampleBloomTile(sampler2D atlas, int level, vec2 uv) {
    vec4 r = bloomTileRect(level);
    vec2 atlasSize = vec2(viewWidth, viewHeight) * 0.5;
    vec2 tileTexel = 1.0 / (r.zw * atlasSize);
    uv = clamp(uv, tileTexel, 1.0 - tileTexel);
    return texture(atlas, r.xy + uv * r.zw).rgb;
}

// Wide, smooth glare: a sum of the levels with weights falling slowly (energy normalised).
vec3 combineBloom(sampler2D atlas, vec2 uv) {
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int l = BLOOM_FIRST; l <= BLOOM_LAST; l++) {
        float w = exp2(-0.55 * float(l - BLOOM_FIRST));
        sum += sampleBloomTile(atlas, l, uv) * w;
        wsum += w;
    }
    return sum / wsum;
}
#endif

#endif

// composite7..15.csh - bloom pyramid in bloomAtlas (lib/post/bloom_layout.glsl).
//   BLOOM_PASS 0      : scene (colortex0) -> level 1, firefly-weighted 4-tap downsample
//   BLOOM_PASS 1..4   : level k -> level k+1, 4 bilinear taps (a 4x4 box)
//   BLOOM_PASS 5..8   : level k += tent-filtered upsample of level k+1, for k = 4 .. 1
// Reads and writes of one dispatch touch different levels except each thread's own texel, and
// Iris places a barrier between dispatches, so no pass sees partial results.
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/post/bloom_layout.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
// One thread per texel of the level being written: 1 / 2^level of the screen.
#if BLOOM_PASS == 0 || BLOOM_PASS == 8
    const vec2 workGroupsRender = vec2(0.5, 0.5);          // level 1
#elif BLOOM_PASS == 1 || BLOOM_PASS == 7
    const vec2 workGroupsRender = vec2(0.25, 0.25);        // level 2
#elif BLOOM_PASS == 2 || BLOOM_PASS == 6
    const vec2 workGroupsRender = vec2(0.125, 0.125);      // level 3
#elif BLOOM_PASS == 3 || BLOOM_PASS == 5
    const vec2 workGroupsRender = vec2(0.0625, 0.0625);    // level 4
#else
    const vec2 workGroupsRender = vec2(0.03125, 0.03125);  // level 5
#endif

uniform sampler2D colortex0;
layout(rgba16f) uniform image2D bloomAtlas;

// Karis-style weighting against single bright pixels (fireflies) on the first downsample,
// in displayed (exposed) units. On raw radiance it did nothing at night (everything ~1e-4), so
// the moon and lamps bloomed at full strength while the sun was suppressed by day.
vec3 fireflySafeAverage(vec3 a, vec3 b, vec3 c, vec3 d) {
    float e = frameStateValid() && fsExposure.x > 0.0 ? fsExposure.x : 1.0;
    float wa = 1.0 / (1.0 + luminance(a) * e), wb = 1.0 / (1.0 + luminance(b) * e);
    float wc = 1.0 / (1.0 + luminance(c) * e), wd = 1.0 / (1.0 + luminance(d) * e);
    return (a * wa + b * wb + c * wc + d * wd) / (wa + wb + wc + wd);
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    #if BLOOM_PASS <= 4
        const int dst = BLOOM_PASS + 1;
    #else
        const int dst = 9 - BLOOM_PASS;    // 5 -> 4, 6 -> 3, 7 -> 2, 8 -> 1
    #endif
    ivec2 size = bloomLevelSize(dst);
    if (any(greaterThanEqual(p, size))) return;
    vec2 uv = (vec2(p) + 0.5) / vec2(size);
    vec2 texel = 1.0 / vec2(size);
    ivec2 dstPx = bloomLevelOffset(dst) + p;

    #if BLOOM_PASS == 0
        vec2 o = texel * 0.25;
        vec3 a = sanitizeRadiance(textureLod(colortex0, uv + vec2(-o.x, -o.y), 0.0).rgb);
        vec3 b = sanitizeRadiance(textureLod(colortex0, uv + vec2( o.x, -o.y), 0.0).rgb);
        vec3 c = sanitizeRadiance(textureLod(colortex0, uv + vec2(-o.x,  o.y), 0.0).rgb);
        vec3 d = sanitizeRadiance(textureLod(colortex0, uv + vec2( o.x,  o.y), 0.0).rgb);
        vec3 result = fireflySafeAverage(a, b, c, d);
        // Highlight compression of the bloom input around 64x white (exposed): lamps and
        // emissives (2-20x white) bloom almost unchanged, while the sun disk (hundreds of times white)
        // no longer floods a large part of the screen with its glow. The image itself keeps the
        // full radiance; only what bloom spreads is limited.
        {
            float e = frameStateValid() && fsExposure.x > 0.0 ? fsExposure.x : 1.0;
            float l = luminance(result) * e;
            const float CAP = 64.0;
            if (l > 1e-6) result *= inversesqrt(1.0 + sq(l / CAP));   // -5 % at 20x, ~64x for the sun
        }
    #elif BLOOM_PASS <= 4
        const int src = BLOOM_PASS;
        vec2 o = texel * 0.5;
        vec3 result = 0.25 * (textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2(-o.x, -o.y)), 0.0).rgb
                            + textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2( o.x, -o.y)), 0.0).rgb
                            + textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2(-o.x,  o.y)), 0.0).rgb
                            + textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2( o.x,  o.y)), 0.0).rgb);
    #else
        const int src = dst + 1;
        vec2 o = texel;   // 3x3 tent over the coarser level
        vec3 up = vec3(0.0);
        up += 1.0 * textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2(-o.x, -o.y)), 0.0).rgb;
        up += 2.0 * textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2(0.0, -o.y)), 0.0).rgb;
        up += 1.0 * textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2( o.x, -o.y)), 0.0).rgb;
        up += 2.0 * textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2(-o.x, 0.0)), 0.0).rgb;
        up += 4.0 * textureLod(bloomAtlasTex, bloomLevelUv(src, uv), 0.0).rgb;
        up += 2.0 * textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2( o.x, 0.0)), 0.0).rgb;
        up += 1.0 * textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2(-o.x,  o.y)), 0.0).rgb;
        up += 2.0 * textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2(0.0,  o.y)), 0.0).rgb;
        up += 1.0 * textureLod(bloomAtlasTex, bloomLevelUv(src, uv + vec2( o.x,  o.y)), 0.0).rgb;
        up /= 16.0;
        vec3 here = imageLoad(bloomAtlas, dstPx).rgb;
        // Wider levels contribute progressively (BLOOM_RADIUS); the sum is normalised in final.
        vec3 result = here + up * BLOOM_RADIUS;
    #endif
    imageStore(bloomAtlas, dstPx, vec4(sanitizeRadiance(result), 1.0));
}
#endif

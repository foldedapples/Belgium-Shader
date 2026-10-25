// composite2 - adds the volumetric light (depth-aware upsample of colortex10) and applies the
// Nether's heat shimmer.
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
uniform sampler2D colortex0;
uniform sampler2D colortex10;
uniform sampler2D depthtex0;

in vec2 texCoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outScene;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec2 uv = texCoord;

    #if defined DIM_NETHER && defined HEAT_HAZE
    {
        // Heat shimmer: a slow refraction offset that grows with distance (hot air columns).
        float d = texelFetch(depthtex0, px, 0).r;
        float lin = linearizeDepth(d, near, far);
        float strength = HEAT_HAZE_STRENGTH * 0.0025 * smoothstep(4.0, 48.0, lin);
        float t = frameTimeCounter;
        vec2 wobble = vec2(sin(uv.y * 38.0 + t * 2.3) + sin(uv.y * 71.0 - t * 3.1) * 0.5,
                           sin(uv.x * 29.0 + t * 1.7) * 0.6);
        uv = clamp(uv + wobble * strength, vec2(0.0), vec2(1.0));
    }
    vec3 scene = texture(colortex0, uv).rgb;
    #else
    vec3 scene = texelFetch(colortex0, px, 0).rgb;
    #endif

    #if !defined DIM_NETHER && defined VOLUMETRIC_LIGHT
    {
        // Depth-aware 2x2 upsample from the half-resolution volumetric buffer.
        vec2 lowSize = vec2(viewWidth, viewHeight) * 0.5;
        vec2 lp = texCoord * lowSize - 0.5;
        ivec2 base = ivec2(floor(lp));
        vec2 f = lp - vec2(base);
        float d0 = linearizeDepth(texelFetch(depthtex0, px, 0).r, near, far);
        vec3 sum = vec3(0.0);
        float wsum = 0.0;
        for (int y = 0; y <= 1; y++) for (int x = 0; x <= 1; x++) {
            ivec2 q = clamp(base + ivec2(x, y), ivec2(0), ivec2(lowSize) - 1);
            vec2 full = (vec2(q) + 0.5) * 2.0;
            float dq = linearizeDepth(texelFetch(depthtex0, ivec2(full), 0).r, near, far);
            float wb = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y);
            float w = wb / (1.0 + abs(dq - d0) / max(d0, 1.0) * 12.0) + 1e-4;
            sum += texelFetch(colortex10, q, 0).rgb * w;
            wsum += w;
        }
        scene += sum / wsum;
    }
    #endif
    outScene = vec4(sanitizeRadiance(scene), 1.0);
}
#endif

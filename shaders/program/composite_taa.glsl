// composite3 - temporal anti-aliasing. Reprojects last frame's resolved image with the
// closest depth of the 3x3 neighbourhood (keeps thin foreground edges from smearing),
// clips the history to the neighbourhood's YCoCg variance box, and blends in a
// tone-compressed space so bright pixels do not dominate.
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/material/gbuffer.glsl"
#include "/lib/core/taa_jitter.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/compat/lod.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D colortex7;
uniform sampler2D depthtex0;

in vec2 texCoord;

#if DEBUG_VIEW == DBG_TAA_REJECT || DEBUG_VIEW == DBG_MOTION
    #define TAA_WRITES_DEBUG
#endif
#ifdef TAA_WRITES_DEBUG
/* RENDERTARGETS: 0,7,11 */
layout(location = 2) out vec4 outDebug;
#else
/* RENDERTARGETS: 0,7 */
vec4 outDebug;
#endif
layout(location = 0) out vec4 outScene;
layout(location = 1) out vec4 outHistory;

// Tone compression in displayed (exposed) units: radiance is absolute, and at night it is
// ~1e-5 with exposure up to 2^9, where c / (1 + L) on raw values would be linear and let
// torches dominate the blend. Last frame's exposure is the one the image was metered with.
float taaExposure = 1.0;
vec3 compress(vec3 c) { c *= taaExposure; return c / (1.0 + luminance(c)); }
vec3 uncompress(vec3 c) { return c / max(1.0 - luminance(c), 1e-4) / taaExposure; }

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    if (frameStateValid() && fsExposure.x > 0.0) taaExposure = clamp(fsExposure.x, 1e-4, 1e6);
    vec3 current = sanitizeRadiance(texelFetch(colortex0, px, 0).rgb);

    #ifndef TAA
        outScene = vec4(current, 1.0);
        outHistory = vec4(current, 0.0);
        outDebug = vec4(0.0);
        return;
    #else
    // Neighbourhood statistics and closest depth.
    vec3 m1 = vec3(0.0), m2 = vec3(0.0);
    float closest = 1.0;
    ivec2 closestPx = px;
    ivec2 maxPx = ivec2(viewWidth, viewHeight) - 1;
    for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        ivec2 p = clamp(px + ivec2(x, y), ivec2(0), maxPx);
        vec3 c = rgbToYCoCg(compress(sanitizeRadiance(texelFetch(colortex0, p, 0).rgb)));
        m1 += c; m2 += c * c;
        float d = texelFetch(depthtex0, p, 0).r;
        if (d < closest) { closest = d; closestPx = p; }
    }
    m1 /= 9.0; m2 /= 9.0;
    vec3 sigma = sqrt(max(m2 - m1 * m1, 0.0));

    int flags = decodeByte(texelFetch(colortex4, closestPx, 0).a);
    bool hand = (flags & GB_FLAG_HAND) != 0 && closest < 1.0;

    vec2 uv = (vec2(px) + 0.5) / vec2(viewWidth, viewHeight);
    vec2 prevUv = uv;
    if (!hand) {
        vec2 cuv = (vec2(closestPx) + 0.5) / vec2(viewWidth, viewHeight);
        ScenePoint sp = scenePoint(cuv, closest, closestPx, false);
        vec3 scenePos = sp.scene;
        vec3 prev = reprojectScene(scenePos);
        prevUv = uv + (prev.xy - cuv);
    }
    vec2 motion = prevUv - uv;

    bool offscreen = any(lessThan(prevUv, vec2(0.0))) || any(greaterThan(prevUv, vec2(1.0)));
    vec4 historySample = texture(colortex7, prevUv);
    vec3 history = rgbToYCoCg(compress(sanitizeRadiance(historySample.rgb)));
    vec3 cur = rgbToYCoCg(compress(current));

    // Variance clipping: move the history toward the box centre until it is inside.
    float gamma = 1.25;
    vec3 boxMin = m1 - gamma * sigma, boxMax = m1 + gamma * sigma;
    vec3 centre = 0.5 * (boxMin + boxMax), extent = max(0.5 * (boxMax - boxMin), vec3(1e-5));
    vec3 offset = history - centre;
    vec3 units = abs(offset / extent);
    float maxUnit = maxOf(units);
    vec3 clipped = maxUnit > 1.0 ? centre + offset / maxUnit : history;
    float rejection = saturate(maxUnit - 1.0);

    float speed = length(motion * vec2(viewWidth, viewHeight));
    float blend = mix(0.08, 0.25, saturate(speed / 12.0));
    if (offscreen || !frameStateValid() || fsHeader.y < 3) { blend = 1.0; rejection = 1.0; }

    vec3 resolved = mix(clipped, cur, blend);
    vec3 outC = uncompress(yCoCgToRgb(resolved));
    outC = sanitizeRadiance(outC);

    outScene = vec4(outC, 1.0);
    outHistory = vec4(outC, rejection);
    #if DEBUG_VIEW == DBG_TAA_REJECT
        outDebug = vec4(vec3(rejection), 1.0);
    #elif DEBUG_VIEW == DBG_MOTION
        outDebug = vec4(abs(motion) * vec2(viewWidth, viewHeight) * 0.1, 0.0, 1.0);
    #else
        outDebug = vec4(0.0);
    #endif
    #endif
}
#endif

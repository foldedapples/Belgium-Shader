// composite3: temporal anti-aliasing and temporal integration of the stochastic effects
// (shadow filtering, rough reflections, AO, volumetrics). Reprojection by depth with the
// previous frame's matrices (camera-relative), Catmull-Rom history sampling, variance clipping
// in YCoCg (Salvi 2016), and a luminance-weighted blend that suppresses fireflies (Karis 2014).
// History in colortex7 (never cleared).

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/state.glsl"
#include "/lib/common/transform.glsl"
#include "/lib/common/depth.glsl"
#include "/lib/common/gbuffer.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex7;

in vec2 texcoord;

/*
const int colortex7Format = RGBA16F;
const bool colortex7Clear = false;
*/

/* RENDERTARGETS: 0,7 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outHistory;

vec3 toYCoCg(vec3 c) { return vec3(dot(c, vec3(0.25, 0.5, 0.25)), dot(c, vec3(0.5, 0.0, -0.5)), dot(c, vec3(-0.25, 0.5, -0.25))); }
vec3 fromYCoCg(vec3 c) { return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z); }

// Compress HDR before filtering so very bright pixels do not dominate (inverted after). The
// compression works in exposed (display-referred) units: in absolute radiance it is almost linear
// at night (scene values ~0.001), so torches and the Moon would dominate the history and ghost.
float taaExposure() { return max(state.exposure, 1e-6); }
vec3 tonemapTAA(vec3 c) { c *= taaExposure(); return c / (1.0 + luminance(c)); }
vec3 untonemapTAA(vec3 c) { return c / max(1.0 - luminance(c), 1e-3) / taaExposure(); }

vec3 sampleHistoryCatmullRom(vec2 uv) {
    vec2 size = vec2(viewWidth, viewHeight);
    vec2 p = uv * size;
    vec2 tc = floor(p - 0.5) + 0.5;
    vec2 f = p - tc;
    vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    vec2 w3 = f * f * (-0.5 + 0.5 * f);
    vec2 w12 = w1 + w2;
    vec2 o12 = w2 / w12;
    vec2 t0 = (tc - 1.0) / size, t3 = (tc + 2.0) / size, t12 = (tc + o12) / size;
    vec3 c = vec3(0.0);
    c += texture(colortex7, vec2(t0.x, t12.y)).rgb * w0.x * w12.y;
    c += texture(colortex7, vec2(t12.x, t0.y)).rgb * w12.x * w0.y;
    c += texture(colortex7, vec2(t12.x, t12.y)).rgb * w12.x * w12.y;
    c += texture(colortex7, vec2(t3.x, t12.y)).rgb * w3.x * w12.y;
    c += texture(colortex7, vec2(t12.x, t3.y)).rgb * w12.x * w3.y;
    float w = w0.x * w12.y + w12.x * w0.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
    return max(c / w, 0.0);
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 cur = texelFetch(colortex0, px, 0).rgb;
    #ifndef TAA
    outColor = vec4(cur, 1.0);
    outHistory = vec4(cur, 1.0);
    return;
    #endif

    // Neighbourhood statistics (3x3) in YCoCg of compressed colour.
    vec3 m1 = vec3(0.0), m2 = vec3(0.0);
    float closestDepth = 1.0;
    ivec2 closestOff = ivec2(0);
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        ivec2 q = clamp(px + ivec2(i, j), ivec2(0), ivec2(viewWidth, viewHeight) - 1);
        vec3 s = toYCoCg(tonemapTAA(texelFetch(colortex0, q, 0).rgb));
        m1 += s; m2 += s * s;
        float d = texelFetch(depthtex0, q, 0).r;
        if (d < closestDepth) { closestDepth = d; closestOff = ivec2(i, j); }
    }
    m1 /= 9.0; m2 /= 9.0;
    vec3 sigma = sqrt(max(m2 - m1 * m1, 0.0));

    // Reproject the closest depth in the neighbourhood (keeps edges of moving silhouettes).
    vec2 uv = texcoord;
    ivec2 cq = clamp(px + closestOff, ivec2(0), ivec2(viewWidth, viewHeight) - 1);
    bool hand = hasFlag(int(unpack2x8u(texelFetch(colortex3, cq, 0).z).y), FLAG_HAND) && closestDepth < 0.56;
    vec2 prevUv = uv;
    if (!hand) {
        SceneDepth sd = resolveDepth((vec2(cq) + 0.5) / vec2(viewWidth, viewHeight), false, false);
        vec3 playerPos = viewToPlayer(sd.viewPos);
        if (sd.sky) playerPos = normalize(playerPos) * 1e5;
        vec3 prevPlayer = playerPos + cameraPosition - previousCameraPosition;
        if (sd.sky) prevPlayer = playerPos;
        vec3 prevView = mat3(gbufferPreviousModelView) * prevPlayer + gbufferPreviousModelView[3].xyz;
        mat4 prevProj = gbufferPreviousProjection;
        #ifdef DISTANT_HORIZONS
        if (sd.lod) prevProj = dhPreviousProjection;
        #endif
        #ifdef VOXY
        if (sd.lod) prevProj = vxProjPrev;
        #endif
        prevUv = viewToScreen(prevView, prevProj).xy + (uv - (vec2(cq) + 0.5) / vec2(viewWidth, viewHeight));
    }

    bool offscreen = any(lessThan(prevUv, vec2(0.0))) || any(greaterThan(prevUv, vec2(1.0)));
    vec3 hist = offscreen ? cur : sampleHistoryCatmullRom(prevUv);
    // History never written (first frames after loading) is exactly zero: start from the current
    // frame instead of fading in from black.
    if (maxOf(hist) <= 0.0) hist = cur;
    vec3 histY = toYCoCg(tonemapTAA(hist));
    vec3 lo = m1 - sigma * 1.25, hi = m1 + sigma * 1.25;
    // Clip towards the neighbourhood mean (preserves hue better than clamping).
    vec3 center = 0.5 * (lo + hi), ext = 0.5 * (hi - lo) + 1e-5;
    vec3 off = histY - center;
    vec3 ts = abs(off / ext);
    float mt = maxOf(ts);
    if (mt > 1.0) histY = center + off / mt;
    hist = untonemapTAA(fromYCoCg(histY));

    // Blend: ~1/10 per frame, faster on disocclusion or large motion.
    float motion = length((prevUv - uv) * vec2(viewWidth, viewHeight));
    float alpha = offscreen ? 1.0 : clamp(0.08 + motion * 0.02, 0.08, 0.5);
    vec3 a = tonemapTAA(cur), b = tonemapTAA(hist);
    vec3 res = untonemapTAA(mix(b, a, alpha));
    if (any(isnan(res)) || any(isinf(res))) res = cur;
    res = hdrSafe(res);      // a NaN in the history would persist
    outColor = vec4(res, 1.0);
    outHistory = vec4(res, 1.0);
}

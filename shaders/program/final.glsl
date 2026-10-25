// Final image: bloom, exposure, grading, tone curve, sharpening, dither, debug views.
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/buffers.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/post/tonemap.glsl"
#include "/lib/post/grade.glsl"
#include "/lib/post/bloom_layout.glsl"
#if DEBUG_VIEW != 0
    #include "/lib/debug/debug.glsl"
    uniform sampler2D colortex1;
    uniform sampler2D colortex2;
    uniform sampler2D colortex3;
    uniform sampler2D colortex4;
    uniform sampler2D colortex11;
    #if DEBUG_VIEW == DBG_CLOUD_SCATTER || DEBUG_VIEW == DBG_CLOUD_TRANS
        uniform sampler2D colortex9;
    #endif
    uniform sampler2D depthtex0;
#endif

uniform sampler2D colortex0;
in vec2 texCoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

float currentExposure() {
    float e = frameStateValid() ? fsExposure.x : 1.0;
    if (isnan(e) || isinf(e) || e <= 0.0) e = 1.0;
    return e * exp2(EXPOSURE_COMPENSATION);
}

vec3 bloomAt(vec2 uv) {
    #ifdef BLOOM
        float r = BLOOM_RADIUS;
        float norm = 1.0 + r + r * r + r * r * r + r * r * r * r;
        return texture(bloomAtlasTex, bloomLevelUv(1, uv)).rgb / norm;
    #else
        return vec3(0.0);
    #endif
}

vec3 displayFromHdr(vec3 hdr, float exposure, vec2 uv) {
    float absLum = luminance(hdr);
    vec3 c = gradeSceneReferred(hdr * exposure, absLum);
    return gradeDisplayReferred(tonemapSelected(c, CP_TONEMAP), uv);
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 hdr = texelFetch(colortex0, px, 0).rgb;
    #ifdef BLOOM
        // Energy-conserving: bloom redistributes light instead of adding it.
        hdr = mix(hdr, bloomAt(texCoord), BLOOM_STRENGTH);
    #endif
    float exposure = currentExposure();
    vec3 display = displayFromHdr(hdr, exposure, texCoord);

    #if SHARPENING > 0
    {
        // Contrast-adaptive sharpening on the display signal: strength falls where the local
        // range is already high, which avoids halos on hard edges.
        ivec2 maxPx = ivec2(viewWidth, viewHeight) - 1;
        vec3 n = tonemapFilmic(texelFetch(colortex0, clamp(px + ivec2(0, 1), ivec2(0), maxPx), 0).rgb * exposure);
        vec3 s = tonemapFilmic(texelFetch(colortex0, clamp(px - ivec2(0, 1), ivec2(0), maxPx), 0).rgb * exposure);
        vec3 e = tonemapFilmic(texelFetch(colortex0, clamp(px + ivec2(1, 0), ivec2(0), maxPx), 0).rgb * exposure);
        vec3 w = tonemapFilmic(texelFetch(colortex0, clamp(px - ivec2(1, 0), ivec2(0), maxPx), 0).rgb * exposure);
        vec3 c = tonemapFilmic(hdr * exposure);
        vec3 mn = min(c, min(min(n, s), min(e, w))), mx = max(c, max(max(n, s), max(e, w)));
        vec3 adapt = saturate(1.0 - (mx - mn) * 2.5);
        vec3 detail = c - 0.25 * (n + s + e + w);
        display = saturate(display + detail * adapt * float(SHARPENING) * 0.25);
    }
    #endif

    vec3 srgb = linearToSrgb(display);

    #if DEBUG_VIEW != 0
    {
        vec3 dbg;
        int view = DEBUG_VIEW;
        if (debugGBufferView(view, texelFetch(colortex1, px, 0), texelFetch(colortex2, px, 0),
                             texelFetch(colortex3, px, 0), texelFetch(colortex4, px, 0),
                             texelFetch(depthtex0, px, 0).r, dbg)) {
            srgb = dbg;
        } else if (view == DBG_DIRECT || view == DBG_INDIRECT || view == DBG_GI) {
            srgb = linearToSrgb(tonemapFilmic(texelFetch(colortex11, px, 0).rgb * exposure));
        } else if (view == DBG_SHADOW || view == DBG_TAA_REJECT || view == DBG_MOTION || view == DBG_REFLECTIONS
                   || view == DBG_WATER_HEIGHT || view == DBG_WATER_VELOCITY || view == DBG_AO || view == DBG_LIGHT_VOLUME) {
            srgb = texelFetch(colortex11, px, 0).rgb;
        #if DEBUG_VIEW == DBG_CLOUD_SCATTER || DEBUG_VIEW == DBG_CLOUD_TRANS
        } else if (view == DBG_CLOUD_SCATTER) {
            srgb = linearToSrgb(tonemapFilmic(texelFetch(colortex9, px, 0).rgb * exposure));
        } else if (view == DBG_CLOUD_TRANS) {
            srgb = vec3(texelFetch(colortex9, px, 0).a);
        #endif
        } else if (view == DBG_LOD) {
            int flags = decodeByte(texelFetch(colortex4, px, 0).a);
            bool lod = (flags & GB_FLAG_LOD) != 0;
            srgb = mix(linearToSrgb(display) * 0.4, lod ? vec3(1.0, 0.45, 0.1) : vec3(0.1, 0.5, 1.0), 0.55);
        } else if (view == DBG_LIGHTMAP) {
            // Lightmap as lit by deferred: block light red, sky light blue (after LOD fixes).
            vec2 lm = texelFetch(colortex4, px, 0).rg;
            srgb = vec3(lm.x, 0.0, lm.y);
        } else if (view == DBG_EXPOSURE) {
            // Scene luminance relative to the metered average, in stops: blue -4 .. red +4.
            float stops = log2(max(luminance(hdr), 1e-7) / max(fsExposure.y, 1e-7));
            srgb = debugHeat(stops / 8.0 + 0.5);
        }
    }
    #endif

    // Ordered dither before 8-bit quantisation removes sky banding.
    srgb += (interleavedGradient(gl_FragCoord.xy) - 0.5) / 255.0;
    outColor = vec4(saturate(srgb), 1.0);
}
#endif

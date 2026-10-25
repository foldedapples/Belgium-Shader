// composite6.csh - automatic exposure. One 16x16 work group meters a centre-weighted 64x64
// grid of log luminance from the HDR scene, reduces it in shared memory and adapts the
// exposure stored in FrameState with separate brighten/darken rates.
#include "/lib/core/common.glsl"
#define FRAME_STATE_WRITER
#include "/lib/core/frame_state.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

shared float sharedLog[256];
shared float sharedWeight[256];

void main() {
    uint id = gl_LocalInvocationIndex;
    vec2 cell = vec2(gl_LocalInvocationID.xy);
    float sumLog = 0.0, sumW = 0.0;
    for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) {
        // Per-frame jittered sample positions: over a few frames the meter covers the whole
        // image instead of a fixed sparse grid that small bright objects can slip between.
        vec2 jitter = r2Sequence(frameCounter + int(id) * 7 + j * 4 + i);
        vec2 uv = (cell * 4.0 + vec2(i, j) + jitter) / 64.0;
        float lum = luminance(textureLod(colortex0, uv, 0.0).rgb);
        // Centre-weighted metering (Gaussian falloff toward the frame edge).
        vec2 c = uv - 0.5;
        float w = exp(-dot(c, c) * 5.0);
        if (isnan(lum) || isinf(lum)) { lum = 0.0; w = 0.0; }
        sumLog += w * log2(max(lum, 1e-7));
        sumW += w;
    }
    sharedLog[id] = sumLog;
    sharedWeight[id] = sumW;
    barrier();
    for (uint stride = 128u; stride > 0u; stride >>= 1u) {
        if (id < stride) {
            sharedLog[id] += sharedLog[id + stride];
            sharedWeight[id] += sharedWeight[id + stride];
        }
        barrier();
    }
    if (id != 0u) return;

    // Autofocus for depth of field: median-free centre-weighted depth of five probes,
    // smoothed so focus pulls are gradual (about half a second).
    {
        float sumD = 0.0;
        const vec2 probes[5] = vec2[5](vec2(0.5), vec2(0.47, 0.5), vec2(0.53, 0.5), vec2(0.5, 0.47), vec2(0.5, 0.53));
        for (int i = 0; i < 5; i++) {
            float d = textureLod(depthtex0, probes[i], 0.0).r;
            sumD += d >= 1.0 ? far : linearizeDepth(d, near, far);
        }
        float measured = sumD / 5.0;
        float k = 1.0 - exp(-clamp(frameTime, 0.0, 0.25) * 4.0);
        bool fresh = fsHeader.x != FS_VERSION || fsFocus.x <= 0.0;
        fsFocus = vec4(fresh ? measured : mix(fsFocus.x, measured, k), measured, 0.0, 0.0);
    }

    float avgLog = sharedLog[0] / max(sharedWeight[0], EPSILON);
    float avgLum = exp2(avgLog);
    // Dark scenes are exposed below middle grey so night still reads as night.
    float key = 0.18 * mix(0.38, 1.0, smoothstep(-12.0, -3.5, avgLog));
    #ifdef AUTO_EXPOSURE
        float targetEv = clamp(log2(key / max(avgLum, 1e-7)), EXPOSURE_MIN_EV, EXPOSURE_MAX_EV);
    #else
        float targetEv = EXPOSURE_FIXED_EV;
    #endif

    bool valid = fsHeader.x == FS_VERSION && fsExposure.x > 0.0 && !isnan(fsExposure.x) && !isinf(fsExposure.x);
    float currentEv = valid ? log2(fsExposure.x) : targetEv;
    // The eye darkens to bright light faster than it adapts to darkness.
    float rate = (targetEv > currentEv ? 0.9 : 2.2) * EXPOSURE_SPEED;
    float dt = clamp(frameTime, 0.0, 0.25);
    float ev = currentEv + (targetEv - currentEv) * (1.0 - exp(-rate * dt));
    if (!valid || fsExposure.w < 2.0) ev = targetEv;
    fsExposure = vec4(exp2(ev), avgLum, exp2(targetEv), min(fsExposure.w + 1.0, 1e6));
}
#endif

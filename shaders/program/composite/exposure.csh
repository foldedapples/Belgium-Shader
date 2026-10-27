// composite5 compute: automatic exposure. Averages log luminance of the TAA output over a
// centre-weighted 32x18 grid read from a coarse mip, chooses a target with a scene-dependent key
// (bright scenes get a lower key, after Krawczyk et al. 2005), clamps to a sane EV range and adapts
// exponentially (faster when getting brighter, as the eye does). Stored in state.exposure.
//
// Sky samples count at 30 %: metering a black sky (space in the End, a starry night) otherwise
// pushes exposure up by many stops and blows out the terrain the player is looking at (observed
// in game with an earlier pack on this Iris build). The End and the Nether have constant light
// sources, so their exposure is additionally kept within a band around a reference derived from
// that light.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/state.glsl"
#include "/lib/common/transform.glsl"
#include "/lib/common/depth.glsl"

layout(local_size_x = 32, local_size_y = 18) in;
const ivec3 workGroups = ivec3(1, 1, 1);

uniform sampler2D colortex0;
shared float sLog[576];
shared float sW[576];

void main() {
    uint tid = gl_LocalInvocationIndex;
    vec2 uv = (vec2(gl_LocalInvocationID.xy) + 0.5) / vec2(32.0, 18.0);
    // A mip no finer than the 32 x 18 sample grid, so every sample averages its whole cell. With a
    // finer mip the samples covered only part of the screen and small bright things (a torch, a
    // lantern) moving between sample points as the view turned made the exposure pulse.
    float lod = max(ceil(log2(max(viewWidth / 32.0, viewHeight / 18.0))), 0.0);
    vec3 c = textureLod(colortex0, uv, lod).rgb;
    float l = luminance(c);
    if (isnan(l) || isinf(l)) l = 0.0;
    vec2 d = (uv - 0.5) * vec2(1.6, 2.2);
    float w = exp(-dot(d, d) * 2.0) + 0.05;
    // Sky pixels: 30 % weight in the Overworld; none in the End and the Nether, whose sky is black
    // space or void. The log average is a geometric mean, so even a few black pixels pulled it down
    // by stops (log2 of the old 1e-6 floor is -20) and the terrain was overexposed to white.
    #if defined WORLD_END || defined WORLD_NETHER
    if (resolveDepth(uv, false, false).sky) w *= 0.002;
    #else
    if (resolveDepth(uv, false, false).sky) w *= 0.3;
    #endif
    sLog[tid] = log2(max(l, 1e-4)) * w;
    sW[tid] = w;
    barrier();
    // Fold 576 values into 512, then a power-of-two tree reduction.
    if (tid < 64u) { sLog[tid] += sLog[tid + 512u]; sW[tid] += sW[tid + 512u]; }
    barrier();
    for (uint stride = 256u; stride > 0u; stride >>= 1u) {
        if (tid < stride) { sLog[tid] += sLog[tid + stride]; sW[tid] += sW[tid + stride]; }
        barrier();
    }
    if (tid == 0u) {
        float avgLog = sLog[0] / max(sW[0], 1e-6);
        float avgL = exp2(avgLog);
        // Key value: ~0.18 for daylight scenes, falling to ~0.05 in the dark so night stays night
        // (a fixed key would expose moonlight like daylight). Range: noon to moonless night.
        float key = mix(0.05, 0.18, smoothstep(-4.0, -0.3, log2(avgL) * 0.30103));
        float target = key / max(avgL, 1e-6);
        target = clamp(target, 0.004, 512.0);
        #ifdef WORLD_END
        // Reference: End stone (albedo ~0.35) lit by the disk (lib/space/end_sky.glsl).
        float refEnd = 0.18 / (0.35 * 3.2 * END_LIGHT_STRENGTH * INV_PI + 0.01);
        // The End's light is constant, so only a narrow band of adaptation around that reference
        // (a portal or end rods in view must not drag the disk-lit island into darkness).
        target = clamp(target, refEnd * 0.6, refEnd * 1.8);
        #elif defined WORLD_NETHER
        // Wide band: a lava sea fills the view with emitters far brighter than the rock around it.
        target = clamp(target, 0.12, 24.0);
        #endif
        target *= exp2(EXPOSURE_BIAS);
        float prev = state.exposure;
        // Adapt only from a value this pipeline wrote on the frame before. On the first frame after
        // loading or reloading the pack, or after another pipeline (dimension) ran, the stored value
        // is uninitialised or stale; adapting from it took seconds and showed as a fade in from
        // black. Start at the target instead (normal eye adaptation is unchanged).
        bool continuous = state.exposureInfo.y == 1 && state.exposureInfo.x == frameCounter - 1;
        if (!continuous || !(prev > 0.0) || isinf(prev) || isnan(prev)) prev = target;
        state.exposureInfo = ivec4(frameCounter, 1, 0, 0);
        float dt = clamp(frameTime, 0.0, 0.2);
        float speed = (target > prev ? 1.2 : 2.5) * ADAPTATION_SPEED;
        float ex = exp2(mix(log2(prev), log2(target), 1.0 - exp(-dt * speed)));
        #ifndef AUTO_EXPOSURE
        // Fixed exposure that still follows the time of day (sun elevation from sunAngle).
        float sunH = sin(sunAngle * TAU);
        ex = mix(3.0, 0.07, smoothstep(-0.15, 0.25, sunH)) * exp2(EXPOSURE_BIAS);
        #endif
        state.exposure = ex;
        state.avgLogLuminance = avgLog;
    }
}

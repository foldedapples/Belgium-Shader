// prepare1: interactive water. A height field h around the player obeys the damped 2D wave
// equation, integrated with the explicit leapfrog scheme
//     h' = h + (h - h_prev)(1 - damping) + k * laplacian(h),   k = (c dt / dx)^2
// at a fixed step of 1/60 s. Stability of the 5-point scheme in 2D requires k <= 1/2. The ripple
// speed is c = SIM_DX * sqrt(k) / dt: k = 0.02 gives ~2.1 blocks/s, about the phase speed of
// 1-3 m water waves. (k = 0.32 gave 8.5 blocks/s; in game, ripples raced away from the player.)
//
// Entry points (set by the wrapper):
//   SIM_BOOKKEEPING  prepare1.csh     time accumulator, steps this frame, domain centre, water plane
//   SIM_STEP_N       prepare1_a..d    step N (0..3), a no-op when N >= steps this frame
//
// Inputs (what Iris exposes, see docs/ARCHITECTURE.md "Interactive water"): the camera player's
// position and motion, swimming state, feet-in-water, the ridden vehicle's position and whether it
// is in water. Other entities are not visible to shaders, so only the player and their boat make
// waves. Shorelines come from the voxelised terrain: cells whose column is not water at the
// simulated plane are rigid boundaries (h = 0, reflecting); the domain edge is a sponge layer.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/state.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/water/sim_common.glsl"
#include "/lib/lighting/light_volume.glsl"

const float SIM_DT = 1.0 / 60.0;
const float SIM_K = 0.02;
// Per-step amplitude loss; ~0.004 lets a ripple live ~4 s and travel ~8 blocks.
const float SIM_DAMPING = 0.004;

#ifdef SIM_BOOKKEEPING
layout(local_size_x = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

void main() {
    #ifndef WATER_SIM
    state.simCenter.w = 0.0;
    return;
    #endif
    float dt = clamp(frameTime, 0.0, 0.1);
    float acc = state.simAccumulator + dt;
    int steps = min(int(acc / SIM_DT), 4);
    acc -= float(steps) * SIM_DT;
    acc = min(acc, SIM_DT);
    state.simAccumulator = acc;
    // Base parity: the image holding the newest state before this frame's steps.
    int base = state.simParity;
    state.simInfo = ivec4(base, steps, 0, 0);
    state.simParity = (base + steps) & 1;

    // Domain centre follows the camera; the field is world-anchored (toroidal), so no shifting.
    state.simPrevCenter = vec4(state.simCenter.xz, 0.0, state.simCenter.w);
    vec3 feet = eyePosition - vec3(0.0, inSwimmingAnimation ? 0.4 : 1.62, 0.0);
    float plane = state.simCenter.y;
    bool inWater = feetInWater || isEyeInWater == 1 || (isRiding && vehicleInWater);
    if (inWater) {
        // Water surface: top of the block the feet (or the boat) are in (source water is 14/16 high).
        float y = isRiding && vehicleInWater ? (cameraPosition + relativeVehiclePosition).y : feet.y + 0.3;
        float candidate = floor(y) + 0.889;
        if (state.simCenter.w < 0.5 || abs(candidate - plane) > 0.6) plane = candidate;
    }
    state.simCenter = vec4(cameraPosition.x, plane, cameraPosition.z, (state.simCenter.w > 0.5 || inWater) ? 1.0 : 0.0);

    // Previous body positions for this frame's disturbances, rolled here (one invocation, before
    // the steps) and only on frames that step, so motion during frames without a step still
    // counts. The step pass used to rewrite playerPrev / vehiclePrev from invocation (0,0) while
    // every other invocation of the same dispatch was reading them: workgroups that ran after it
    // saw no motion, leaving the wake missing in 4x4-block tiles.
    if (steps > 0) {
        state.playerPrev = state.playerLast;
        state.vehiclePrev = state.vehicleLast;
        state.playerLast = vec4(feet, (feetInWater || isEyeInWater == 1) ? 1.0 : 0.0);
        state.vehicleLast = vec4(cameraPosition + relativeVehiclePosition, (isRiding && vehicleInWater) ? 1.0 : 0.0);
    }
}
#endif

#if defined SIM_STEP_0 || defined SIM_STEP_1 || defined SIM_STEP_2 || defined SIM_STEP_3
#if defined SIM_STEP_0
const int STEP = 0;
#elif defined SIM_STEP_1
const int STEP = 1;
#elif defined SIM_STEP_2
const int STEP = 2;
#else
const int STEP = 3;
#endif

layout(local_size_x = 16, local_size_y = 16) in;
// Iris reads workGroups as literal text, so each grid size gets its own line (SIM_N / 16).
#if WATER_SIM_RES == 0
const ivec3 workGroups = ivec3(8, 8, 1);
#elif WATER_SIM_RES == 1
const ivec3 workGroups = ivec3(16, 16, 1);
#else
const ivec3 workGroups = ivec3(32, 32, 1);
#endif
layout(rg16f) uniform image2D waterSimA;
layout(rg16f) uniform image2D waterSimB;
layout(r16ui) uniform readonly uimage3D voxelImg;

// World cell represented by texel t for a domain centred at c.
ivec2 cellOf(ivec2 t, vec2 c) {
    ivec2 lo = simCell(c) - SIM_N / 2;
    return lo + ((t - lo) & (SIM_N - 1));   // SIM_N is a power of two; % of negatives is undefined in GLSL
}

bool isWaterColumn(ivec2 cell, float planeY) {
    #ifdef COLORED_LIGHTING
    if (state.lightVolumeOrigin.w < 0.5) return true;
    ivec3 block = ivec3(floor(vec2(cell) * SIM_DX).x, int(floor(planeY - 0.2)), floor(vec2(cell) * SIM_DX).y);
    if (!insideVolume(block, ivec3(state.lightVolumeOrigin.xyz))) return true;
    uint v = imageLoad(voxelImg, voxelIndex(block)).r;
    // Empty voxels inside the volume are air above or around the water: not water.
    return (v & 0x8000u) != 0u && int(v & 255u) == MAT_WATER;
    #else
    return true;
    #endif
}

// Disturbances are mass-conserving: a body is a displacement shape B(x - p); moving it from the
// previous position to the current one adds B(x - p_now) - B(x - p_prev) (bow wave in front, trough
// behind, zero net volume). Splashes use a zero-volume "Mexican hat" profile. Injecting volume
// instead would make a steadily swimming player dig an ever deeper hole
// (tools/tests/test_water_sim.py, case 4).
float gauss(vec2 d, float s2) { return exp(-dot(d, d) / s2); }

float splashProfile(vec2 d) {
    // G(0.6) - 0.25 G(1.2): the integrals cancel (area of a Gaussian is proportional to sigma^2).
    return gauss(d, 0.6) - 0.25 * gauss(d, 2.4);
}

float disturbance(vec2 xz) {
    float s = 0.0;
    float swim = inSwimmingAnimation ? 1.0 : 0.0;
    vec3 feet = eyePosition - vec3(0.0, mix(1.62, 0.4, swim), 0.0);
    float plane = state.simCenter.y;
    bool atSurface = abs(feet.y + mix(0.6, 0.4, swim) - plane) < 1.2;
    bool inWater = feetInWater || isEyeInWater == 1;
    if (inWater && atSurface && state.playerPrev.w > 0.5) {
        float body = mix(0.25, 0.5, swim);
        vec2 prev = state.playerPrev.xz;
        vec2 moved = feet.xz - prev;
        // Ignore teleports and respawns.
        if (dot(moved, moved) < 4.0) s -= (gauss(xz - feet.xz, body) - gauss(xz - prev, body)) * 0.12;
        // Treading water: a faint zero-volume pulse keeps idle swimmers alive.
        s -= splashProfile(xz - feet.xz) * 0.0015 * sin(frameTimeCounter * 3.0);
    }
    // Entering the water: a splash proportional to the vertical speed.
    if (inWater && state.playerPrev.w < 0.5) {
        float vy = max(-(cameraPosition.y - previousCameraPosition.y) / max(frameTime, 1e-3), 0.0);
        s -= splashProfile(xz - feet.xz) * min(vy, 20.0) * 0.012;
    }
    if (isRiding && vehicleInWater && vehicleId == 2 && state.vehiclePrev.w > 0.5) {
        // Boat hull: three displacement points along the heading, moved like the body above.
        vec3 vp = cameraPosition + relativeVehiclePosition;
        vec2 fwd = normalize(vehicleLookVector.xz + vec2(1e-4));
        vec2 delta = vp.xz - state.vehiclePrev.xz;
        if (dot(delta, delta) < 9.0) {
            for (int i = -1; i <= 1; i++) {
                vec2 p = vp.xz + fwd * float(i) * 0.6;
                s -= (gauss(xz - p, 0.55) - gauss(xz - p + delta, 0.55)) * 0.2;
            }
        }
    }
    return s * WATER_SIM_STRENGTH;
}

void main() {
    #ifndef WATER_SIM
    return;
    #endif
    if (STEP >= state.simInfo.y) return;
    ivec2 t = ivec2(gl_GlobalInvocationID.xy);
    int parity = (state.simInfo.x + STEP) & 1;
    vec2 center = state.simCenter.xz;
    ivec2 cell = cellOf(t, center);
    // Cells that wrapped in from the far side since last frame start flat.
    bool fresh = state.simPrevCenter.w < 0.5 || any(notEqual(cell, cellOf(t, state.simPrevCenter.xz)));

    vec2 cur = parity == 0 ? imageLoad(waterSimA, t).rg : imageLoad(waterSimB, t).rg;
    float h = fresh && STEP == 0 ? 0.0 : cur.r;
    float hp = fresh && STEP == 0 ? 0.0 : cur.g;

    float next = 0.0;
    float prevOut = h;
    vec2 xz = (vec2(cell) + 0.5) * SIM_DX;
    if (state.simCenter.w > 0.5 && isWaterColumn(cell, state.simCenter.y)) {
        float lap = 0.0;
        const ivec2 o[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
        for (int i = 0; i < 4; i++) {
            ivec2 nt = simTexel(cell + o[i]);
            float hn = parity == 0 ? imageLoad(waterSimA, nt).r : imageLoad(waterSimB, nt).r;
            // Shore cells act as walls: mirror the centre value (Neumann boundary, reflects waves).
            if (!isWaterColumn(cell + o[i], state.simCenter.y)) hn = h;
            lap += hn;
        }
        lap -= 4.0 * h;
        next = h + (h - hp) * (1.0 - SIM_DAMPING) + SIM_K * lap;
        // Sponge layer at the edge of the domain absorbs outgoing waves.
        float edge = simEdgeFade(xz, center);
        next *= mix(0.92, 1.0, edge);
        // Disturbances displace the surface: added to both time levels, so they move water without
        // adding vertical velocity. Adding them to the new level only acts as a force; with
        // realistic (slow) ripples a swimmer then piles energy up faster than it radiates
        // (tools/tests/test_water_sim.py, case 4).
        float D = STEP == 0 ? disturbance(xz) : 0.0;
        next = clamp(next + D, -0.6, 0.6);
        prevOut = h + D;
    }
    vec4 outv = vec4(next, prevOut, 0.0, 0.0);
    if (parity == 0) imageStore(waterSimB, t, outv);
    else imageStore(waterSimA, t, outv);
}
#endif

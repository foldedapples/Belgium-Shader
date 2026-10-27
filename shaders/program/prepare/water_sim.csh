// prepare1: interactive water. A height field h around the player obeys the damped 2D wave
// equation, integrated with the explicit leapfrog scheme
//     h' = h + (h - h_prev)(1 - damping) + k * laplacian(h),   k = (c dt / dx)^2
// at a fixed step of 1/60 s. Stability of the 5-point scheme in 2D requires k <= 1/2. The ripple
// speed is c = SIM_DX * sqrt(k) / dt: k = 0.02 gives ~2.1 blocks/s, about the phase speed of
// 1-3 m water waves. (k = 0.32 gave 8.5 blocks/s; in game, ripples raced away from the player.)
//
// Entry points (set by the wrapper):
//   SIM_BOOKKEEPING  prepare1.csh     time accumulator, steps this frame, domain centre, water plane,
//                                     body history (one invocation, runs before the steps)
//   SIM_STEP_N       prepare1_a..d    step N (0..3), a no-op when N >= steps this frame
//
// Inputs (Iris uniforms; see lib/water/sim_common.glsl for the coordinate frames): the camera
// entity's eye relative to the camera (relativeEyePosition = camera - eye), swimming state,
// feet-in-water, the ridden vehicle's offset (relativeVehiclePosition = camera - vehicle), its
// heading and whether it is in water. Other entities are not visible to shaders, so only the
// player and their boat make waves. Shorelines come from the voxelised terrain: cells whose
// column is not water at the simulated plane are rigid boundaries (reflecting); the domain edge
// is a sponge layer.

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
const float SOURCE_WATER_TOP = 0.889;   // top of a source water block within its block

// Feet of the camera entity (normally the player) relative to the camera, in blocks.
vec3 feetRelative() {
    return -relativeEyePosition - vec3(0.0, inSwimmingAnimation ? 0.4 : 1.62, 0.0);
}
vec3 vehicleRelative() { return -relativeVehiclePosition; }

// Offset of the camera's cell corner from the camera, so that (corner offset + relative position)
// is a position relative to simCameraCell() in blocks.
vec2 cellCornerOffset() {
    vec2 f = cameraPositionFract.xz * float(SIM_CELLS_PER_BLOCK);
    return (f - floor(f)) * SIM_DX;
}

#ifdef SIM_BOOKKEEPING
layout(local_size_x = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

#ifdef COLORED_LIGHTING
uniform usampler3D voxelSampler;
#endif

// Height of the water surface in the column at a camera-relative point: the top of the highest
// water block within a few blocks of `rel.y`, from the voxelised terrain. Returns -1e4 when the
// column has no water there, or when the voxels are unavailable.
float voxelWaterSurface(vec3 rel) {
    #ifdef COLORED_LIGHTING
    if (state.lightVolumeOrigin.w < 0.5) return -1e4;
    ivec3 b = cameraPositionInt + ivec3(floor(cameraPositionFract + rel));
    ivec3 origin = ivec3(state.lightVolumeOrigin.xyz);
    for (int dy = 3; dy >= -3; dy--) {
        ivec3 q = b + ivec3(0, dy, 0);
        if (!insideVolume(q, origin)) continue;
        uint v = texelFetch(voxelSampler, voxelIndex(q), 0).r;
        if ((v & 0x8000u) != 0u && int(v & 255u) == MAT_WATER) return float(q.y) + SOURCE_WATER_TOP;
    }
    #endif
    return -1e4;
}

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

    ivec2 C = simCameraCell();
    bool riding = isRiding && vehicleInWater;
    bool inWater = feetInWater || isEyeInWater == 1 || riding;

    // Water plane: the surface of the water the body is in. The voxelised terrain gives it
    // exactly (also in shallow water and for boats); without it, the eye height is used (it sits
    // just above the surface when floating, just below when swimming). The old estimate,
    // floor(feet + 0.3), put the plane one block too low for a floating player, which in shallow
    // water put it in the river bed so every cell was "shore" and nothing moved.
    float plane = state.simCenter.y;
    if (inWater) {
        vec3 ref = riding ? vehicleRelative() : -relativeEyePosition - vec3(0.0, 0.5, 0.0);
        float y = voxelWaterSurface(ref);
        if (y < -1e3) {
            float absY = cameraPosition.y + ref.y;    // y is never shifted by Iris
            y = floor(absY + (riding ? 0.2 : 0.0)) + SOURCE_WATER_TOP;
        }
        if (state.simCenter.w < 0.5 || abs(y - plane) > 0.3) plane = y;
    }
    state.simCenter = vec4(0.0, plane, 0.0, (state.simCenter.w > 0.5 || inWater) ? 1.0 : 0.0);

    // Domain centre now; the centre and body history are rolled only on frames that step, so the
    // step pass always compares against the last frame that actually stepped (cells that wrapped
    // in during frames without a step are still cleared, and motion during them still counts).
    state.simCells.xy = C;
    if (steps > 0) {
        state.simCells.zw = state.simCellsLast.xy;
        state.simPrevCenter.w = float(state.simCellsLast.z);
        state.playerPrev = state.playerLast;
        state.vehiclePrev = state.vehicleLast;
        vec2 corner = cellCornerOffset();
        vec3 feet = feetRelative();
        vec3 veh = vehicleRelative();
        state.playerLast = vec4(corner.x + feet.x, cameraPosition.y + feet.y, corner.y + feet.z,
                                (feetInWater || isEyeInWater == 1) ? 1.0 : 0.0);
        state.vehicleLast = vec4(corner.x + veh.x, cameraPosition.y + veh.y, corner.y + veh.z, riding ? 1.0 : 0.0);
        state.simCellsLast = ivec4(C, 1, 0);
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

// World cell represented by texel t for a domain centred on cell c.
ivec2 cellOf(ivec2 t, ivec2 c) {
    ivec2 lo = c - SIM_N / 2;
    return lo + ((t - lo) & (SIM_N - 1));   // SIM_N is a power of two; % of negatives is undefined in GLSL
}

bool isWaterColumn(ivec2 cell, float planeY) {
    #ifdef COLORED_LIGHTING
    if (state.lightVolumeOrigin.w < 0.5) return true;
    // Arithmetic shift = floor division by 4 for negative cells too.
    ivec3 block = ivec3(cell.x >> 2, int(floor(planeY - 0.2)), cell.y >> 2);
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
// instead would make a steadily swimming player dig an ever deeper hole.
// All positions are in blocks relative to the corner of the current domain-centre cell.
float gauss(vec2 d, float s2) { return exp(-dot(d, d) / s2); }

float splashProfile(vec2 d) {
    // G(0.6) - 0.25 G(1.2): the integrals cancel (area of a Gaussian is proportional to sigma^2).
    return gauss(d, 0.6) - 0.25 * gauss(d, 2.4);
}

float disturbance(vec2 xz) {
    float s = 0.0;
    float swim = inSwimmingAnimation ? 1.0 : 0.0;
    vec2 corner = cellCornerOffset();
    vec3 feetRel = feetRelative();
    vec2 feet = corner + feetRel.xz;
    float feetY = cameraPosition.y + feetRel.y;
    // Previous positions were stored relative to the centre cell of their frame.
    vec2 shift = vec2(state.simCells.zw - state.simCells.xy) * SIM_DX;
    float plane = state.simCenter.y;
    bool atSurface = abs(feetY + mix(0.6, 0.4, swim) - plane) < 1.2;
    bool inWater = feetInWater || isEyeInWater == 1;
    if (inWater && atSurface && state.playerPrev.w > 0.5) {
        float body = mix(0.25, 0.5, swim);
        vec2 prev = state.playerPrev.xz + shift;
        vec2 moved = feet - prev;
        // Ignore teleports and respawns.
        if (dot(moved, moved) < 4.0) s -= (gauss(xz - feet, body) - gauss(xz - prev, body)) * 0.12;
        // Treading water: a faint zero-volume pulse keeps idle swimmers alive.
        s -= splashProfile(xz - feet) * 0.0015 * sin(frameTimeCounter * 3.0);
    }
    // Entering the water: a splash proportional to the vertical speed.
    if (inWater && state.playerPrev.w < 0.5 && state.simPrevCenter.w > 0.5) {
        float vy = max(-(cameraPosition.y - previousCameraPosition.y) / max(frameTime, 1e-3), 0.0);
        s -= splashProfile(xz - feet) * min(vy, 20.0) * 0.012;
    }
    if (isRiding && vehicleInWater && vehicleId == 2 && state.vehiclePrev.w > 0.5) {
        // Boat hull: three displacement points along the heading, moved like the body above.
        vec2 vp = corner + vehicleRelative().xz;
        vec2 fwd = normalize(vehicleLookVector.xz + vec2(1e-4));
        vec2 delta = vp - (state.vehiclePrev.xz + shift);
        if (dot(delta, delta) < 9.0) {
            for (int i = -1; i <= 1; i++) {
                vec2 p = vp + fwd * float(i) * 0.6;
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
    ivec2 C = state.simCells.xy;
    ivec2 cell = cellOf(t, C);
    // Cells that wrapped in from the far side since the last stepped frame start flat.
    bool fresh = state.simPrevCenter.w < 0.5 || any(notEqual(cell, cellOf(t, state.simCells.zw)));

    vec2 cur = parity == 0 ? imageLoad(waterSimA, t).rg : imageLoad(waterSimB, t).rg;
    float h = fresh && STEP == 0 ? 0.0 : cur.r;
    float hp = fresh && STEP == 0 ? 0.0 : cur.g;

    float next = 0.0;
    float prevOut = h;
    vec2 local = vec2(cell - C) + 0.5;            // cells from the centre cell's corner
    vec2 xz = local * SIM_DX;                      // blocks, same frame as disturbance()
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
        next *= mix(0.92, 1.0, simEdgeFade(local));
        // Disturbances displace the surface: added to both time levels, so they move water without
        // adding vertical velocity. Adding them to the new level only acts as a force; with
        // realistic (slow) ripples a swimmer then piles energy up faster than it radiates.
        float D = STEP == 0 ? disturbance(xz) : 0.0;
        next = clamp(next + D, -0.6, 0.6);
        prevOut = h + D;
    }
    vec4 outv = vec4(next, prevOut, 0.0, 0.0);
    if (parity == 0) imageStore(waterSimB, t, outv);
    else imageStore(waterSimA, t, outv);
}
#endif

// prepare1: interactive water. A height field h around the player obeys the damped 2D wave
// equation, integrated with the explicit leapfrog scheme
//     h' = h + v (1 - d - sponge) + k L(h) + nu L(v),   v = h - h_prev,  k = (c dt / dx)^2
// at a fixed step of 1/60 s (L = 5-point Laplacian). The ripple speed is c = WATER_SIM_SPEED
// blocks/s (default 2.5, the phase speed of ~4 m gravity waves; 8.5 blocks/s raced away from the
// player). Short waves travel a little slower than long ones on the grid (numerical dispersion),
// which is the same sense as real gravity waves: a splash spreads into a train of rings.
//
// Damping is frequency dependent, as in real water, where viscosity removes short ripples within
// seconds but barely touches metre-scale waves: nu L(v) damps a wave of wavenumber kappa at a rate
// ~ nu kappa^2, so grid-scale noise dies in a fraction of a second while the rings a body makes
// keep going; d is a small uniform loss (WATER_SIM_DAMPING). The old single uniform loss (0.004
// per step) killed long and short waves alike, so rings faded after a few blocks. Rings now
// weaken mostly by spreading over a growing circle (amplitude ~ 1 / sqrt(r)), and leave through
// the absorbing layer at the domain edge (lib/water/sim_common.glsl, simSponge) without
// reflecting. Von Neumann stability (|g| <= 1 for every Laplacian eigenvalue 0..8) needs
// 8k + 16nu <= 4 - 2(d + sponge); the largest option uses k = 0.071, far inside.
// tools/tests/test_water_propagation.py runs this scheme: speed, range, decay, edge reflection,
// stability and sleeping.
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
const float SIM_K = (WATER_SIM_SPEED * SIM_DT / SIM_DX) * (WATER_SIM_SPEED * SIM_DT / SIM_DX);
// Uniform per-step velocity loss d and viscous coefficient nu (Low / Normal / High damping).
// Normal: a hop's ring stays above a 0.02 slope out to ~19 blocks (old: ~13).
#if WATER_SIM_DAMPING == 0
const float SIM_DAMPING = 0.0004; const float SIM_VISCOSITY = 0.002;
#elif WATER_SIM_DAMPING == 1
const float SIM_DAMPING = 0.0009; const float SIM_VISCOSITY = 0.003;
#else
const float SIM_DAMPING = 0.0025; const float SIM_VISCOSITY = 0.004;
#endif
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
    // The field belongs to one dimension: entering another starts from a flat, inactive field
    // (no Overworld ripples showing up in the Nether or the End).
    #if defined WORLD_NETHER
    const int DIM = 2;
    #elif defined WORLD_END
    const int DIM = 3;
    #else
    const int DIM = 1;
    #endif
    if (state.simFlags.y != DIM) {
        state.simFlags = ivec4(0, DIM, 0, 0);
        state.simCenter.w = 0.0;
        state.simCellsLast.z = 0;
        state.playerLast.w = 0.0;
        state.vehicleLast.w = 0.0;
    }

    // Whether the player (not the camera) is in the water, and how fast their eye moves. The old
    // test used isEyeInWater and the camera height, which belong to the camera: in third person
    // the camera dips under the surface and jumps by metres when the view tilts or the
    // perspective changes, which read as a fast entry and gave false splashes
    // (tools/tests/test_water_sim_events.py). Now:
    //   feetInWater    the player entity touching water (Iris: isInShallowWater, which may turn
    //                  false once the player is fully under, hence the eye tests)
    //   eye submerged  first person: isEyeInWater (the camera is the eye); any view: the
    //                  voxelised water surface above the player's eye
    //   eye height     camera minus relativeEyePosition (the entity, whatever the camera does)
    float eyeY = cameraPosition.y - relativeEyePosition.y;    // y is never shifted by Iris
    float eyeSurface = voxelWaterSurface(-relativeEyePosition);
    bool eyeUnder = (firstPersonCamera && isEyeInWater == 1) || (eyeSurface > -1e3 && eyeY < eyeSurface);
    bool feetIn = feetInWater || eyeUnder;
    bool bodyInWater = feetIn || (isRiding && vehicleInWater);
    float dt = clamp(frameTime, 0.0, 0.1);
    float eyeDy = state.misc.y > 0.5 ? eyeY - state.misc.x : 0.0;
    state.misc.xy = vec2(eyeY, 1.0);

    // Water entry -> splash. A small state machine: dry time accumulates in real time (also while
    // the simulation sleeps); the body touching water after >= 0.15 s dry while moving down is one
    // entry, whatever the frame rate. The splash waits (simFlags.w) until a frame that steps
    // consumes it, so it is neither lost on frames without a step nor applied twice. Bobbing at the
    // surface or a shoreline edge never re-arms it (no dry time); riding never splashes.
    int dryMs = state.simFlags.z;
    int pending = state.simFlags.w;
    if (feetIn) {
        if (dryMs >= 150 && !isRiding) {
            float vy = abs(eyeDy) < 5.0 ? max(-eyeDy / max(frameTime, 1e-3), 0.0) : 0.0;   // not a teleport
            // Bounded amplitude in blocks: a hop (5 blocks/s) ~0.36, a high fall tends to 0.85.
            float amp = 0.85 * (1.0 - exp(-vy / 9.0)) * smoothstep(1.5, 4.0, vy) * WATER_SPLASH_STRENGTH;
            pending = max(pending, int(amp * 1000.0));
        }
        dryMs = 0;
    } else {
        dryMs = min(dryMs + int(dt * 1000.0 + 0.5), 1000000);
    }

    // Sleep while nothing moves: no body in the water, no splash waiting, and the last frame that
    // stepped left nothing moving (the steps set simFlags.x). The flag is cleared only on frames
    // that step - those are the only ones that can set it again. (Clearing it every frame put the
    // simulation to sleep on the first frame without a step - most frames above 60 FPS - so
    // ripples froze the moment the player left the water or the boat.)
    bool awake = bodyInWater || pending > 0 || state.simFlags.x != 0;
    float acc = awake ? state.simAccumulator + dt : 0.0;
    int steps = min(int(acc / SIM_DT), 4);      // at most 4 catch-up steps after a long frame
    acc -= float(steps) * SIM_DT;
    acc = min(acc, SIM_DT);
    state.simAccumulator = acc;
    state.simFlags = ivec4(steps > 0 ? 0 : state.simFlags.x, state.simFlags.y, dryMs, steps > 0 ? 0 : pending);
    // Base parity: the image holding the newest state before this frame's steps.
    int base = state.simParity;
    // z: the splash this frame's first step applies (x1000); w: the player is in the water.
    state.simInfo = ivec4(base, steps, steps > 0 ? pending : 0, feetIn ? 1 : 0);
    state.simParity = (base + steps) & 1;

    ivec2 C = simCameraCell();
    bool riding = isRiding && vehicleInWater;
    bool inWater = feetIn || riding;

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
                                feetIn ? 1.0 : 0.0);
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
#elif WATER_SIM_RES == 2
const ivec3 workGroups = ivec3(32, 32, 1);
#else
const ivec3 workGroups = ivec3(64, 64, 1);
#endif
// 32-bit: with long-lived waves, half-float rounding of h and h_prev broke volume conservation
// and could leave a drifting offset that kept the field awake after a boat ride.
layout(rg32f) uniform image2D waterSimA;
layout(rg32f) uniform image2D waterSimB;
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
    bool inWater = state.simInfo.w != 0;      // the player, as decided by the bookkeeping pass
    if (inWater && atSurface && state.playerPrev.w > 0.5) {
        float body = mix(0.25, 0.5, swim);
        vec2 prev = state.playerPrev.xz + shift;
        vec2 moved = feet - prev;
        // Ignore teleports and respawns.
        if (dot(moved, moved) < 4.0) s -= (gauss(xz - feet, body) - gauss(xz - prev, body)) * 0.12;
        // Treading water: a faint zero-volume pulse keeps idle swimmers alive.
        s -= splashProfile(xz - feet) * 0.0015 * sin(frameTimeCounter * 3.0);
    }
    // Entering the water: a crater (zero-volume profile) whose depth follows the entry speed,
    // decided by the bookkeeping pass (simInfo.z). The old in-step version used 0.012 x speed:
    // ring slopes of 0.02-0.13, no stronger than the ambient waves, so jumps showed nothing.
    if (state.simInfo.z > 0) s -= splashProfile(xz - feet) * (float(state.simInfo.z) / 1000.0);
    if (isRiding && vehicleInWater && vehicleId == 2 && state.vehiclePrev.w > 0.5) {
        // Boat hull: three displacement points along the heading, moved like the body above.
        vec2 vp = corner + vehicleRelative().xz;
        vec2 fwd = normalize(vehicleLookVector.xz + vec2(1e-4));
        vec2 delta = vp - (state.vehiclePrev.xz + shift);
        if (dot(delta, delta) < 9.0) {
            for (int i = -1; i <= 1; i++) {
                vec2 p = vp + fwd * float(i) * 0.6;
                s -= (gauss(xz - p, 0.55) - gauss(xz - p + delta, 0.55)) * (0.2 * WATER_BOAT_WAKE);
            }
        }
        // Faster than the ripples (2.5 blocks/s), the hull leaves a V-shaped wake behind it
        // (half-angle asin(c / v), ~18 degrees at 8 blocks/s). A boat at rest moves no water, so
        // stopping or leaving it ends the impulses while the waves already made run on.
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
        // Laplacians of the height and of the velocity v = h - h_prev (the viscous term).
        float v = h - hp;
        float lap = 0.0, lapV = 0.0;
        const ivec2 o[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
        for (int i = 0; i < 4; i++) {
            ivec2 nt = simTexel(cell + o[i]);
            vec2 n = parity == 0 ? imageLoad(waterSimA, nt).rg : imageLoad(waterSimB, nt).rg;
            // Shore cells act as walls: mirror the centre value (Neumann boundary, reflects waves).
            if (!isWaterColumn(cell + o[i], state.simCenter.y)) n = vec2(h, hp);
            lap += n.x;
            lapV += n.x - n.y;
        }
        lap -= 4.0 * h;
        lapV -= 4.0 * v;
        // The absorbing layer at the domain edge damps only the velocity (no reflections).
        next = h + v * (1.0 - SIM_DAMPING - simSponge(local)) + SIM_K * lap + SIM_VISCOSITY * lapV;
        // Disturbances displace the surface: added to both time levels, so they move water without
        // adding vertical velocity. Adding them to the new level only acts as a force; with
        // realistic (slow) ripples a swimmer then piles energy up faster than it radiates.
        float D = STEP == 0 ? disturbance(xz) : 0.0;
        next = clamp(next + D, -0.6, 0.6);
        prevOut = h + D;
        // Keep the simulation awake while any cell still moves (all writers store the same value).
        // Thresholds are far below anything visible (a 2e-3 bump is a slope of < 1e-3). With
        // long-lived waves, 2e-4 kept the field stepping for half a minute after the last visible
        // ripple, held by the faint displacement a boat or swimmer leaves behind (it drains
        // slowly through the absorbing layer).
        if (abs(next) > 2e-3 || abs(next - h) > 1e-4) state.simFlags.x = 1;
    }
    vec4 outv = vec4(next, prevOut, 0.0, 0.0);
    if (parity == 0) imageStore(waterSimB, t, outv);
    else imageStore(waterSimA, t, outv);
}
#endif

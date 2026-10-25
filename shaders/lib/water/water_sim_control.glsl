#ifndef WATER_SIM_CONTROL_GLSL
#define WATER_SIM_CONTROL_GLSL
// Per-frame control of the water simulation, executed by the single begin.csh thread.
// Requires WATER_SIM_WRITER to be defined before water_sim_common.glsl is first included.
#include "/lib/core/common.glsl"
#include "/lib/water/water_sim_common.glsl"
#include "/lib/material/material_ids.glsl"

// Interaction sources available to shader packs (Iris source, IrisExclusiveUniforms):
//   * the local player's eye position (relativeEyePosition), feet-in-water (feetInWater,
//     Iris >= 1.10.4) and head-in-water (isEyeInWater);
//   * the player's vehicle: id via entity.properties (vehicleId), position
//     (relativeVehiclePosition), heading (vehicleLookVector), vehicleInWater.
// Other players, mobs and items are not exposed and cannot disturb the water.

void splitWorld(vec3 relToCamera, out ivec3 block, out vec3 frac) {
    vec3 p = cameraPositionFract + relToCamera;
    vec3 fl = floor(p);
    block = cameraPositionInt + ivec3(fl);
    frac = p - fl;
}

vec3 worldDelta(ivec3 b1, vec3 f1, ivec3 b0, vec3 f0) { return vec3(b1 - b0) + (f1 - f0); }

// Position in cells relative to the window centre.
vec2 cellsRelative(ivec3 block, vec3 frac, ivec2 centre) {
    return vec2(block.xz * SIM_CPB - centre) + frac.xz * float(SIM_CPB);
}

void updateWaterSimControl() {
    bool init = wsHeader.x != WS_VERSION;
    float ft = clamp(frameTime, 0.0, 0.25);

    // ---- player ------------------------------------------------------------------------
    vec3 eyeRel = -relativeEyePosition;                    // eye relative to the camera
    float feetBelowEye = inSwimmingAnimation ? 0.3 : 1.5;
    ivec3 pb; vec3 pf;
    splitWorld(eyeRel - vec3(0.0, feetBelowEye, 0.0), pb, pf);
    vec3 pDelta = init ? vec3(0.0) : worldDelta(pb, pf, wsPlayerCell.xyz, wsPlayerFrac.xyz);
    bool teleport = !init && length(pDelta) > SIM_TELEPORT;
    vec3 pVel = (teleport || ft <= 0.0) ? vec3(0.0) : pDelta / max(ft, 1e-4);

    #if IRIS_VERSION >= 11004
        bool feetWet = feetInWater;
        bool boat = isRiding && vehicleId == ENTITY_BOAT && (vehicleInWater || feetInWater);
    #else
        bool feetWet = false;
        bool boat = false;
    #endif
    bool wet = (feetWet || isEyeInWater == 1) && !isRiding;
    bool wasWet = !init && wsPlayerCell.w != 0;

    // ---- boat --------------------------------------------------------------------------
    ivec3 bb = pb; vec3 bf = pf;
    vec3 bVel = vec3(0.0);
    bool hadBoat = !init && wsBoatCell.w != 0;
    #if IRIS_VERSION >= 11004
    if (boat) {
        splitWorld(-relativeVehiclePosition, bb, bf);
        if (hadBoat) {
            vec3 d = worldDelta(bb, bf, wsBoatCell.xyz, wsBoatFrac.xyz);
            if (length(d) < SIM_TELEPORT) bVel = d / max(ft, 1e-4);
        }
    }
    #endif

    // ---- sleep / clear decisions -------------------------------------------------------
    bool contact = wet || boat;
    float idle = init ? SIM_IDLE_SLEEP : wsTiming.z;
    idle = contact ? 0.0 : min(idle + ft, 1e4);
    bool awake = idle < SIM_IDLE_SLEEP;
    bool wasAwake = !init && (wsHeader.w & WS_FLAG_AWAKE) != 0;
    bool clear = init || teleport || (awake && !wasAwake);

    // ---- fixed time step ---------------------------------------------------------------
    float acc = (init || !awake) ? 0.0 : wsTiming.x;
    int steps = 0;
    if (awake) {
        acc += ft;
        steps = min(int(acc / SIM_DT), SIM_MAX_STEPS);
        acc -= float(steps) * SIM_DT;
        acc = min(acc, SIM_DT);           // drop time we cannot catch up on
        if (clear) steps = max(steps, 1);  // a clear must reach the images
    }

    // The window only moves on frames that step, so stored data and centre stay consistent.
    int parityBefore = init ? 0 : simLatestParity();
    ivec2 oldCentre = init ? ivec2(0) : wsWindow.xy;
    ivec3 anchorB = boat ? bb : pb;
    vec3 anchorF = boat ? bf : pf;
    ivec2 centre = oldCentre;
    if (steps > 0 || init) centre = anchorB.xz * SIM_CPB + ivec2(floor(anchorF.xz * float(SIM_CPB)));

    // ---- sources (cells relative to the new centre) ------------------------------------
    vec2 pNow = cellsRelative(pb, pf, centre);
    vec2 pPrev = (init || teleport) ? pNow : cellsRelative(wsPlayerCell.xyz, wsPlayerFrac.xyz, centre);
    float speed = length(pVel.xz);
    bool swimming = wet && !boat;
    float strength = swimming ? WATER_SIM_STRENGTH * PLAYER_RIPPLE_STRENGTH : 0.0;
    wsPlayerSrc0 = vec4(pPrev, 0.45 * float(SIM_CPB), strength);
    wsPlayerSrc1 = vec4(pNow, speed, swimming ? strength * (1.0 - smoothstep(0.2, 1.0, speed)) : 0.0);

    vec2 bNow = cellsRelative(bb, bf, centre);
    vec2 bPrev = (hadBoat && boat) ? cellsRelative(wsBoatCell.xyz, wsBoatFrac.xyz, centre) : bNow;
    vec2 heading = vehicleLookVector.xz;
    heading = dot(heading, heading) > 1e-6 ? normalize(heading) : vec2(1.0, 0.0);
    float bSpeed = length(bVel.xz);
    wsBoatSrc0 = vec4(bPrev, boat ? 1.0 : 0.0, boat ? WATER_SIM_STRENGTH * BOAT_WAKE_STRENGTH : 0.0);
    wsBoatSrc1 = vec4(bNow, atan(heading.y, heading.x), bSpeed);

    // ---- splashes: mass-conserving impulses -----------------------------------------
    // An impulse is applied by step 0 of the first frame that steps. If the previous frame
    // stepped, whatever it carried has been consumed; otherwise it is still pending and is
    // re-expressed relative to the (possibly moved) window centre.
    bool consumed = init || teleport || wsHeader.z > 0;
    vec4 impulse = consumed ? vec4(0.0) : wsImpulse;
    if (!consumed) impulse.xy += vec2(oldCentre - centre);
    if (!init && !teleport) {
        if (wet && !wasWet && pVel.y < -2.0) {
            float a = 0.045 * sqrt(min(-pVel.y, 30.0)) * WATER_SIM_STRENGTH * PLAYER_RIPPLE_STRENGTH;
            impulse = vec4(pNow, 0.55 * float(SIM_CPB), -a);
            ivec2 c = pb.xz * SIM_CPB + ivec2(floor(pf.xz * float(SIM_CPB)));
            wsDelayed = vec4(0.55 * a, 0.28, 0.3 * float(SIM_CPB), 0.0);
            wsDelayedCell = ivec4(c, 0, 0);
        } else if (!wet && wasWet && !isRiding && pVel.y > 1.0) {
            impulse = vec4(pNow, 0.4 * float(SIM_CPB), -0.02 * WATER_SIM_STRENGTH * PLAYER_RIPPLE_STRENGTH);
        }
        if (wsDelayed.x > 0.0) {
            wsDelayed.y -= ft;
            if (wsDelayed.y <= 0.0 && impulse.w == 0.0) {
                // Rebound: the collapsing crater throws up a narrow column.
                impulse = vec4(vec2(wsDelayedCell.xy - centre) + 0.5, wsDelayed.z, wsDelayed.x);
                wsDelayed.x = 0.0;
            }
        }
    } else {
        wsDelayed = vec4(0.0);
    }
    wsImpulse = impulse;

    // ---- water plane: the sim is applied to water surfaces near this height ------------
    float plane = init ? cameraPosition.y : wsPlane.x;
    if (boat) plane = float(bb.y) + bf.y + 0.35;
    else if (feetWet && isEyeInWater == 0) plane = float(pb.y) + 0.9;
    else if (isEyeInWater == 1 && (init || teleport)) plane = float(pb.y) + 2.0;

    // ---- commit ------------------------------------------------------------------------
    wsHeader = ivec4(WS_VERSION, parityBefore, steps, (clear ? WS_FLAG_CLEAR : 0) | (awake ? WS_FLAG_AWAKE : 0));
    wsWindow = ivec4(centre, (steps > 0 && !init) ? oldCentre : centre);
    float clock = init ? 0.0 : wsTiming.w;
    clock = mod(clock + float(steps) * SIM_DT, 1000.0);
    wsTiming = vec4(acc, saturate(acc / SIM_DT), idle, clock);
    wsPlane = vec4(plane, awake ? 1.0 - smoothstep(0.6 * SIM_IDLE_SLEEP, SIM_IDLE_SLEEP, idle) : 0.0, 0.0, 0.0);
    wsPlayerCell = ivec4(pb, wet ? 1 : 0);
    wsPlayerFrac = vec4(pf, 0.0);
    wsBoatCell = ivec4(bb, boat ? 1 : 0);
    wsBoatFrac = vec4(bf, 0.0);
}

#endif

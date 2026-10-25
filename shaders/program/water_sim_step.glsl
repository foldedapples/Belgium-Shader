// begin_b..begin_e.csh - one fixed time step of the local water simulation each
// (SIM_STEP_INDEX 0..3). Steps beyond the number scheduled by begin.csh return immediately.
//
// Scheme: damped Klein-Gordon wave equation with Kelvin-Voigt viscosity,
//   d2h/dt2 = c^2 lap(h) - Omega^2 h + nu lap(dh/dt) - gamma dh/dt + f,
// integrated with a two-level leapfrog (Verlet) update:
//   h+ = h + (h - h-)(1 - gamma dt) + (c dt)^2 lap(h) - (Omega dt)^2 h + nu dt lap(h - h-) + dt^2 f
// lap() is the isotropic 9-point stencil of Oono & Puri: (orth/2 + diag/4 - 3 h) / dx^2,
// whose ripples stay round instead of square.
#include "/lib/core/common.glsl"
#include "/lib/water/water_sim_common.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
// Iris reads workGroups as literal integers (no arithmetic): WATER_SIM_RES / 16.
#if WATER_SIM_RES == 256
    const ivec3 workGroups = ivec3(16, 16, 1);
#elif WATER_SIM_RES == 1024
    const ivec3 workGroups = ivec3(64, 64, 1);
#elif WATER_SIM_RES == 2048
    const ivec3 workGroups = ivec3(128, 128, 1);
#else
    const ivec3 workGroups = ivec3(32, 32, 1);
#endif

layout(rgba16f) uniform image2D waterSimA;
layout(rgba16f) uniform image2D waterSimB;

int readParity;
bool firstStep;
bool clearAll;
ivec2 centre;
ivec2 prevCentre;

// h_now, h_prev of a world cell; cells outside the window, cells that just entered it and
// cleared state read as calm water.
vec2 loadCell(ivec2 cell) {
    if (clearAll || !simInWindow(cell, centre)) return vec2(0.0);
    if (firstStep && !simInWindow(cell, prevCentre)) return vec2(0.0);
    ivec2 t = simTexel(cell);
    return readParity == 0 ? imageLoad(waterSimA, t).xy : imageLoad(waterSimB, t).xy;
}

float gaussian(vec2 d, float radius) {
    return exp(-dot(d, d) / max(radius * radius, 1e-4));
}

// Laplacian of a Gaussian: zero net volume, so a splash never adds or removes water.
float mexicanHat(vec2 d, float sigma) {
    float r2 = dot(d, d) / max(sigma * sigma, 1e-4);
    // Cut off at ~7 sigma: truncating earlier (e.g. 4 sigma) loses a measurable volume.
    return r2 > 50.0 ? 0.0 : (1.0 - 0.5 * r2) * exp(-0.5 * r2);
}

// Boat hull: a flat-bottomed elliptical pressure footprint in the boat's frame (blocks).
float hullFootprint(vec2 dBlocks, float heading) {
    vec2 fwd = vec2(cos(heading), sin(heading));
    float along = dot(dBlocks, fwd) / 0.78;
    float across = dot(dBlocks, vec2(-fwd.y, fwd.x)) / 0.42;
    return exp(-sq(along * along) - sq(across * across));
}

float sourceAcceleration(vec2 cellPos, float stepFraction, float clock) {
    float f = 0.0;
    // Player: pushes water away while moving, treads water gently while still.
    if (wsPlayerSrc0.w > 0.0) {
        vec2 p = mix(wsPlayerSrc0.xy, wsPlayerSrc1.xy, stepFraction);
        vec2 d = cellPos - p;
        if (dot(d, d) < sq(4.0 * wsPlayerSrc0.z)) {
            float speed = wsPlayerSrc1.z;
            float moving = smoothstep(0.15, 1.2, speed) * min(speed, 5.0) / 5.0;
            float g = gaussian(d, wsPlayerSrc0.z);
            f -= 3.0 * wsPlayerSrc0.w * moving * g;
            f -= 0.8 * wsPlayerSrc1.w * sin(TAU * 1.1 * clock) * g;
        }
    }
    // Boat: the hull's pressure, swept along its path between frames.
    if (wsBoatSrc0.z > 0.5) {
        vec2 p = mix(wsBoatSrc0.xy, wsBoatSrc1.xy, stepFraction);
        vec2 dBlocks = (cellPos - p) * SIM_DX;
        if (dot(dBlocks, dBlocks) < 4.0) {
            float speed = wsBoatSrc1.w;
            float g = hullFootprint(dBlocks, wsBoatSrc1.z);
            float drive = 0.3 + 0.7 * smoothstep(0.2, 6.0, speed);
            float bob = 0.35 * (1.0 - smoothstep(0.2, 1.5, speed)) * sin(TAU * 0.7 * clock);
            f -= 2.5 * wsBoatSrc0.w * (drive + bob) * g;
        }
    }
    return f;
}

void main() {
    if (SIM_STEP_INDEX >= wsHeader.z) return;
    ivec2 t = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(t, ivec2(SIM_N)))) return;

    readParity = (wsHeader.y + SIM_STEP_INDEX) & 1;
    firstStep = SIM_STEP_INDEX == 0;
    clearAll = firstStep && (wsHeader.w & WS_FLAG_CLEAR) != 0;
    centre = wsWindow.xy;
    prevCentre = wsWindow.zw;

    // World cell held by this texel inside the current window.
    ivec2 lo = centre - SIM_N / 2;
    ivec2 cell = lo + ((t - lo) & ivec2(SIM_N - 1));
    ivec2 rel = cell - centre;

    vec2 c  = loadCell(cell);
    vec2 e  = loadCell(cell + ivec2(1, 0));
    vec2 w  = loadCell(cell - ivec2(1, 0));
    vec2 n  = loadCell(cell + ivec2(0, 1));
    vec2 s  = loadCell(cell - ivec2(0, 1));
    vec2 ne = loadCell(cell + ivec2(1, 1));
    vec2 nw = loadCell(cell + ivec2(-1, 1));
    vec2 se = loadCell(cell + ivec2(1, -1));
    vec2 sw = loadCell(cell + ivec2(-1, -1));

    const float invDx2 = 1.0 / (SIM_DX * SIM_DX);
    vec2 orth = e + w + n + s;
    vec2 diag = ne + nw + se + sw;
    vec2 lap = (0.5 * orth + 0.25 * diag - 3.0 * c) * invDx2;  // .x on h_now, .y on h_prev
    float lapH = lap.x;
    float lapV = lap.x - lap.y;                               // lap of (h_now - h_prev)

    float h = c.x, hPrev = c.y;
    vec2 cellPos = vec2(rel) + 0.5;
    float steps = float(max(wsHeader.z, 1));
    float stepFraction = (float(SIM_STEP_INDEX) + 0.5) / steps;
    float clock = wsTiming.w + float(SIM_STEP_INDEX) * SIM_DT;
    float force = sourceAcceleration(cellPos, stepFraction, clock);

    // Absorbing sponge near the window edge.
    float edge = maxOf(abs(vec2(rel) + 0.5)) / float(SIM_N / 2);
    float sponge = smoothstep(1.0 - SIM_SPONGE_WIDTH, 1.0, edge);
    float gamma = SIM_DAMPING + SIM_SPONGE * sponge;

    const float dt = SIM_DT;
    float hNext = h + (h - hPrev) * (1.0 - gamma * dt)
                + sq(SIM_WAVE_SPEED * dt) * lapH
                + SIM_VISCOSITY * dt * lapV
                - sq(SIM_RESTORING * dt) * h
                + dt * dt * force;

    // Splash impulses are a displacement of both time levels (zero initial velocity).
    float displacement = 0.0;
    if (firstStep && wsImpulse.w != 0.0) {
        displacement = wsImpulse.w * mexicanHat(cellPos - wsImpulse.xy, wsImpulse.z);
    }
    hNext += displacement;
    float hStored = h + displacement;

    hNext = clamp(hNext, -SIM_HEIGHT_LIMIT, SIM_HEIGHT_LIMIT);
    hStored = clamp(hStored, -SIM_HEIGHT_LIMIT, SIM_HEIGHT_LIMIT);
    if (isnan(hNext) || isinf(hNext) || isnan(hStored) || isinf(hStored)) { hNext = 0.0; hStored = 0.0; }

    // Gradient of the current field for smooth rendering (central differences, blocks/block).
    vec2 grad = vec2(e.x - w.x, n.x - s.x) * (0.5 / SIM_DX);

    vec4 outTexel = vec4(hNext, hStored, grad);
    if (readParity == 0) imageStore(waterSimB, t, outTexel);
    else imageStore(waterSimA, t, outTexel);
}
#endif

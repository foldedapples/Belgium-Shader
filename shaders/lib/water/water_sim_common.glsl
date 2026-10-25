#ifndef WATER_SIM_COMMON_GLSL
#define WATER_SIM_COMMON_GLSL
#include "/lib/core/common.glsl"

// Layer B: local height-field simulation (ORIGINAL_ARCHITECTURE.md sec. 8.2).
//
// Domain: WATER_SIM_RES^2 cells, WATER_SIM_CPB cells per block, centred on the player.
// Cells are addressed by integer *world* cell index c (= floor(world xz * CPB)); a cell lives
// in texel (c mod N), so the window can follow the player without copying data.
// Texel layout (RGBA16F, two images ping-ponged): (h_now, h_prev, dh/dx, dh/dz) in blocks.

const int   SIM_N = WATER_SIM_RES;
const int   SIM_CPB = WATER_SIM_CPB;
const float SIM_DX = 1.0 / float(WATER_SIM_CPB);          // cell size in blocks
const float SIM_HZ = 60.0;
const float SIM_DT = 1.0 / SIM_HZ;
const int   SIM_MAX_STEPS = 4;                             // begin_b .. begin_e

// Physical parameters (blocks, seconds). The Courant number c*dt/dx and viscous number
// nu*dt/dx^2 are clamped at compile time to the leapfrog scheme's stable range.
const float SIM_WAVE_SPEED = min(WATER_SIM_WAVE_SPEED, 0.6 * SIM_DX / SIM_DT);
const float SIM_VISCOSITY = 0.05 * SIM_DX * SIM_DX / SIM_DT;
const float SIM_DAMPING = 0.45;          // 1/s, open-water decay
// Restoring term (gravity analogue): a steady pressure makes a finite dip F/Omega^2 instead
// of the unbounded hole of the bare 2-D wave equation, and the waves become dispersive
// (omega^2 = c^2 k^2 + Omega^2), which reads more like water.
const float SIM_RESTORING = TAU * 0.8;  // rad/s
const float SIM_SPONGE = 14.0;           // 1/s, extra damping at the window edge
const float SIM_SPONGE_WIDTH = 0.12;     // fraction of the half-window
const float SIM_HEIGHT_LIMIT = 0.6;      // blocks
const float SIM_IDLE_SLEEP = 30.0;       // seconds without contact before sleeping
const float SIM_TELEPORT = 24.0;         // blocks per frame treated as a teleport

#define WS_VERSION 0x57534D33
#define WS_FLAG_CLEAR 1
#define WS_FLAG_AWAKE 2

#ifdef WATER_SIM_WRITER
    #define WS_ACCESS
#else
    #define WS_ACCESS readonly
#endif

layout(std430, binding = 1) WS_ACCESS buffer WaterSimBuffer {
    ivec4 wsHeader;        // x version, y parity of the image holding the state before this
                           //   frame's steps, z steps scheduled this frame, w flags
    ivec4 wsWindow;        // xy current window centre (world cells), zw previous centre
    vec4  wsTiming;        // x accumulator (s), y render alpha, z idle time (s), w sim clock (s)
    vec4  wsPlane;         // x water-plane world Y, y render fade 0..1, z/w reserved
    ivec4 wsPlayerCell;    // xyz block of the player's feet last frame, w wet last frame
    vec4  wsPlayerFrac;    // xyz fraction, w reserved
    ivec4 wsBoatCell;      // xyz boat block last frame, w riding a boat last frame
    vec4  wsBoatFrac;      // xyz fraction, w reserved
    vec4  wsPlayerSrc0;    // xy start (cells rel. window centre), z radius (cells), w strength
    vec4  wsPlayerSrc1;    // xy end, z speed (blocks/s), w bob strength
    vec4  wsBoatSrc0;      // xy start, z active, w strength
    vec4  wsBoatSrc1;      // xy end, z heading (rad), w speed (blocks/s)
    vec4  wsImpulse;       // xy centre (cells rel. window centre), z radius (cells), w amplitude
    vec4  wsDelayed;       // x amplitude, y countdown (s), z radius (cells), w reserved
    ivec4 wsDelayedCell;   // xy world cell of the delayed rebound
};

ivec2 simTexel(ivec2 worldCell) { return worldCell & ivec2(SIM_N - 1); }

bool simInWindow(ivec2 cell, ivec2 centre) {
    ivec2 r = cell - centre;
    return all(greaterThanEqual(r, ivec2(-SIM_N / 2))) && all(lessThan(r, ivec2(SIM_N / 2)));
}

// Parity of the image holding the newest state after this frame's steps.
int simLatestParity() { return (wsHeader.y + wsHeader.z) & 1; }

#endif

#ifndef MERIDIAN_STATE
#define MERIDIAN_STATE

// Persistent per-frame state shared by all passes (SSBO 0, bufferObject.0 in shaders.properties).
// Written only by the passes named in the comments; everything else reads.
layout(std430, binding = 0) buffer MeridianState {
    float exposure;            // composite (exposure pass): adapted linear exposure
    float avgLogLuminance;     // composite (exposure pass)
    float simAccumulator;      // prepare (water sim): fixed-step time accumulator
    int   simParity;           // prepare (water sim): 0 = image A newest, 1 = image B newest
    vec4  simCenter;           // prepare (water sim): xz domain centre, y water plane, w valid
    vec4  playerPrev;          // prepare (water sim): xyz previous feet position, w in-water flag
    vec4  simPrevCenter;       // prepare (water sim): domain centre of the previous frame (xz), w valid
    ivec4 simInfo;             // prepare (water sim): x parity read by step 0, y steps this frame
    vec4  vehiclePrev;         // prepare (water sim): xyz previous vehicle position, w valid
    vec4  lightBasis[3];       // begin: light-space x, y, z axes (z = towards the light), w unused
    vec4  cascadeCenter[4];    // begin: per-cascade snapped light-space offset (xy), z texel size
    vec4  lightVolumeOrigin;   // begin: xyz voxel-volume origin (world block), w = frame valid
    vec4  lightVolumePrevOrigin; // begin: previous origin, for reprojection of the light volume
    vec4  cloudOffset;         // begin: xy cumulus wind offset (m), zw cirrus offset (m)
    vec4  skySH[9];            // prepare: sky irradiance / pi as order-2 SH (rgb)
    vec4  misc;                // x: splash energy, y: previous swimming flag, zw cloud-shadow map centre (prepare)
    ivec4 shadowAnchor;        // begin: xyz world block the light rotation pivots about, w = valid
    vec4  playerLast;          // prepare (water sim bookkeeping): feet at the last stepped frame, w in water
    vec4  vehicleLast;         // prepare (water sim bookkeeping): vehicle at the last stepped frame, w valid
} state;

#endif

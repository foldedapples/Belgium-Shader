#ifndef WATER_SIM_SAMPLE_GLSL
#define WATER_SIM_SAMPLE_GLSL
// Reading the simulation from fragment shaders (gbuffers_water, debug views).
#include "/lib/core/common.glsl"
#include "/lib/water/water_sim_common.glsl"

uniform sampler2D beWaterSimATex;
uniform sampler2D beWaterSimBTex;

vec4 simFetch(ivec2 cell, int parity) {
    if (!simInWindow(cell, wsWindow.xy)) return vec4(0.0);
    ivec2 t = simTexel(cell);
    return parity == 0 ? texelFetch(beWaterSimATex, t, 0) : texelFetch(beWaterSimBTex, t, 0);
}

struct SimSurface {
    float height;
    vec2  slope;
    float velocity; // blocks/s
    float weight;   // 0 outside the domain / plane, 1 fully simulated
};

// `scenePos` is camera-relative; the world cell is built from the integer camera position so
// the lookup stays exact far from the origin.
SimSurface sampleWaterSim(vec3 scenePos) {
    SimSurface s;
    s.height = 0.0; s.slope = vec2(0.0); s.velocity = 0.0; s.weight = 0.0;
    if (wsHeader.x != WS_VERSION || wsPlane.y <= 0.0) return s;

    vec3 local = cameraPositionFract + scenePos;
    // Only water surfaces near the simulated plane receive the ripples.
    float worldY = float(cameraPositionInt.y) + local.y;
    float planeWeight = 1.0 - smoothstep(1.0, 2.0, abs(worldY - wsPlane.x));
    if (planeWeight <= 0.0) return s;

    vec2 p = local.xz * float(SIM_CPB) - 0.5;      // in cells, relative to the camera's cell
    vec2 pf = floor(p);
    vec2 f = p - pf;
    ivec2 cell = cameraPositionInt.xz * SIM_CPB + ivec2(pf);

    // Fade out near the edge of the window so it never shows as a line on the water.
    vec2 rel = vec2(cell - wsWindow.xy) + f;
    float edge = maxOf(abs(rel)) / float(SIM_N / 2);
    float edgeWeight = 1.0 - smoothstep(0.72, 0.86, edge);
    s.weight = planeWeight * edgeWeight * wsPlane.y;
    if (s.weight <= 0.0) return s;

    int parity = simLatestParity();
    vec4 a = simFetch(cell, parity);
    vec4 b = simFetch(cell + ivec2(1, 0), parity);
    vec4 c = simFetch(cell + ivec2(0, 1), parity);
    vec4 d = simFetch(cell + ivec2(1, 1), parity);
    vec4 v = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    // Present the state one step behind, interpolated by the accumulator, for smooth motion
    // at any frame rate.
    s.height = mix(v.y, v.x, wsTiming.y) * s.weight;
    s.slope = v.zw * s.weight;
    s.velocity = (v.x - v.y) / SIM_DT * s.weight;
    return s;
}

#endif

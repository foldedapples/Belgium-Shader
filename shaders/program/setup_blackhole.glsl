// setup3.csh (End) - geodesic LUT for the black hole: one column per impact parameter.
//   row 0      : x = escape angle phi_end (or -1 if captured), y = capture angle, z = b
//   rows 1..255: (u, du/dphi) sampled at phi = (row - 1) / 254 * BH_PHI_MAX, u = 0 after escape,
//                u = 1 after capture.
#include "/lib/core/common.glsl"
#include "/lib/end/black_hole_common.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
// BH_LUT_B / 64; Iris reads workGroups as literal integers.
const ivec3 workGroups = ivec3(8, 1, 1);

layout(rgba32f) uniform writeonly image2D blackHoleLut;

void main() {
    int col = int(gl_GlobalInvocationID.x);
    if (col >= BH_LUT_B) return;
    float b = bhImpactFromX((float(col) + 0.5) / float(BH_LUT_B));
    float D = bhObserverDistance();
    vec2 s = bhInitialState(b, D);

    const int SUB = 24;                                  // integration steps per stored row
    const int ROWS = BH_LUT_PHI - 1;
    float h = BH_PHI_MAX / float((ROWS - 1) * SUB);
    float phiEnd = -1.0, phiCapture = -1.0;
    bool done = false;
    float phi = 0.0;
    imageStore(blackHoleLut, ivec2(col, 1), vec4(s, 0.0, 0.0));
    for (int row = 2; row <= ROWS; row++) {
        for (int k = 0; k < SUB && !done; k++) {
            vec2 next = bhRk4(s, h);
            if (next.x <= 0.0) {
                // Escaped: interpolate the phi where u crossed zero.
                phiEnd = phi + h * s.x / max(s.x - next.x, 1e-9);
                done = true;
                s = vec2(0.0, next.y);
            } else if (next.x >= 1.0) {
                phiCapture = phi + h;
                done = true;
                s = vec2(1.0, 0.0);
            } else {
                s = next;
            }
            phi += h;
        }
        if (done && s.x <= 0.0) imageStore(blackHoleLut, ivec2(col, row), vec4(0.0, 0.0, 0.0, 0.0));
        else imageStore(blackHoleLut, ivec2(col, row), vec4(s, 0.0, 0.0));
    }
    if (!done) phiEnd = BH_PHI_MAX;     // still orbiting: treat as escaping at the limit
    imageStore(blackHoleLut, ivec2(col, 0), vec4(phiEnd, phiCapture, b, 0.0));
}
#endif

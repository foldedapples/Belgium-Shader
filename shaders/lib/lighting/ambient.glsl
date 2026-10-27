#ifndef MERIDIAN_AMBIENT
#define MERIDIAN_AMBIENT

// Sky ambient: evaluates the SH projection made in prepare (state.skySH, already cosine-convolved
// and divided by pi), so albedo * skyIrradiance(n) is the diffuse sky light on a surface.
vec3 skyIrradiance(vec3 d) {
    vec3 r = state.skySH[0].rgb * 0.282095
           + state.skySH[1].rgb * (0.488603 * d.y)
           + state.skySH[2].rgb * (0.488603 * d.z)
           + state.skySH[3].rgb * (0.488603 * d.x)
           + state.skySH[4].rgb * (1.092548 * d.x * d.y)
           + state.skySH[5].rgb * (1.092548 * d.y * d.z)
           + state.skySH[6].rgb * (0.315392 * (3.0 * d.z * d.z - 1.0))
           + state.skySH[7].rgb * (1.092548 * d.x * d.z)
           + state.skySH[8].rgb * (0.546274 * (d.x * d.x - d.y * d.y));
    return max(r, vec3(0.0));
}

// Vanilla sky light (0..1) -> fraction of the open sky a point sees. Vanilla light falls by one
// level per block of travel, so the curve is steep near 1 and flat near 0.
float skyVisibility(float skyLight) {
    return skyLight * skyLight * (3.0 - 2.0 * skyLight) * skyLight;
}

// Vanilla block light (0..1) -> relative irradiance from nearby emitters. Vanilla falls linearly
// with distance; real point lights fall with the inverse square, which this curve approximates
// for a light of level 14-15 (an exponent between 2 and 3 matches distance^-2 over 1..12 blocks).
// The lowest levels taper smoothly to zero: a hard step at level 0 draws diamond-shaped edges
// around every torch at night (observed in game with an earlier pack).
float blockLightFalloff(float blockLight) {
    float l = saturate(blockLight);
    return pow(l, 2.6) * smoothstep(0.0, 0.5, l);
}

#endif

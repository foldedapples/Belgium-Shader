#ifndef MERIDIAN_TANGENT
#define MERIDIAN_TANGENT

// Fragment stages only (uses screen-space derivatives).

// Tangent frame from screen-space derivatives of position and texture coordinates (Schueler
// 2006, "cotangent frame"). T follows +U and B follows +V of the texture whatever the vertex
// tangent's handedness says, which is what LabPBR's top-down (Y-down) normal maps expect.
// `fallbackT` (vertex tangent with sign in w) is used when the derivatives degenerate.
mat3 textureTangentFrame(vec3 n, vec3 pos, vec2 uv, vec4 fallbackT) {
    vec3 dp1 = dFdx(pos), dp2 = dFdy(pos);
    vec2 duv1 = dFdx(uv), duv2 = dFdy(uv);
    vec3 dp2perp = cross(dp2, n), dp1perp = cross(n, dp1);
    vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
    float m = max(dot(t, t), dot(b, b));
    if (m < 1e-20) {
        t = normalize(fallbackT.xyz - n * dot(n, fallbackT.xyz));
        return mat3(t, cross(n, t) * fallbackT.w, n);
    }
    t = normalize(t - n * dot(n, t));
    b = normalize(b - n * dot(n, b) - t * dot(t, b));
    return mat3(t, b, n);
}

#endif

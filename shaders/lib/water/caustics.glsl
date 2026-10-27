#ifndef MERIDIAN_CAUSTICS
#define MERIDIAN_CAUSTICS

// Sunlight on surfaces below water. The shadow atlas tells us whether a water surface lies
// between the receiver and the light (shadowtex0 includes translucents, shadowtex1 does not, and
// shadowcolor1.z marks water), and how deep the receiver is along the light.
//
// Absorption: Beer-Lambert over that depth with the water medium's coefficients.
// Caustics: computed from the actual wave surface above the point. Each surface point refracts
// the light ray (Snell); the floor receives the light of the surface patch that lands on it, so
// the intensity is the inverse of the area change of that mapping, 1 / |det J|, with J the
// Jacobian of x -> x + depth * refracted_xz(x) / refracted_y(x). J comes from finite differences
// of the analytic wave gradient, so the caustic pattern moves exactly with the visible waves.
// Requires waves.glsl, fog.glsl (water coefficients), shadow samplers and shadow_proj.

vec2 refractedOffset(vec2 xz, vec3 lightDir, float depth, WaterParams wp) {
    vec3 hg = waveHeightGrad(xz, frameTimeCounter, wp);
    vec3 n = normalize(vec3(-hg.y, 1.0, -hg.z));
    vec3 r = refract(-lightDir, n, 1.0 / 1.333);
    return r.xz / max(-r.y, 0.2) * depth;
}

// Returns the multiplier for direct light reaching `playerPos`.
vec3 underwaterLight(vec3 playerPos, vec3 lightDir) {
    mat3 L = shadowLightRotation();
    vec3 lp = L * playerPos;
    for (int k = 0; k < 4; k++) {
        vec2 c = (lp.xy + state.cascadeCenter[k].xy) / cascadeExtent(k);
        if (maxOf(abs(c)) > 0.95) continue;
        vec2 uv = cascadeOrigin(k) + (c * 0.5 + 0.5) * 0.5;
        float z = (-lp.z / SHADOW_Z_RANGE) * 0.5 + 0.5;
        float dAll = texture(shadowtex0, uv).r;
        if (dAll >= z - 1e-5) return vec3(1.0);          // nothing translucent in front
        if (texture(shadowcolor1, uv).z < 0.5) return vec3(1.0);   // translucent, but not water
        float depth = (z - dAll) * 2.0 * SHADOW_Z_RANGE;   // along the light, in blocks
        vec3 att = exp(-waterAbsorption() * depth);
        #ifdef WATER_CAUSTICS
        if (lightDir.y > 0.05 && depth < 24.0) {
            // Point on the surface above the receiver, back along the light (camera-relative, as
            // the wave functions expect).
            vec2 xz = playerPos.xz + lightDir.xz * depth;
            WaterParams wp = waterParamsAt(vec3(0.0, 1.0, 0.0), 1.0);
            const float e = 0.12;
            float dVert = depth * lightDir.y;
            vec2 o0 = refractedOffset(xz, lightDir, dVert, wp);
            vec2 ox = refractedOffset(xz + vec2(e, 0.0), lightDir, dVert, wp);
            vec2 oz = refractedOffset(xz + vec2(0.0, e), lightDir, dVert, wp);
            vec2 jx = vec2(1.0, 0.0) + (ox - o0) / e;
            vec2 jz = vec2(0.0, 1.0) + (oz - o0) / e;
            float det = abs(jx.x * jz.y - jx.y * jz.x);
            // Peak focus limited to 3.5x (6x made shallow shorelines glow saturated cyan; the mean
            // over the pattern stays ~1 either way).
            float caustic = clamp(1.0 / max(det, 0.15), 0.0, 3.5);
            // Deep water blurs the pattern back towards uniform light.
            caustic = mix(caustic, 1.0, saturate(depth / 20.0));
            att *= caustic;
        }
        #endif
        return att;
    }
    return vec3(1.0);
}

#endif

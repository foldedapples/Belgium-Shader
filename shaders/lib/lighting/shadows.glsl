#ifndef MERIDIAN_SHADOWS
#define MERIDIAN_SHADOWS

// Receiver side of the cascaded shadow maps: cascade selection, normal-offset bias,
// PCF / PCSS filtering with hardware comparison, coloured shadows through translucent casters.
// Needs: state.glsl, shadow_proj.glsl, math, noise. Samplers declared here.

uniform sampler2DShadow shadowtex0HW;
uniform sampler2DShadow shadowtex1HW;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

struct ShadowCoord {
    vec3 uvz;     // atlas uv, comparison depth in [0,1]
    int  cascade; // -1 outside every cascade
    float texelBlocks;
};

// Cascade-space position (x,y in [-1,1] inside, z = light-space depth) for cascade k.
vec3 cascadeSpace(vec3 lightPos, int k) {
    return vec3((lightPos.xy + state.cascadeCenter[k].xy) / cascadeExtent(k), lightPos.z);
}

ShadowCoord shadowCoordFor(vec3 lightPos, float margin) {
    ShadowCoord sc;
    sc.cascade = -1;
    sc.uvz = vec3(0.0);
    sc.texelBlocks = 1.0;
    for (int k = 0; k < 4; k++) {
        vec3 c = cascadeSpace(lightPos, k);
        if (maxOf(abs(c.xy)) < CASCADE_SELECT - margin / cascadeExtent(k) || (k == 3 && maxOf(abs(c.xy)) < 1.0)) {
            sc.cascade = k;
            sc.uvz = vec3(cascadeOrigin(k) + (c.xy * 0.5 + 0.5) * 0.5, (-c.z / SHADOW_Z_RANGE) * 0.5 + 0.5);
            sc.texelBlocks = cascadeTexel(k);
            return sc;
        }
    }
    return sc;
}

// Clamp a filter tap into the cascade's quadrant so it never reads a neighbouring cascade.
vec2 clampToQuadrant(vec2 uv, int k) {
    vec2 o = cascadeOrigin(k);
    float pad = 1.5 / float(shadowMapResolution);
    return clamp(uv, o + pad, o + 0.5 - pad);
}

vec2 vogelDisk(int i, int n, float phi) {
    float r = sqrt((float(i) + 0.5) / float(n));
    float a = float(i) * GOLDEN_ANGLE + phi;
    return r * vec2(cos(a), sin(a));
}

// Average blocker depth difference (in blocks along the light) for PCSS; < 0 means no blocker.
float blockerDistance(ShadowCoord sc, float radiusUv, float phi) {
    float sum = 0.0, count = 0.0;
    const int N = 8;
    for (int i = 0; i < N; i++) {
        vec2 uv = clampToQuadrant(sc.uvz.xy + vogelDisk(i, N, phi) * radiusUv, sc.cascade);
        float d = texture(shadowtex1, uv).r;
        if (d < sc.uvz.z) { sum += sc.uvz.z - d; count += 1.0; }
    }
    return count > 0.0 ? (sum / count) * 2.0 * SHADOW_Z_RANGE : -1.0;
}

struct ShadowResult {
    vec3 light;       // per-channel transmission (0 = fully shadowed)
    float casterDist; // blocks from receiver to the nearest opaque blocker (for SSS), large if none
};

// Main entry. `playerPos` is the receiver in player space, `geoNormal` its geometric normal,
// `lightDir` the player-space light direction, `noise` a per-pixel [0,1) value.
ShadowResult sampleShadow(vec3 playerPos, vec3 geoNormal, vec3 lightDir, float noise, float sunAngularRadius) {
    ShadowResult res;
    res.light = vec3(1.0);
    res.casterDist = 1e4;

    mat3 L = shadowLightRotation();
    float NoL = dot(geoNormal, lightDir);
    // Normal offset scaled by the cascade texel and the slope; pushes the lookup off the surface.
    vec3 lp0 = L * playerPos;
    ShadowCoord sc0 = shadowCoordFor(lp0, 0.0);
    if (sc0.cascade < 0) return res;
    float texel = sc0.texelBlocks;
    float slope = sqrt(saturate(1.0 - NoL * NoL)) / max(abs(NoL), 0.2);
    vec3 offsetPos = playerPos + geoNormal * texel * (1.2 + 1.5 * slope) * (NoL < 0.0 ? -1.0 : 1.0);
    vec3 lp = L * offsetPos;

    float phi = noise * TAU;
    // Filter radius in blocks (soft shadows from the light's angular size).
    float minRadius = texel * 1.5;
    float radius = minRadius;
    ShadowCoord sc = shadowCoordFor(lp, 2.0);
    if (sc.cascade < 0) return res;

    #if SHADOW_FILTER == 2
    float searchBlocks = min(1.6 * SHADOW_SOFTNESS, cascadeFilterReach(sc.cascade));
    float searchUv = searchBlocks / (2.0 * cascadeExtent(sc.cascade)) * 0.5;
    float blocker = blockerDistance(sc, searchUv, phi);
    if (blocker < 0.0) return res;  // nothing in the search region: fully lit
    res.casterDist = blocker;
    radius = max(minRadius, blocker * tan(sunAngularRadius) * 2.0 * SHADOW_SOFTNESS);
    radius = min(radius, searchBlocks);
    #elif SHADOW_FILTER == 1
    radius = texel * 3.0 * SHADOW_SOFTNESS;
    #endif

    radius = min(radius, cascadeFilterReach(sc.cascade));
    float radiusUv = radius / (2.0 * cascadeExtent(sc.cascade)) * 0.5;
    // Depth bias grows with the filter footprint on sloped receivers.
    float bias = (0.5 * texel + radius * slope * 0.5) / (2.0 * SHADOW_Z_RANGE);
    float refZ = sc.uvz.z - bias;

    float opaque = 0.0, solidOrTrans = 0.0;
    #if SHADOW_FILTER == 0
    const int N = 4;
    #else
    const int N = SHADOW_SAMPLES;
    #endif
    vec3 tint = vec3(0.0);
    for (int i = 0; i < N; i++) {
        vec2 uv = clampToQuadrant(sc.uvz.xy + vogelDisk(i, N, phi) * radiusUv, sc.cascade);
        float o = texture(shadowtex1HW, vec3(uv, refZ));
        opaque += o;
        #ifdef COLORED_SHADOWS
        float a = texture(shadowtex0HW, vec3(uv, refZ));
        solidOrTrans += a;
        if (o > a) {
            vec4 c = texture(shadowcolor0, uv);
            tint += (o - a) * mix(vec3(1.0), srgbToLinear(c.rgb), sqrt(saturate(c.a)));
        }
        #endif
    }
    opaque /= float(N);
    #ifdef COLORED_SHADOWS
    solidOrTrans /= float(N);
    vec3 trans = (solidOrTrans + tint / float(N));
    res.light = min(vec3(opaque), trans);
    #else
    res.light = vec3(opaque);
    #endif

    // Fade the far cascade's edge to unshadowed so the shadow distance has no hard line.
    if (sc.cascade == 3) {
        vec3 c = cascadeSpace(lp, 3);
        float edge = smoothstep(0.85, 1.0, maxOf(abs(c.xy)));
        res.light = mix(res.light, vec3(1.0), edge);
    }
    return res;
}

#endif

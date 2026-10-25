#ifndef CLOUDS_CLOUDS_GLSL
#define CLOUDS_CLOUDS_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/core/phase_functions.glsl"

// Volumetric clouds (ORIGINAL_ARCHITECTURE.md sec. 7). Distances in blocks (= metres).
//
// Density = weather map (coverage, type, base lift) x type-dependent height profile x
// Perlin-Worley base shape, eroded at the edges by Worley detail. One slab holds every type:
// stratus (flat, low), stratocumulus, cumulus, and cumulonimbus towers with anvils during
// storms. Lighting: Beer-Lambert toward the light with exponentially growing steps, dual-lobe
// Henyey-Greenstein phase (silver lining) and three octaves of a multiple-scattering
// approximation, a powder term for dark crevices, height-graded ambient sky light, and point
// light from lightning bolts.

#include "/lib/core/textures.glsl"
uniform sampler3D cloudShapeTex;
uniform sampler3D cloudDetailTex;

const float WEATHER_TILE = 16384.0;    // weather map period (blocks); noise2d is 256 texels
const float SHAPE_TILE = 2400.0;       // 128 voxels -> 18.75 m
const float DETAIL_TILE = 240.0;       // 32 voxels -> 7.5 m, divides SHAPE_TILE exactly
const float CLOUD_MAX_THICKNESS = 6500.0;
const float CLOUD_EXTINCTION = 0.045;  // per block at density 1 (dense cumulus ~0.05/m)

struct CloudWeather {
    float coverage;
    float type;      // 0 stratus .. 0.5 cumulus .. 1 cumulonimbus
    float base;
    float thickness;
};

// Camera-relative position -> tile-local cloud coordinates. Modulo on the camera position is
// exact because every noise tile size divides the corresponding wrap period.
vec2 cloudLocalXZ(vec3 scenePos, float tile) {
    return mod(cameraPosition.xz, tile) + scenePos.xz;
}

CloudWeather sampleWeather(vec3 scenePos) {
    CloudWeather w;
    vec2 xz = cloudLocalXZ(scenePos, WEATHER_TILE);
    vec4 wm = texture(noise2dTex, (xz + fsCloudWind.xy) / WEATHER_TILE);
    float field = wm.r * 0.65 + wm.g * 0.35;
    float cov = fsCloud.x;
    w.coverage = smoothstep(1.0 - cov - 0.12, 1.0 - cov + 0.22, field);
    float storm = fsCloud.y;
    w.type = saturate(wm.b * 1.5 - 0.35 + storm * 0.9 + CLOUD_TYPE_BIAS);
    float cumulusThick = mix(260.0, 1500.0, smoothstep(0.12, 0.6, w.type));
    w.thickness = cumulusThick + 4800.0 * smoothstep(0.72, 1.0, w.type) * storm;
    w.base = fsCloud.z + (wm.a - 0.5) * 160.0 - 220.0 * storm * smoothstep(0.7, 1.0, w.type);
    return w;
}

float heightProfile(float h, float type) {
    float bottom = smoothstep(0.0, 0.06 + 0.08 * type, h);
    float topStart = mix(0.35, 0.72, type);
    float top = 1.0 - smoothstep(topStart, 1.0, h);
    return bottom * top;
}

// `lod` 0 = full detail, 1 = no detail erosion (light marching, shadows, empty skipping).
float cloudDensity(vec3 scenePos, CloudWeather w, int lod, out float heightFrac) {
    float y = cameraPosition.y + scenePos.y;
    float h = (y - w.base) / max(w.thickness, 1.0);
    heightFrac = h;
    if (h <= 0.0 || h >= 1.0 || w.coverage <= 0.0) return 0.0;

    float coverage = w.coverage;
    // Anvil: the top of a cumulonimbus spreads out downwind.
    float anvil = smoothstep(0.72, 1.0, w.type) * smoothstep(0.7, 0.9, h);
    coverage = saturate(coverage + anvil * 0.35);

    vec2 xz = cloudLocalXZ(scenePos, SHAPE_TILE) + fsCloudWind.zw;
    vec3 p = vec3(xz.x, y * 1.15, xz.y);
    vec4 s = texture(cloudShapeTex, p / SHAPE_TILE);
    float worley = s.g * 0.625 + s.b * 0.25 + s.a * 0.125;
    float base = remapSafe(s.r, worley - 1.0, 1.0, 0.0, 1.0);
    float d = remapSafe(base * heightProfile(h, w.type), 1.0 - coverage, 1.0, 0.0, 1.0);
    if (d <= 0.0) return 0.0;

    if (lod == 0) {
        vec3 q = vec3(cloudLocalXZ(scenePos, DETAIL_TILE) + fsCloudWind.zw * 1.6, y * 1.3).xzy;
        vec4 dn = texture(cloudDetailTex, q / DETAIL_TILE);
        float detail = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
        // Wispy bottoms, billowy tops.
        float erosion = mix(detail, 1.0 - detail, saturate(h * 3.0));
        d = remapSafe(d, erosion * 0.38, 1.0, 0.0, 1.0);
    }
    // Stratus layers are optically thinner; towers are denser.
    return saturate(d) * mix(0.6, 1.35, w.type) * CLOUD_DENSITY;
}

float cloudDensityAt(vec3 scenePos, int lod) {
    float h;
    return cloudDensity(scenePos, sampleWeather(scenePos), lod, h);
}

// Optical depth toward the light with exponentially growing steps (covers ~2 km).
float lightOpticalDepth(vec3 p, vec3 l, int steps) {
    float od = 0.0;
    float t = 0.0;
    float len = 28.0;
    for (int i = 0; i < steps; i++) {
        vec3 q = p + l * (t + 0.5 * len);
        od += cloudDensityAt(q, i < 2 ? 0 : 1) * len;
        t += len;
        len *= 2.1;
    }
    return od * CLOUD_EXTINCTION;
}

float cloudPhase(float cosTheta, float octave) {
    float scale = pow(0.5, octave);
    float forward = henyeyGreenstein(cosTheta, 0.78 * scale);
    float back = henyeyGreenstein(cosTheta, -0.22 * scale);
    return mix(forward, back, 0.28);
}

struct CloudResult {
    vec3  scattering;     // in-scattered radiance toward the camera
    float transmittance;
    float distance;       // transmittance-weighted mean distance of the cloud (for haze, TAA)
};

struct CloudLighting {
    vec3 lightDir;
    vec3 lightIrradiance;   // at cloud altitude
    vec3 ambientTop;        // radiance of the sky above a cloud
    vec3 ambientBottom;     // radiance from below (ground bounce)
};

vec3 lightningIrradiance(vec3 scenePos) {
    if (lightningBoltPosition.w <= 0.0) return vec3(0.0);
    vec3 bolt = lightningBoltPosition.xyz;
    bolt.y = fsCloud.z + 400.0 - cameraPosition.y; // the flash lights the cloud from inside
    float d = length(scenePos - bolt);
    return vec3(0.8, 0.85, 1.0) * 60.0 * exp(-d / 650.0);
}

CloudResult marchClouds(vec3 dir, float maxDist, float jitter, CloudLighting lit, int steps, int lightSteps) {
    CloudResult r;
    r.scattering = vec3(0.0); r.transmittance = 1.0; r.distance = 0.0;

    float slabBottom = fsCloud.z - 400.0;
    float slabTop = fsCloud.w;
    vec2 span = raySlab(cameraPosition.y, dir.y, slabBottom, slabTop);
    float t0 = span.x;
    float t1 = min(span.y, min(maxDist, CLOUD_MAX_DISTANCE));
    if (t1 <= t0) return r;

    float len = t1 - t0;
    // Adaptive step count: long horizontal paths get more steps, capped by quality.
    int n = clamp(int(len / 90.0), steps / 3, steps);
    float dt = len / float(n);
    // Two step sizes. Clear air is crossed with dt (doubled after a few empty samples). On
    // reaching cloud the march steps back over the last stride and continues inside the cloud
    // with dtIn, so cloud fronts and thin clouds are resolved finely instead of snapping to
    // the coarse grid (seen in game as stacked slices: dt ~ 140 m at 20 deg elevation).
    float dtIn = max(dt * 0.34, 10.0);
    int maxIter = n * 2;
    float cosTheta = dot(dir, lit.lightDir);
    float wSum = 0.0;
    float t = t0 + dt * jitter;
    float lastStep = dt * jitter;
    bool fine = false;
    int emptyRun = 0;

    for (int i = 0; i < maxIter; i++) {
        if (t > t1) break;
        vec3 p = dir * t;
        CloudWeather w = sampleWeather(p);
        float h;
        float coarse = cloudDensity(p, w, 1, h);
        if (coarse <= 0.0) {
            emptyRun++;
            if (fine && emptyRun > 3) fine = false;
            lastStep = fine ? dtIn : dt * (emptyRun > 2 ? 2.0 : 1.0);
            t += lastStep;
            continue;
        }
        if (!fine) {
            fine = true;
            if (lastStep > dtIn) {
                // Re-approach the entry with fine steps; tolerate the empty samples in between.
                t = max(t - lastStep + dtIn * jitter, t0);
                emptyRun = -int(ceil(lastStep / dtIn));
                lastStep = 0.0;
                continue;
            }
        }
        emptyRun = min(emptyRun, 0);
        float density = cloudDensity(p, w, 0, h);
        if (density > 0.0) {
            emptyRun = 0;
            float sigma = density * CLOUD_EXTINCTION;
            float od = lightOpticalDepth(p, lit.lightDir, lightSteps);
            vec3 direct = vec3(0.0);
            for (int o = 0; o < 3; o++) {
                float fo = float(o);
                direct += pow(0.5, fo) * cloudPhase(cosTheta, fo) * exp(-od * pow(0.45, fo));
            }
            // Powder: crevices facing away from the light lose their in-scattered light.
            float powder = 1.0 - exp(-sigma * 140.0);
            direct *= mix(1.0, powder * 1.6, 0.5 * (1.0 - cosTheta) * 0.5);
            vec3 radiance = lit.lightIrradiance * direct;
            vec3 ambient = mix(lit.ambientBottom, lit.ambientTop, saturate(h * 1.3)) * mix(0.55, 1.0, h);
            radiance += ambient + lightningIrradiance(p) * 0.08;
            float stepT = exp(-sigma * dtIn);
            // Energy-conserving integration of in-scattering over the step.
            vec3 integ = radiance * (1.0 - stepT);
            r.scattering += r.transmittance * integ;
            float wgt = r.transmittance * (1.0 - stepT);
            r.distance += t * wgt;
            wSum += wgt;
            r.transmittance *= stepT;
            if (r.transmittance < 0.01) { r.transmittance = 0.0; break; }
        }
        t += dtIn;
        lastStep = dtIn;
    }
    r.distance = wSum > 0.0 ? r.distance / wSum : t1;
    return r;
}

// Transmittance of the cloud layer along the light, for a point projected onto the cloud base
// plane. Used to build the cloud shadow map.
float cloudShadowTransmittance(vec3 basePoint, vec3 l) {
    float ly = max(l.y, 0.08);
    float pathLen = (fsCloud.w - fsCloud.z) / ly;
    float od = 0.0;
    const int N = 10;
    float dt = min(pathLen, 6000.0) / float(N);
    for (int i = 0; i < N; i++) {
        vec3 p = basePoint + l * (float(i) + 0.5) * dt;
        od += cloudDensityAt(p, 1) * dt;
    }
    return exp(-od * CLOUD_EXTINCTION * 0.75);
}

#endif

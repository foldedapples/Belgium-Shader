// Translucent terrain (water, glass, ice, slime, honey) and translucent hand items.
//   water  -> colortex6: surface normal (waves + local simulation, octahedral), sky light,
//             coverage 1. Shading happens in composite where the scene behind is known.
//   others -> colortex5: forward-lit, premultiplied, with a Fresnel sky reflection.
// Both targets blend with SRC_ALPHA / ONE_MINUS_SRC_ALPHA, so a fragment writing alpha 0 to a
// target leaves it untouched (glass never overwrites the water data behind it).
#include "/lib/core/common.glsl"
#include "/lib/core/taa_jitter.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/lighting/forward.glsl"

#ifdef STAGE_VERTEX
in vec4 mc_Entity;
out vec2 vUv;
out vec2 vLightmap;
out vec4 vColor;
out vec3 vScenePos;
out vec3 vNormal;
flat out int vMaterial;

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 lm = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vLightmap = saturate((lm - 1.0 / 32.0) * (16.0 / 15.0));
    vColor = gl_Color;
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vScenePos = viewToScene(viewPos.xyz);
    vNormal = safeNormalize(viewToSceneDir(gl_NormalMatrix * gl_Normal));
    #ifdef PROG_HAND
        vMaterial = MAT_HAND;
    #else
        vMaterial = materialFromBlockId(int(mc_Entity.x + 0.5));
    #endif
    gl_Position = gl_ProjectionMatrix * viewPos;
    applyTaaJitter(gl_Position);
}
#endif

#ifdef STAGE_FRAGMENT
#include "/lib/water/waves.glsl"
#if WATER_SOURCE == 1 && defined DIM_OVERWORLD
    #include "/lib/halcyon/halcyon_water_sim.glsl"
#else
    #include "/lib/water/water_sim_sample.glsl"
#endif
#include "/lib/water/water_record.glsl"
#include "/lib/weather/wetness.glsl"
#include "/lib/lighting/brdf.glsl"
#ifdef DIM_OVERWORLD
    #include "/lib/sky/sky_render.glsl"
#endif

uniform sampler2D gtexture;

in vec2 vUv;
in vec2 vLightmap;
in vec4 vColor;
in vec3 vScenePos;
in vec3 vNormal;
flat in int vMaterial;

/* RENDERTARGETS: 5,6 */
layout(location = 0) out vec4 outTranslucent;
layout(location = 1) out vec4 outWater;

float pixelAngularSize() { return 2.0 / max(gbufferProjection[1][1] * viewHeight, 1.0); }

void main() {
    vec3 faceN = safeNormalize(cross(dFdx(vScenePos), dFdy(vScenePos)), vNormal);
    if (dot(faceN, vNormal) < 0.0) faceN = -faceN;
    float dist = length(vScenePos);
    vec3 viewDir = vScenePos / max(dist, EPSILON);

    if (vMaterial == MAT_WATER) {
        vec3 n = faceN;
        // Only the top surface carries waves; sides of flowing water and waterfalls keep
        // their face normal (their motion is the vanilla texture animation).
        if (faceN.y > 0.5) {
            vec2 xz = cameraPosition.xz + vScenePos.xz;
            float footprint = dist * pixelAngularSize() / max(abs(viewDir.y), 0.12);
            WaveSample w = waveSurface(xz, waveTime(), waterOpenness(vLightmap.y), footprint);
            vec2 slope = w.slope;
            #if WATER_SOURCE == 1 && defined DIM_OVERWORLD
                // Halcyon's ocean swells on top of the wave spectrum, then its simulation.
                vec2 footprintAV = vec2(footprint, dist * pixelAngularSize());
                slope += halcyonSwellSlope(xz, waterOpenness(vLightmap.y), safeNormalize(viewDir.xz), footprintAV);
                #ifdef WATER_SIMULATION
                    slope += halcyonWaterSimSlope(vScenePos);
                #endif
            #elif defined WATER_SIMULATION
                SimSurface sim = sampleWaterSim(vScenePos);
                slope += sim.slope;
            #endif
            #if defined RAIN_RIPPLES && !defined DIM_NETHER
                // Halcyon's ripples are scaled for open water already; Belgium's need x2 here.
                #if RAIN_RIPPLE_SOURCE == 1
                    slope += rainRipples(cameraPosition + vScenePos, vLightmap.y);
                #else
                    slope += rainRipples(cameraPosition + vScenePos, vLightmap.y) * 2.0;
                #endif
            #endif
            n = waveNormal(slope);
            // Normals must not face away from a camera looking at the surface from above.
            if (dot(n, -viewDir) < 0.02 && viewDir.y < 0.0) n = safeNormalize(n + vec3(0.0, 0.5, 0.0));
        }
        outWater = vec4(encodeUnitVector(n), packWaterLight(vLightmap, false), 1.0);
        outTranslucent = vec4(0.0);
        return;
    }

    vec4 base = texture(gtexture, vUv) * vColor;
    if (base.a < 0.01) discard;
    vec3 albedo = srgbToLinear(base.rgb);
    vec3 n = faceN;
    vec3 v = -viewDir;
    vec3 diffuse = forwardLighting(albedo, n, vLightmap, vScenePos);
    // Clear dielectric surfaces reflect the sky (and the sun) by Fresnel.
    float F = fresnelDielectric(abs(dot(n, v)), 1.5);
    vec3 reflection = vec3(0.0);
    #ifdef DIM_OVERWORLD
        vec3 r = reflect(-v, n);
        reflection = skyRadiance(normalize(vec3(r.x, max(r.y, 0.01), r.z))) * skyVisibility(vLightmap.y);
    #endif
    // Premultiplied: body colour attenuated by what the surface reflects.
    vec3 premult = diffuse * base.a * (1.0 - F) + reflection * F;
    float coverage = 1.0 - (1.0 - base.a) * (1.0 - F);
    outTranslucent = vec4(sanitizeRadiance(premult / max(coverage, 1e-4)), coverage);
    outWater = vec4(0.0);
}
#endif

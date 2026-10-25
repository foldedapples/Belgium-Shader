// Distant Horizons translucents: water writes the water surface record (composite shades it),
// anything else is forward-lit like vanilla translucents.
#include "/lib/core/common.glsl"
#include "/lib/core/taa_jitter.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/lighting/forward.glsl"

#ifdef STAGE_VERTEX
out vec4 vColor;
out vec2 vLightmap;
out vec3 vScenePos;
out vec3 vNormal;
flat out int vIsWater;

void main() {
    vColor = gl_Color;
    vLightmap = saturate(gl_MultiTexCoord1.xy);
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vScenePos = viewToScene(viewPos.xyz);
    vNormal = safeNormalize(viewToSceneDir(gl_NormalMatrix * gl_Normal));
    #ifdef DISTANT_HORIZONS
        vIsWater = dhMaterialId == DH_BLOCK_WATER ? 1 : 0;
    #else
        vIsWater = 0;
    #endif
    gl_Position = gl_ProjectionMatrix * viewPos;
    applyTaaJitter(gl_Position);
}
#endif

#ifdef STAGE_FRAGMENT
#include "/lib/core/blue_noise.glsl"
#include "/lib/water/waves.glsl"
#include "/lib/water/water_record.glsl"

in vec4 vColor;
in vec2 vLightmap;
in vec3 vScenePos;
in vec3 vNormal;
flat in int vIsWater;

/* RENDERTARGETS: 5,6 */
layout(location = 0) out vec4 outTranslucent;
layout(location = 1) out vec4 outWater;

void main() {
    float d = length(vScenePos.xz);
    float handoff = smoothstep(far * 0.78, far * 0.92, d);
    if (handoff < blueNoiseStatic(ivec2(gl_FragCoord.xy)).x) discard;

    if (vIsWater == 1) {
        vec3 n = vNormal;
        if (n.y > 0.5) {
            // Far water: only the long waves survive the footprint filter.
            float dist = length(vScenePos);
            float footprint = dist * 2.0 / max(gbufferProjection[1][1] * viewHeight, 1.0) / max(abs(vScenePos.y / dist), 0.12);
            WaveSample w = waveSurface(cameraPosition.xz + vScenePos.xz, waveTime(), waterOpenness(vLightmap.y), footprint);
            n = waveNormal(w.slope);
        }
        outWater = vec4(encodeUnitVector(n), packWaterLight(vLightmap, false), 1.0);
        outTranslucent = vec4(0.0);
        return;
    }
    vec3 albedo = srgbToLinear(vColor.rgb);
    vec3 radiance = forwardLighting(albedo, vNormal, vLightmap, vScenePos);
    outTranslucent = vec4(sanitizeRadiance(radiance), vColor.a);
    outWater = vec4(0.0);
}
#endif

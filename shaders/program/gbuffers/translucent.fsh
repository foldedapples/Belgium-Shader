#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/tangent.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/common/gbuffer.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/material/labpbr.glsl"
#include "/lib/water/waves.glsl"
#if defined WATER_SIM && !defined GBUF_HAND_WATER
#include "/lib/common/state.glsl"
#include "/lib/water/sim_common.glsl"
uniform sampler2D waterSimSamplerA;
uniform sampler2D waterSimSamplerB;
#endif
#if defined RAIN_RIPPLES
#include "/lib/weather/ripples.glsl"
#endif

uniform sampler2D gtexture;
uniform sampler2D normals;

in vec2 vUv;
in vec2 vLightmap;
in vec4 vColor;
in vec3 vNormal;
in vec4 vTangent;
in vec3 vPlayerPos;
flat in int vId;

// colortex4: xy oct normal (player space), z packed lightmap, w packed (id, flags)
// colortex5: rgb tint (sRGB), a coverage
/* RENDERTARGETS: 4,5 */
layout(location = 0) out vec4 outSurface;
layout(location = 1) out vec4 outTint;

#if defined WATER_SIM && !defined GBUF_HAND_WATER
float simHeight(ivec2 cell) {
    ivec2 tx = simTexel(cell);
    return state.simParity == 0 ? texelFetch(waterSimSamplerA, tx, 0).r : texelFetch(waterSimSamplerB, tx, 0).r;
}

// Gradient of the simulated height field, bilinearly interpolated between cell centres.
vec2 simGradient(vec2 worldXZ) {
    vec2 g = worldXZ / SIM_DX - 0.5;
    ivec2 c = ivec2(floor(g));
    vec2 f = g - vec2(c);
    float h00 = simHeight(c), h10 = simHeight(c + ivec2(1, 0)), h01 = simHeight(c + ivec2(0, 1)), h11 = simHeight(c + ivec2(1, 1));
    float hm0 = simHeight(c + ivec2(-1, 0)), h20 = simHeight(c + ivec2(2, 0));
    float h0m = simHeight(c + ivec2(0, -1)), h02 = simHeight(c + ivec2(0, 2));
    // Central differences at the two nearest columns/rows, blended.
    float gx0 = (h10 - hm0) * 0.5, gx1 = (h20 - h00) * 0.5;
    float gy0 = (h01 - h0m) * 0.5, gy1 = (h02 - h00) * 0.5;
    vec2 grad = vec2(mix(gx0, gx1, f.x), mix(gy0, gy1, f.y));
    return grad / SIM_DX;
}
#endif

void main() {
    vec4 albedo = texture(gtexture, vUv) * vColor;
    vec3 n = normalize(vNormal);
    if (!gl_FrontFacing) n = -n;
    vec2 lm = normalizeLightmap(vLightmap);
    vec3 worldPos = vPlayerPos + cameraPosition;
    int flags = 0;
    vec3 surfaceNormal = n;

    if (vId == MAT_WATER) {
        #ifdef WATER_WAVES
        WaterParams wp = waterParamsAt(n, lm.y);
        vec3 hg = waveHeightGrad(worldPos.xz, frameTimeCounter, wp);
        vec2 grad = hg.yz;
        #else
        vec2 grad = vec2(0.0);
        #endif
        #if defined WATER_SIM && !defined GBUF_HAND_WATER
        if (state.simCenter.w > 0.5) {
            float planeW = 1.0 - saturate(abs(worldPos.y - state.simCenter.y) - 0.6);
            float w = planeW * simEdgeFade(worldPos.xz, state.simCenter.xz);
            if (w > 0.0) grad += simGradient(worldPos.xz) * w;
        }
        #endif
        #ifdef RAIN_RIPPLES
        float exposed = smoothstep(0.85, 0.97, lm.y);
        if (rainStrength * exposed > 0.01 && biomeWet > 0.0)
            grad += rainRippleGradient(worldPos.xz, frameTimeCounter) * rainStrength * exposed * biomeWet;
        #endif
        if (abs(n.y) > 0.5) {
            // Height field over the horizontal plane; fade detail at grazing distance (anti-alias).
            float dist = length(vPlayerPos);
            grad *= 1.0 / (1.0 + dist * 0.004);
            surfaceNormal = normalize(vec3(-grad.x, 1.0, -grad.y)) * sign(n.y);
        } else {
            // Side faces of flowing water: perturb along the face tangent plane only.
            vec3 t = normalize(vTangent.xyz);
            vec3 b = cross(n, t);
            surfaceNormal = normalize(n - (t * grad.x + b * grad.y) * 0.5);
        }
        #ifdef WATER_VANILLA_TEXTURE
        outTint = vec4(albedo.rgb, 1.0);
        #else
        // Keep the biome water colour (vertex tint); the texture's own pattern is replaced by waves.
        outTint = vec4(vColor.rgb, 1.0);
        #endif
    } else {
        // Glass, ice, slime, portals: optional LabPBR normal map.
        if (albedo.a < 0.004) discard;
        #ifdef NORMAL_MAPS_ACTIVE
        vec4 nt = decodeLabNormal(texture(normals, vUv), NORMAL_MAP_STRENGTH);
        surfaceNormal = normalize(textureTangentFrame(n, vPlayerPos, vUv, vTangent) * nt.xyz);
        #endif
        outTint = albedo;
    }

    #ifdef GBUF_HAND_WATER
    flags |= FLAG_HAND;
    #endif
    outSurface = vec4(octEncode(surfaceNormal), pack2x8(lm), pack2x8u(uint(vId), uint(flags)));
}

// composite2: applies the media in front of every surface: air (aerial perspective, analytic),
// the marched volumetrics (half resolution, depth-aware upsampling), clouds in front of terrain,
// render-distance fog, heat shimmer in the Nether, and the rain layer drawn by gbuffers_weather.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/state.glsl"
#include "/lib/common/transform.glsl"
#include "/lib/common/depth.glsl"
#include "/lib/material/ids.glsl"
#define ATMOSPHERE_SAMPLERS
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/sky/celestial.glsl"
#include "/lib/lighting/ambient.glsl"
#include "/lib/atmosphere/fog.glsl"
#ifdef WORLD_OVERWORLD
#include "/lib/sky/stars.glsl"
#include "/lib/sky/moon.glsl"
#include "/lib/sky/sky.glsl"
#include "/lib/clouds/clouds_common.glsl"
#endif
#ifdef WORLD_NETHER
#include "/lib/nether/nether.glsl"
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex13;
uniform sampler2D vlSampler;

in vec2 texcoord;

/*
const int colortex13Format = RGBA16F;
const bool colortex13Clear = true;
const vec4 colortex13ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
*/

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

vec4 upsampleVL(vec2 uv, float linDepth) {
    vec2 hs = vec2(textureSize(vlSampler, 0));
    vec2 p = uv * hs - 0.5;
    ivec2 b = ivec2(floor(p));
    vec2 f = p - vec2(b);
    vec4 sum = vec4(0.0);
    float ws = 0.0;
    for (int i = 0; i < 4; i++) {
        ivec2 o = ivec2(i & 1, i >> 1);
        ivec2 tc = clamp(b + o, ivec2(0), ivec2(hs) - 1);
        vec2 fuv = (vec2(tc) + 0.5) / hs;
        float d = linearizeDepth(texture(depthtex0, fuv).r, near, far * 4.0);
        float wd = exp(-abs(d - linDepth) / max(linDepth * 0.08, 0.1));
        vec2 w2 = mix(1.0 - f, f, vec2(o));
        float w = w2.x * w2.y * wd + 1e-4;
        sum += texelFetch(vlSampler, tc, 0) * w;
        ws += w;
    }
    return sum / ws;
}

void main() {
    vec2 uv = texcoord;

    #ifdef WORLD_NETHER
    #ifdef HEAT_DISTORTION
    {
        // Heat shimmer: stronger over lava and towards the bottom of the view, animated noise.
        uint idf = unpack2x8u(texture(colortex3, uv).z).x;
        float hot = (int(idf) == MAT_LAVA ? 1.0 : 0.25) * HEAT_STRENGTH;
        vec2 q = uv * vec2(aspectRatio, 1.0) * 18.0 + vec2(0.0, frameTimeCounter * 1.6);
        vec2 off = vec2(valueNoise(q) - 0.5, valueNoise(q + 7.1) - 0.5) * 0.004 * hot;
        uv = clamp(uv + off, vec2(0.0), vec2(1.0));
    }
    #endif
    #endif

    vec3 color = texture(colortex0, uv).rgb;
    SceneDepth sd = resolveDepth(uv, false, false);
    vec3 playerPos = viewToPlayer(sd.viewPos);
    float dist = sd.sky ? 1e6 : length(playerPos);
    vec3 dir = normalize(playerPos);

    #if DEBUG_VIEW == 0
    #ifdef WORLD_OVERWORLD
    SkyLights L = skyLights();
    if (!sd.sky && isEyeInWater != 1) {
        // Clouds in front of terrain (mountains in the clouds, LOD terrain beyond them).
        #ifdef VOLUMETRIC_CLOUDS
        float camAlt = cameraPosition.y - 62.0;
        float baseY = 62.0 + cloudShellBase();
        bool cloudInFront = camAlt > cloudShellBase() || (dir.y > 0.0 && (baseY - cameraPosition.y) / dir.y < dist);
        if (cloudInFront) {
            vec4 c = sampleClouds(uv);
            color = color * c.a + c.rgb;
        }
        #endif
        #ifdef VOLUMETRIC_LIGHT
        vec4 ap = aerialPerspective(dir, dist, L, false);
        #else
        vec4 ap = aerialPerspective(dir, dist, L, true);
        #endif
        color = color * ap.a + ap.rgb;
        #ifdef BORDER_FOG
        // Hide the edge of the loaded world: fade into the sky over the last 20 % of the distance.
        float farD = sd.lod ? 1e9 : far;
        #ifdef DISTANT_HORIZONS
        if (sd.lod) farD = float(dhRenderDistance);
        #endif
        #ifdef VOXY
        if (sd.lod) farD = float(vxRenderDistance) * 16.0;
        #endif
        float bf = smoothstep(farD * 0.8, farD, length(playerPos.xz)) * LOD_FADE;
        #if defined DISTANT_HORIZONS || defined VOXY
        // LOD terrain continues past the vanilla edge, so only LOD terrain fades (at its own far
        // edge). Fading vanilla terrain into the sky here showed as flat beige bands and ghost
        // blocks along the boundary (seen in game, 2026-10-26).
        if (!sd.lod) bf = 0.0;
        #endif
        if (bf > 0.0) color = mix(color, skyRadiance(dir, L, 0.01, false), saturate(bf));
        #endif
    }
    #elif defined WORLD_NETHER
    // Distance haze beyond the marched range.
    float hz = 1.0 - exp(-max(dist - 160.0, 0.0) * 0.01 * NETHER_FOG_DENSITY);
    color = mix(color, netherHazeColor() * 2.0, hz);
    #endif

    #ifdef WORLD_NETHER
    #ifdef NETHER_ASH
    // Ash: sparse specks drifting down and sideways in world space, tested layer by layer along
    // the view ray (each layer is a slab of a 3D grid of cells with at most one speck).
    {
        vec3 ash = vec3(0.0);
        for (int i = 0; i < 8; i++) {
            float layerD = 1.5 + float(i) * 2.2;
            if (layerD > dist) break;
            vec3 p = cameraPosition + dir * layerD;
            vec3 drift = vec3(frameTimeCounter * 0.25, -frameTimeCounter * 0.6, frameTimeCounter * 0.12);
            vec3 q = (p + drift) / 1.6;
            ivec3 cellI = ivec3(floor(q));
            vec4 h = hash4(cellI);
            if (h.w > 0.18) continue;
            vec3 speck = (vec3(cellI) + 0.2 + 0.6 * h.xyz) * 1.6 - drift;
            vec3 rel = speck - cameraPosition;
            float along = dot(rel, dir);
            if (along <= 0.2 || along > dist) continue;
            float perp = length(rel - dir * along);
            float size = 0.012 * (0.6 + h.y);
            float a = smoothstep(size, size * 0.3, perp);
            vec3 c = h.x > 0.85 ? vec3(1.6, 0.5, 0.1) * 0.4 : netherHazeColor() * 1.5 + 0.02;
            ash += c * a * 0.6;
        }
        color += ash;
    }
    #endif
    #endif

    #ifdef VOLUMETRIC_LIGHT
    float linD = sd.sky ? far * 4.0 : linearizeDepth(sd.depth, near, far * 4.0);
    vec4 vl = upsampleVL(uv, linD);
    color = color * vl.a + vl.rgb;
    #endif

    #ifdef WORLD_OVERWORLD
    // Lava and powder snow (eye inside) fogs.
    if (isEyeInWater == 2) color = mix(color, vec3(2.0, 0.45, 0.06), 1.0 - exp(-dist * 1.2));
    if (isEyeInWater == 3) color = mix(color, vec3(0.6, 0.7, 0.8) * 0.3, 1.0 - exp(-dist * 0.8));
    #endif

    // Rain streaks (premultiplied, drawn into colortex13 by gbuffers_weather).
    vec4 rain = texture(colortex13, uv);
    color = color * (1.0 - rain.a) + rain.rgb;

    // Blindness and darkness effects.
    color *= mix(1.0, exp(-dist * 0.5), max(blindness, darknessFactor * 0.6));
    #endif

    #if DEBUG_VIEW == 15 && defined WORLD_OVERWORLD && defined VOLUMETRIC_CLOUDS
    color = vec3(1.0 - sampleClouds(uv).a);
    #endif
    outColor = vec4(hdrSafe(color), 1.0);
}

// deferred2 - screen-space global illumination trace at half resolution (scale.deferred2).
//
// For each pixel, SSGI_RAYS cosine-distributed rays leave the surface and march a short
// distance (SSGI_RADIUS blocks) through the depth buffer. A hit gathers the sun/sky-lit
// diffuse radiance that surface had last frame (colortex14 from deferred4, reprojected), so
// bounce light carries the colour of sunlit grass or red walls onto its surroundings, and
// repeated frames give multiple bounces (each scaled by albedo < 1, so it converges).
// Block light and emission are not in colortex14: the vanilla lightmap already spreads them.
// A hit also blocks the environment light that direction would have delivered, so each hit
// adds L_hit - L_env(dir). With cosine-weighted directions E = pi * mean(difference).
// Output: signed irradiance correction (rgb) and the fraction of rays that hit (a).
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/blue_noise.glsl"
#include "/lib/material/gbuffer.glsl"
#include "/lib/lighting/surface.glsl"
#ifdef DIM_NETHER
    #include "/lib/nether/nether_atmosphere.glsl"
#endif

uniform sampler2D colortex2;
uniform sampler2D colortex4;
uniform sampler2D colortex14;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 12 */
layout(location = 0) out vec4 outGi;

void main() {
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * 0.5);
    outGi = vec4(0.0);
    #ifdef SSGI
    if (any(greaterThan(uv, vec2(1.0)))) return;
    ivec2 fullPx = ivec2(uv * vec2(viewWidth, viewHeight));
    float depth = texelFetch(depthtex0, fullPx, 0).r;
    if (depth >= 1.0) return;
    vec4 t4 = texelFetch(colortex4, fullPx, 0);
    int flags = decodeByte(t4.a);
    if ((flags & (GB_FLAG_HAND | GB_FLAG_LOD)) != 0) return;   // no reliable depth to trace against
    if (!frameStateValid()) return;
    float skyVis = dimensionSkyVisibility(t4.g);

    vec3 viewPos = screenToView(uv, depth);
    vec3 n = sceneToViewDir(decodeUnitVector(texelFetch(colortex2, fullPx, 0).ba));
    mat3 basis = basisFromNormal(n);
    vec4 noise = blueNoise(ivec2(gl_FragCoord.xy));
    // Start slightly off the surface so the first step does not hit itself.
    vec3 origin = viewPos + n * (0.02 + 0.002 * length(viewPos));

    vec3 sum = vec3(0.0);
    float hits = 0.0;
    for (int r = 0; r < SSGI_RAYS; r++) {
        vec2 xi = fract(noise.xy + r2Sequence(r + 1));
        float phi = TAU * xi.x;
        float sinT = sqrt(xi.y), cosT = sqrt(1.0 - xi.y);
        vec3 dir = basis * vec3(cos(phi) * sinT, sin(phi) * sinT, cosT);
        // Exponentially growing steps: fine near the surface (contact bounce), long reach.
        float t = 0.0;
        float stepLen = SSGI_RADIUS / (exp2(float(SSGI_STEPS) * 0.25) * 4.0);
        for (int i = 0; i < SSGI_STEPS; i++) {
            t += stepLen * (1.0 + noise.z);
            stepLen *= 1.1892; // 2^(1/4)
            if (t > SSGI_RADIUS) break;
            vec3 p = origin + dir * t;
            if (p.z > -near) break;
            vec3 s = viewToScreen(p);
            if (any(lessThan(s.xy, vec2(0.0))) || any(greaterThan(s.xy, vec2(1.0)))) break;
            float d = texture(depthtex0, s.xy).r;
            if (d >= 1.0) continue;
            float sceneZ = screenToView(s.xy, d).z;
            float diff = sceneZ - p.z;          // > 0: the depth buffer is in front of the ray
            if (diff > 0.02 && diff < max(0.5, stepLen * 2.0)) {
                // Only surfaces facing the ray emit toward us.
                ivec2 hp = ivec2(s.xy * vec2(viewWidth, viewHeight));
                vec3 hn = sceneToViewDir(decodeUnitVector(texelFetch(colortex2, hp, 0).ba));
                int hitFlags = decodeByte(texelFetch(colortex4, hp, 0).a);
                // The hand moves with the camera and LODs are not in colortex14: treat as misses.
                if ((hitFlags & (GB_FLAG_HAND | GB_FLAG_LOD)) != 0) break;
                if (dot(hn, -dir) > 0.0) {
                    vec3 hitScene = viewToScene(screenToView(s.xy, d));
                    vec2 prevUv = reprojectScene(hitScene).xy;
                    if (all(greaterThan(prevUv, vec2(0.0))) && all(lessThan(prevUv, vec2(1.0)))) {
                        vec3 dirScene = viewToSceneDir(dir);
                        #ifdef DIM_NETHER
                            vec3 envL = netherAmbientIrradiance(dirScene) * INV_PI;
                        #else
                            vec3 envL = skyIrradiance(dirScene) * skyVis * INV_PI;
                        #endif
                        sum += sanitizeRadiance(texture(colortex14, prevUv).rgb) - envL;
                        hits += 1.0;
                    }
                }
                break;
            }
        }
    }
    vec3 irradiance = PI * sum / float(SSGI_RAYS);
    // Guard against fireflies from tiny bright hits (the sun's disk seen in a reflection etc.).
    irradiance = clamp(irradiance, vec3(-32.0), vec3(32.0));
    outGi = vec4(irradiance, hits / float(SSGI_RAYS));
    #endif
}
#endif

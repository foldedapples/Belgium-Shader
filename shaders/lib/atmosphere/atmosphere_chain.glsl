#ifndef ATMOSPHERE_CHAIN_GLSL
#define ATMOSPHERE_CHAIN_GLSL
// The atmosphere applied between the camera and a surface, per dimension. Deferred lighting
// and composite must apply exactly the same chain, and composite also needs to *remove* it
// (refraction) or attenuate added light by it (reflections). Every step is affine in the
// input colour, c -> c*T + S, so T and S follow from evaluating the chain at 0 and 1.
// Requires the dimension's sky/fog modules to be included first.
#include "/lib/compat/lod.glsl"

vec3 applyAtmosphere(vec3 c, vec3 scenePos, float dist, vec3 dir) {
    #if defined DIM_OVERWORLD
        c = aerialPerspective(c, scenePos, dist);
        c = borderFog(c, scenePos, dist, terrainRenderDistance());
        c = applyHeightFog(c, dir, dist, fsSkyIrradianceUp.rgb, fsLightColor.rgb * cloudShadow(vec3(0.0)), fsLightDir.xyz);
    #elif defined DIM_END
        c = endFog(c, scenePos, dist);
    #else
        c = netherFog(c, scenePos, dist);
    #endif
    return c;
}

void atmosphereTerms(vec3 scenePos, float dist, vec3 dir, out vec3 T, out vec3 S) {
    S = applyAtmosphere(vec3(0.0), scenePos, dist, dir);
    T = applyAtmosphere(vec3(1.0), scenePos, dist, dir) - S;
}

#endif

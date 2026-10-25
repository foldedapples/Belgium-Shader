#ifndef HALCYON_WATER_LIGHT_GLSL
#define HALCYON_WATER_LIGHT_GLSL
// Halcyon's caustics (refraction Jacobian of its caustic wave set and swells) and underwater
// sun shafts (Water Source = Halcyon), on Belgium's water medium and shadow map. Requires
// lib/water/water_params.glsl and lib/lighting/shadow_space.glsl; the shafts are compiled when
// HALCYON_UW_SHAFTS is defined (the volumetric-light pass).
#include "/lib/halcyon/adapter_core.glsl"

// The water medium Halcyon's shafts integrate through: Belgium's, so shafts and Belgium's
// underwater fog agree (Underwater Fog scales the density as in Halcyon).
vec3 uwExtinction() { return waterExtinction() * UNDERWATER_FOG; }
vec3 uwScattering() { return waterScattering(); }
// Camera depth below the water surface: the water plane Belgium's water state tracks; Halcyon's
// sky-light estimate when no plane is known.
float uwCameraDepth() {
    #ifdef HALCYON_HAS_WATER_PLANE
        if (wsHeader.x == WS_VERSION) return max(wsPlane.x - cameraPosition.y, 0.0) + 0.5;
    #endif
    return (1.0 - float(eyeBrightnessSmooth.y) / 240.0) * 15.0 + 0.5;
}
vec3 getShadowClipPos(vec3 scenePos) { return sceneToShadowClip(scenePos); }
vec3 getShadowScreenPos(vec3 clip) { return shadowClipToTexture(clip); }

#include "/lib/halcyon/hc_begin.glsl"
#include "/lib/halcyon/adapter_region.glsl"
#include "/lib/halcyon/water/halcyon_waterfog.glsl"
#include "/lib/halcyon/water/caustics.glsl"
#ifdef HALCYON_UW_SHAFTS
    #include "/lib/halcyon/water/underwaterShafts.glsl"
#endif

// Light focusing factor (1 = none) for a point lit through `pathInWater` blocks of water.
float halcyonCaustics(vec3 worldPos, vec3 lightDir, float pathInWater, float camDist) {
    #ifdef CAUSTICS
        return proceduralCaustics(worldPos, lightDir, pathInWater, camDist);
    #else
        return 1.0;
    #endif
}
#ifdef HALCYON_UW_SHAFTS
// In-scattered sunlight along a view ray (view-space end point) seen from under water.
vec3 halcyonUnderwaterShafts(vec3 viewPos, float jitter) { return underwaterSunShafts(viewPos, jitter); }
#endif

#include "/lib/halcyon/adapter_region_end.glsl"
#include "/lib/halcyon/hc_end.glsl"
#endif

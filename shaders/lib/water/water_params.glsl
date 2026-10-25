#ifndef WATER_PARAMS_GLSL
#define WATER_PARAMS_GLSL
#include "/lib/core/common.glsl"
#include "/lib/post/color_profile.glsl"

// Optical properties of water per block (= metre).
// Absorption of pure water at 680/550/440 nm is about (0.45, 0.064, 0.015) /m; natural water
// adds particulate scattering and some yellow-substance absorption. Presets scale these.

const float WATER_IOR = 1.333;

#if WATER_STYLE == 0       // clear ocean
    const vec3 WATER_ABSORPTION = vec3(0.42, 0.075, 0.028);
    const vec3 WATER_SCATTERING = vec3(0.010, 0.016, 0.020);
#elif WATER_STYLE == 1     // coastal / temperate
    const vec3 WATER_ABSORPTION = vec3(0.46, 0.11, 0.075);
    const vec3 WATER_SCATTERING = vec3(0.028, 0.040, 0.038);
#elif WATER_STYLE == 2     // tropical lagoon
    const vec3 WATER_ABSORPTION = vec3(0.40, 0.055, 0.050);
    const vec3 WATER_SCATTERING = vec3(0.018, 0.035, 0.034);
#else                      // murky lake
    const vec3 WATER_ABSORPTION = vec3(0.55, 0.28, 0.30);
    const vec3 WATER_SCATTERING = vec3(0.06, 0.07, 0.05);
#endif

vec3 waterExtinction() { return (WATER_ABSORPTION + WATER_SCATTERING) * WATER_DENSITY; }
// The colour profile's water response scales only the in-scattered colour (turquoise
// shallows, richer blue depths); extinction, so clarity and depth darkening, stays physical.
vec3 waterScattering() { return WATER_SCATTERING * WATER_DENSITY * CP_WATER_COLOR; }
vec3 waterAlbedo() { return waterScattering() / max(waterExtinction(), vec3(1e-5)); }

// In-scattered radiance along a water path of length d whose medium is lit by irradiance
// `ambientE` (already attenuated to the path's depth). Isotropic phase, single scattering.
vec3 waterInscatter(vec3 ambientE, float d) {
    vec3 ext = waterExtinction();
    return ambientE * (0.25 * INV_PI) * waterAlbedo() * (1.0 - exp(-ext * d));
}

#endif

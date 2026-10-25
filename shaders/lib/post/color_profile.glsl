#ifndef POST_COLOR_PROFILE_GLSL
#define POST_COLOR_PROFILE_GLSL
// Colour profiles (COLOR_PROFILE). Each profile is a set of controls applied where they belong
// physically rather than as a screen filter:
//   CP_SUN_WARMTH      sun spectrum (begin.csh): warmer sunlight for sky, clouds and terrain
//   CP_SKY_TINT        sky irradiance tint toward blue (ambient in shade)
//   CP_SHADOW_COLOR    saturation of sky irradiance: colour separation between sun and shade
//   CP_BLOCK_LIGHT     intensity of block and hand light
//   CP_LIGHT_SATURATION saturation of coloured block light
//   CP_GI_SATURATION   saturation of screen-space bounce light
//   CP_REFLECTION      environment / screen-space reflection strength (energy-capped)
//   CP_WATER_COLOR     scattering response of water (turquoise shallows, depth colour)
//   CP_CLOUD_LIGHT     sunlight reaching clouds
//   CP_AURORA          aurora brightness multiplier
//   CP_SATURATION / CP_VIBRANCE / CP_CONTRAST / CP_TONEMAP   final grade only
// CUSTOM (4) reads the individual options.

#if COLOR_PROFILE == 0          // Natural: photographic, restrained
    #define CP_SUN_WARMTH 0.0
    #define CP_SKY_TINT 0.0
    #define CP_SHADOW_COLOR 1.0
    #define CP_BLOCK_LIGHT 1.0
    #define CP_LIGHT_SATURATION 1.0
    #define CP_GI_SATURATION 1.0
    #define CP_REFLECTION 1.0
    #define CP_WATER_COLOR 1.0
    #define CP_CLOUD_LIGHT 1.0
    #define CP_AURORA 1.0
    #define CP_SATURATION 0.96
    #define CP_VIBRANCE 1.0
    #define CP_CONTRAST 1.02
    #define CP_TONEMAP 0
#elif COLOR_PROFILE == 1        // Vibrant (default): rich but believable
    #define CP_SUN_WARMTH 0.15
    #define CP_SKY_TINT 0.1
    #define CP_SHADOW_COLOR 1.15
    #define CP_BLOCK_LIGHT 1.15
    #define CP_LIGHT_SATURATION 1.15
    #define CP_GI_SATURATION 1.15
    #define CP_REFLECTION 1.0
    #define CP_WATER_COLOR 1.1
    #define CP_CLOUD_LIGHT 1.05
    #define CP_AURORA 1.25
    #define CP_SATURATION 1.04
    #define CP_VIBRANCE 1.15
    #define CP_CONTRAST 1.06
    #define CP_TONEMAP 0
#elif COLOR_PROFILE == 2        // Cinematic: contrast and warm/cool separation
    #define CP_SUN_WARMTH 0.28
    #define CP_SKY_TINT 0.18
    #define CP_SHADOW_COLOR 1.3
    #define CP_BLOCK_LIGHT 1.1
    #define CP_LIGHT_SATURATION 1.1
    #define CP_GI_SATURATION 1.0
    #define CP_REFLECTION 1.0
    #define CP_WATER_COLOR 1.0
    #define CP_CLOUD_LIGHT 1.1
    #define CP_AURORA 1.0
    #define CP_SATURATION 0.98
    #define CP_VIBRANCE 1.1
    #define CP_CONTRAST 1.12
    #define CP_TONEMAP 1
#elif COLOR_PROFILE == 3        // Fantasy: stylised but energy-bounded
    #define CP_SUN_WARMTH 0.2
    #define CP_SKY_TINT 0.28
    #define CP_SHADOW_COLOR 1.4
    #define CP_BLOCK_LIGHT 1.4
    #define CP_LIGHT_SATURATION 1.35
    #define CP_GI_SATURATION 1.35
    #define CP_REFLECTION 1.1
    #define CP_WATER_COLOR 1.3
    #define CP_CLOUD_LIGHT 1.15
    #define CP_AURORA 2.0
    #define CP_SATURATION 1.15
    #define CP_VIBRANCE 1.25
    #define CP_CONTRAST 1.05
    #define CP_TONEMAP 2
#else                           // Custom
    #define CP_SUN_WARMTH SUN_WARMTH
    #define CP_SKY_TINT SKY_LIGHT_TINT
    #define CP_SHADOW_COLOR SHADOW_COLOR_INFLUENCE
    #define CP_BLOCK_LIGHT COLORED_LIGHT_INTENSITY
    #define CP_LIGHT_SATURATION COLORED_LIGHT_SATURATION
    #define CP_GI_SATURATION INDIRECT_SATURATION
    #define CP_REFLECTION REFLECTION_INTENSITY
    #define CP_WATER_COLOR WATER_COLOR_RESPONSE
    #define CP_CLOUD_LIGHT CLOUD_LIGHT_INTENSITY
    #define CP_AURORA 1.0
    #define CP_SATURATION SATURATION
    #define CP_VIBRANCE VIBRANCE
    #define CP_CONTRAST CONTRAST
    #define CP_TONEMAP TONEMAP
#endif

// Saturation about luminance, used by the stages above (keeps luminance, so energy is kept).
vec3 cpSaturate(vec3 c, float s) {
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    vec3 r = max(vec3(l) + (c - vec3(l)) * s, vec3(0.0));
    // Clamping negative channels adds luminance; scale it back out.
    float lr = dot(r, vec3(0.2126, 0.7152, 0.0722));
    return lr > 1e-6 ? r * (l / lr) : r;
}

#endif

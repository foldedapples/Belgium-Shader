#ifndef MERIDIAN_SETTINGS
#define MERIDIAN_SETTINGS

// User options. Iris rewrites these lines from the settings menu; every option here is listed on
// a screen in shaders.properties and described in lang/en_us.lang. Value lists must contain the
// default. Profiles (LOW..CINEMATIC) are defined in shaders.properties.

/*---------------------------------------------------------------- General / colour */
#define COLOR_PROFILE 1 // [0 1 2 3 4 5]
#define TONEMAP 0 // [0 1 2]
#define EXPOSURE_BIAS 0.0 // [-2.0 -1.5 -1.0 -0.5 0.0 0.5 1.0 1.5 2.0]
#define AUTO_EXPOSURE // Automatic Exposure
#define ADAPTATION_SPEED 1.0 // [0.25 0.5 1.0 2.0 4.0]
#define NIGHT_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define PURKINJE // Night Vision Colour
#define BLOOM // Bloom
#define BLOOM_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
#define VIGNETTE 0.0 // [0.0 0.1 0.2 0.3 0.4 0.5]
#define CUSTOM_SATURATION 1.0 // [0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4]
#define CUSTOM_VIBRANCE 0.0 // [-0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4]
#define CUSTOM_CONTRAST 1.0 // [0.8 0.9 1.0 1.1 1.2 1.3]
#define CUSTOM_WHITE_BALANCE 6500 // [4500 5000 5500 6000 6500 7000 7500 8000 9000]
#define CUSTOM_SHADOW_TINT 0.0 // [-0.3 -0.2 -0.1 0.0 0.1 0.2 0.3]

/*---------------------------------------------------------------- Lighting */
#define SUN_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define MOON_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define SKY_LIGHT_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define BLOCKLIGHT_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define BLOCKLIGHT_TEMPERATURE 2900 // [2000 2300 2600 2900 3200 3600 4000 5000]
#define CAVE_MIN_LIGHT 0.5 // [0.0 0.25 0.5 1.0 2.0]
#define HAND_LIGHT // Held Light
#define SUBSURFACE_SCATTERING // Subsurface Scattering
#define AMBIENT_OCCLUSION // Ambient Occlusion
#define AO_STRENGTH 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5]

/*---------------------------------------------------------------- Shadows */
const int shadowMapResolution = 4096; // [2048 3072 4096 6144 8192]
const float shadowDistance = 160.0; // [96.0 128.0 160.0 192.0 224.0 256.0]
#define SHADOW_FILTER 2 // [0 1 2]
#define SHADOW_SAMPLES 12 // [4 8 12 16 24 32]
#define SHADOW_SOFTNESS 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define CONTACT_SHADOWS // Contact Shadows
#define COLORED_SHADOWS // Coloured Shadows
#define CLOUD_SHADOWS // Cloud Shadows

/*---------------------------------------------------------------- LabPBR */
#define PBR_MODE 1 // [0 1]
#define HARDCODED_MATERIALS // Built-in Materials
#define NORMAL_MAPPING // Normal Maps
#define NORMAL_MAP_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5]
//#define NORMAL_MAP_Y_FLIP // Flip Normal Map Green
#define PARALLAX_OCCLUSION // Parallax Depth
#define POM_DEPTH 0.25 // [0.05 0.1 0.15 0.2 0.25 0.3 0.4]
#define POM_SAMPLES 32 // [8 16 24 32 48 64]
#define POM_SELF_SHADOW // Parallax Self-Shadowing
#define EMISSION_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0 4.0]

/*---------------------------------------------------------------- Reflections */
#define SSR // Screen-Space Reflections
#define SSR_STEPS 24 // [12 16 24 32 48 64]
#define SSR_MAX_ROUGHNESS 0.55 // [0.2 0.3 0.4 0.55 0.7 0.85 1.0]
#define SKY_REFLECTIONS // Sky Reflections

/*---------------------------------------------------------------- Indirect lighting */
#define COLORED_LIGHTING // Coloured Light
#define CL_VOLUME 1 // [0 1 2]
#define CL_ITERATIONS 2 // [1 2 3 4]
#define CL_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define INDIRECT_SUN // Bounced Sunlight
#define RSM_SAMPLES 12 // [6 8 12 16 24 32]
#define INDIRECT_SUN_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]

/*---------------------------------------------------------------- Water */
#define WATER_WAVES // Waves
#define WAVE_HEIGHT 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define WAVE_SPEED 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define WATER_REFRACTION // Refraction
#define WATER_CLARITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define WATER_CAUSTICS // Caustics
//#define WATER_VANILLA_TEXTURE // Vanilla Water Texture
#define WATER_SIM // Interactive Water
#define WATER_SIM_RES 1 // [0 1 2]
#define WATER_SIM_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]

/*---------------------------------------------------------------- Clouds */
#define VOLUMETRIC_CLOUDS // Volumetric Clouds
#define CLOUD_QUALITY 2 // [0 1 2 3]
#define CLOUD_RES 2 // [1 2 4]
#define CLOUD_COVERAGE 0.45 // [0.2 0.3 0.4 0.45 0.5 0.6 0.7 0.8]
#define CLOUD_ALTITUDE 1400 // [800 1000 1200 1400 1700 2000 2500]
#define CLOUD_SPEED 1.0 // [0.0 0.25 0.5 1.0 1.5 2.0 3.0]
#define CIRRUS_CLOUDS // Cirrus Clouds
#define CIRRUS_AMOUNT 1.0 // [0.0 0.5 1.0 1.5 2.0]

/*---------------------------------------------------------------- Atmosphere */
#define HAZE_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define AERIAL_PERSPECTIVE 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0 4.0]
#define VOLUMETRIC_LIGHT // Light Shafts
#define VL_STEPS 12 // [6 8 12 16 24 32]
#define VL_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define BORDER_FOG // Edge Fog

/*---------------------------------------------------------------- Weather */
#define RAIN_STREAKS // Realistic Rain
#define RAIN_OPACITY 0.45 // [0.15 0.3 0.45 0.6 0.8 1.0]
#define RAIN_WIND_LEAN 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define WET_SURFACES // Wet Surfaces
#define PUDDLES // Puddles
#define PUDDLE_AMOUNT 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define RAIN_RIPPLES // Rain Ripples
#define LIGHTNING_FLASH // Lightning Flashes

/*---------------------------------------------------------------- Moon and stars */
#define MOON_TEXTURE 1 // [0 1 2]
#define MOON_SIZE 2.0 // [1.0 1.5 2.0 2.5 3.0 4.0]
#define SUN_SIZE 1.5 // [1.0 1.5 2.0 2.5 3.0]
#define STARS // Stars
#define STAR_BRIGHTNESS 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define MILKY_WAY // Milky Way
#define MILKY_WAY_BRIGHTNESS 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define ECLIPSES // Eclipses
#define EARTHSHINE // Earthshine

/*---------------------------------------------------------------- The End */
#define END_SPACE // Deep Space Sky
#define BLACK_HOLE // Black Hole
#define BH_SIZE 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define BH_DISK_BRIGHTNESS 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define BH_LENSING_STEPS 48 // [24 32 48 64 96]
#define END_PLANETS // Planets
#define END_NEBULAE // Nebulae
#define END_LIGHT_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]

/*---------------------------------------------------------------- The Nether */
#define NETHER_FOG_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define NETHER_SMOKE // Moving Smoke
#define HEAT_DISTORTION // Heat Shimmer
#define HEAT_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0]
#define NETHER_ASH // Ash

/*---------------------------------------------------------------- Distant terrain */
#define LOD_FADE 1.0 // [0.5 0.75 1.0 1.5 2.0]

/*---------------------------------------------------------------- Performance */
#define TAA // Temporal Anti-Aliasing
#define TAA_SHARPNESS 0.4 // [0.0 0.2 0.4 0.6 0.8]

/*---------------------------------------------------------------- Debug */
#define DEBUG_VIEW 0 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20]

/*---------------------------------------------------------------- Derived switches */
// Iris's option scanner lists a toggle only when some #ifdef/#ifndef tests it directly, so
// combinations are spelled out here with nested #ifdef and the code tests the derived name.
#ifdef CLOUD_SHADOWS
#ifdef VOLUMETRIC_CLOUDS
#define CLOUD_SHADOWS_ACTIVE
#endif
#endif
#ifdef NORMAL_MAPPING
#if PBR_MODE == 1
#define NORMAL_MAPS_ACTIVE
#endif
#endif
#ifdef PARALLAX_OCCLUSION
#if PBR_MODE == 1
#define PARALLAX_ACTIVE
#endif
#endif

#endif

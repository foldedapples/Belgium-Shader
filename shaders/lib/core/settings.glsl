#ifndef CORE_SETTINGS_GLSL
#define CORE_SETTINGS_GLSL
// Every user-visible option lives in this file, written in Iris' option syntax: a define with
// a bracketed choice list is a multi-value option; a bare define (optionally commented out)
// followed by a comment is an on/off toggle.
// tools/validate.py checks every option is in a menu screen and has a language string.

// ---------------------------------------------------------------- Lighting ----------------
#define BLOCKLIGHT_TEMPERATURE 2600 // [1800 2000 2200 2400 2600 2800 3000 3400 4000]
#define BLOCKLIGHT_INTENSITY 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define EMISSION_INTENSITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0]
#define AMBIENT_FLOOR 1.0 // [0.0 0.25 0.5 1.0 2.0 4.0 8.0]
#define SKYLIGHT_INTENSITY 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define SUBSURFACE_SCATTERING // Light passing through leaves, grass and LabPBR SSS materials.
#define COLORED_LIGHTING // Block light takes the colour of nearby light sources (lava, soul fire, redstone...).
#define SSAO // Screen-space ambient occlusion in creases and under small objects.
#define SSAO_SAMPLES 8 // [4 6 8 12 16]
#define SSAO_STRENGTH 0.8 // [0.25 0.5 0.8 1.0]
#define CONTACT_SHADOWS // Short screen-space shadows that catch detail below shadow-map resolution.
#define SSGI // Screen-space bounce light: coloured indirect light from nearby lit and emissive surfaces.
#define SSGI_RAYS 1 // [1 2 4]
#define SSGI_STEPS 12 // [8 12 16 24]
#define SSGI_RADIUS 6.0 // [2.0 4.0 6.0 8.0 12.0]
#define SSGI_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define SSGI_TEMPORAL 0.15 // [0.08 0.12 0.15 0.25 0.5]
#define HAND_LIGHT // Held light sources light the world in their own colour.
#define BLOCK_LIGHT_SPECULAR // Torches, lava and lamps give highlights on smooth, wet and metal surfaces.

// ---------------------------------------------------------------- Shadows -----------------
const int shadowMapResolution = 3072; // [1024 1536 2048 3072 4096 6144 8192]
const float shadowDistance = 160.0; // [64.0 96.0 128.0 160.0 192.0 256.0 320.0 384.0 512.0]
const float shadowDistanceRenderMul = 1.0;
const float entityShadowDistanceMul = 1.0;
#define SHADOW_FILTER 3 // [0 1 2 3 4]
#define SHADOW_SOFTNESS 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define SHADOW_DISTORTION 0.12 // [0.05 0.08 0.1 0.12 0.15 0.2 0.3]
#define SHADOW_ANCHOR_RADIUS 4.0 // [0.0 2.0 4.0 6.0 8.0 12.0]
#define COLORED_SHADOWS // Stained glass and other translucent blocks tint the light passing through them.

// ---------------------------------------------------------------- Materials ---------------
#define NORMAL_MAPPING // Use resource-pack normal maps (LabPBR _n).
#define SPECULAR_MAPPING // Use resource-pack specular maps (LabPBR _s).
#define VANILLA_METALS // Without a PBR pack, give iron/gold/copper/netherite blocks a metallic response.
#define WAVING_PLANTS // Grass, flowers, crops and leaves sway in the wind.
#define WAVING_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define PARALLAX // Parallax occlusion mapping from resource-pack height maps (LabPBR _n alpha).
#define PARALLAX_DEPTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define PARALLAX_SAMPLES 24 // [8 16 24 32 48 64]
#define PARALLAX_DISTANCE 24.0 // [8.0 16.0 24.0 32.0 48.0]

// ---------------------------------------------------------------- Sun, moon, eclipses -----
const float sunPathRotation = -25.0; // [-60.0 -50.0 -40.0 -30.0 -25.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0]
#define BE_SUN_SIZE 1.0 // [0.53 0.75 1.0 1.25 1.5 2.0 3.0]
#define BE_MOON_SIZE 1.05 // [0.5 0.75 1.0 1.05 1.25 1.5 2.0 3.0]
#define MOON_INCLINATION 5.1 // [1.5 2.5 3.5 5.1 7.0 10.0]
#define ECLIPSE_CYCLE_DAYS 48 // [16 24 32 48 64 96 160 240]
#define ECLIPSE_SLOWDOWN 0.85 // [0.0 0.5 0.7 0.85 0.9]
#define BE_ECLIPSE_PREVIEW 0 // [0 1 2 3 4]
#define MOON_TEXTURE 2 // [0 1 2 3]
#define MOON_BRIGHTNESS 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define MOON_RELIEF 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define MOON_SHARPNESS_BIAS 0.0 // [-1.0 -0.5 0.0 0.5 1.0]

// ---------------------------------------------------------------- Night sky ---------------
#define NIGHT_SKY_BRIGHTNESS 20.0 // [1.0 5.0 10.0 20.0 40.0 80.0]
#define BE_STAR_DENSITY 1 // [1 2]
#define STAR_TWINKLE // Stars scintillate slightly, more strongly near the horizon.
#define MILKY_WAY_BRIGHTNESS 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define MILKY_WAY_TEXTURE // Use NASA's Deep Star Maps 2020 Milky Way (real structure, dust lanes, Magellanic Clouds) instead of the procedural band.

// ---------------------------------------------------------------- Atmosphere --------------
#define AERIAL_PERSPECTIVE 8.0 // [0.0 2.0 4.0 8.0 12.0 16.0 24.0]

// ---------------------------------------------------------------- End / Nether ------------
#define END_BH_AZIMUTH 35.0 // [0.0 35.0 90.0 145.0 180.0 225.0 270.0 315.0]
#define END_BH_ELEVATION 24.0 // [8.0 16.0 24.0 32.0 45.0 60.0]
#define END_LIGHT_INTENSITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define END_FOG_DENSITY 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define NETHER_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define NETHER_FOG_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]

// ---------------------------------------------------------------- Clouds ------------------
#define VOLUMETRIC_CLOUDS // Raymarched 3-D clouds you can fly through.
#define CLOUD_QUALITY 2 // [0 1 2 3 4 5]
#define CLOUD_RES 0.5 // [0.25 0.5 0.75 1.0]
#define CLOUD_COVERAGE 0.45 // [0.1 0.2 0.3 0.4 0.45 0.5 0.6 0.7 0.8 0.9]
#define CLOUD_DAILY_VARIATION 0.35 // [0.0 0.15 0.25 0.35 0.5]
#define CLOUD_DENSITY 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define CLOUD_TYPE_BIAS 0.0 // [-0.3 -0.15 0.0 0.15 0.3]
#define CLOUD_ALTITUDE 900.0 // [400.0 600.0 900.0 1200.0 1600.0 2000.0]
#define CLOUD_WIND_SPEED 9.0 // [0.0 3.0 6.0 9.0 14.0 20.0]
#define CLOUD_MAX_DISTANCE 24000.0 // [8000.0 12000.0 16000.0 24000.0 32000.0]
#define CLOUD_SHADOWS // Clouds shade the ground below them.
#define CLOUD_SHADOW_RES 512 // [256 512 1024]
#define CLOUD_SHADOW_RANGE 4096.0 // [2048.0 4096.0 8192.0]
#define CIRRUS_AMOUNT 0.5 // [0.0 0.25 0.5 0.75 1.0]

// ---------------------------------------------------------------- Weather -----------------
#define WETNESS // Rain wets surfaces: porous blocks darken, smooth ones get a water film.
#define PUDDLES // Puddles form on flat open ground while it rains.
#define PUDDLE_AMOUNT 0.6 // [0.2 0.4 0.6 0.8 1.0]
#define RAIN_RIPPLES // Raindrop ripples on puddles and water.
#define RAINBOW_BRIGHTNESS 1.0 // [0.0 0.5 0.75 1.0 1.5 2.0 3.0]
#define LIGHTNING_BRIGHTNESS 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define MORNING_FOG 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define WEATHER_FOG 1.0 // [0.0 0.5 1.0 1.5 2.0]

// ---------------------------------------------------------------- Volumetric light --------
#define VOLUMETRIC_LIGHT // Light shafts through fog, rain haze and under water.
#define VL_STEPS 16 // [8 12 16 24 32]
#define VL_DISTANCE 160.0 // [64.0 96.0 128.0 160.0 256.0]
#define VL_WATER_DISTANCE 48.0 // [24.0 32.0 48.0 64.0]
#define VL_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define VOLUMETRIC_FOG_BASELINE 1.0 // [0.0 0.5 1.0 2.0 4.0]

// ---------------------------------------------------------------- Aurora ------------------
#define AURORA // Auroras on some nights, toward the north.
#define BE_AURORA_FREQUENCY 0.2 // [0.05 0.1 0.2 0.35 0.5 1.0]
#define AURORA_BRIGHTNESS 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define AURORA_SPEED 1.0 // [0.25 0.5 1.0 2.0 3.0]
#define AURORA_HIGH_EMISSION 1.0 // [0.0 0.5 1.0 2.0 3.0]
#define AURORA_STEPS 24 // [12 16 24 32 48]

// ---------------------------------------------------------------- End black hole ----------
#define END_BLACK_HOLE // A lensing black hole with an accretion disk dominates the End sky.
#define BH_QUALITY 1 // [0 1 2]
#define BH_SIZE 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define BH_DISK_TILT 10.0 // [0.0 4.0 7.0 10.0 15.0 25.0 40.0]
#define BH_DISK_ROLL 0.0 // [-30.0 -15.0 0.0 15.0 30.0]
#define BH_DISK_OUTER 14.0 // [8.0 10.0 14.0 18.0 24.0]
#define BH_DISK_TEMPERATURE 9000.0 // [4000.0 6000.0 9000.0 12000.0 16000.0]
#define BH_DISK_BRIGHTNESS 1.0 // [0.25 0.5 1.0 1.5 2.0 3.0]
#define BH_ROTATION_SPEED 1.0 // [0.0 0.5 1.0 2.0 3.0]
#define BH_DOPPLER // Relativistic beaming: the approaching side of the disk is brighter and bluer.
#define END_STAR_BRIGHTNESS 1.0 // [0.25 0.5 1.0 2.0 4.0]
#define END_NEBULA_BRIGHTNESS 1.0 // [0.0 0.5 1.0 2.0 3.0]
#define END_PLANETS // Three planets orbit slowly across the End sky, lit by the accretion disk.
#define END_BH_DRIFT // The black hole (and the End's light and shadows) drifts slowly around its set position.


// ---------------------------------------------------------------- Halcyon sky ------------
// Sky Source: 1 = Halcyon's sky (lib/halcyon, the default), 0 = Belgium's (lib/sky).
#define SKY_SOURCE 1 // [0 1]
// Rain Ripple Source: 1 = Halcyon's ripples (lib/halcyon/water/rainRipples.glsl), 0 = Belgium's.
#define RAIN_RIPPLE_SOURCE 1 // [0 1]
// Cloud Source: 1 = Halcyon's volumetric clouds (lib/halcyon), 0 = Belgium's (lib/clouds).
#define CLOUD_SOURCE 1 // [0 1]
// Water Source: 1 = Halcyon's water simulation, swells, caustics and underwater shafts
// (Overworld; the End keeps Belgium's simulation), 0 = Belgium's.
#define WATER_SOURCE 1 // [0 1]
#define WATER_SIM_QUALITY 2 // [1 2 3 4]
#define CAUSTICS
#define CAUSTICS_MODE 2 // [1 2]
#define CAUSTICS_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5]
#define UW_SUN_SHAFTS
#define UW_SHAFT_SAMPLES 8 // [4 6 8 12 16]
#define UW_SHAFT_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define UNDERWATER_FOG 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define WAVE_SCALE 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define WAVE_SPEED 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define WAVE_DEPTH 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define WAVE_SWELL 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
#define WATER_SWELLS
#define WATER_STORM_WAVES 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define WATER_BIOME_WAVES
#define VC_ALTITUDE 640.0 // [400.0 500.0 640.0 800.0 1000.0 1200.0]
#define VC_STEPS 32 // [16 24 32 48 64 96]
#define VC_LIGHT_STEPS 5 // [3 4 5 6 8]
#define CLOUD_SHADOW_VISIBILITY 0.8 // [0.0 0.2 0.4 0.6 0.7 0.8 0.9 1.0]
// Halcyon's cloud quality levels (Cloud Quality 5 = custom: Cloud Steps / Light Steps).
#if CLOUD_QUALITY == 0
  #define VC_STEPS_Q 16
  #define VC_LIGHT_STEPS_Q 3
#elif CLOUD_QUALITY == 1
  #define VC_STEPS_Q 24
  #define VC_LIGHT_STEPS_Q 4
#elif CLOUD_QUALITY == 2
  #define VC_STEPS_Q 32
  #define VC_LIGHT_STEPS_Q 5
#elif CLOUD_QUALITY == 3
  #define VC_STEPS_Q 48
  #define VC_LIGHT_STEPS_Q 6
#elif CLOUD_QUALITY == 4
  #define VC_STEPS_Q 48
  #define VC_LIGHT_STEPS_Q 8
#else
  #define VC_STEPS_Q VC_STEPS
  #define VC_LIGHT_STEPS_Q VC_LIGHT_STEPS
#endif
#define RAIN_RIPPLE_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define RAIN_OPACITY 0.3 // [0.1 0.2 0.3 0.4 0.5 0.7]
#define REFLECTION_TEMPORAL // Accumulate reflections over frames (less noise on rough and wet surfaces).
#define REFLECTION_TEMPORAL_WEIGHT 1.0 // [0.5 0.75 1.0]
#define BLOCK_LIGHT_DIRECTIONAL // Block light is brighter on faces turned toward torches and lamps (needs Coloured Lighting).
#define RAIN_WIND_TILT 0.12 // [0.0 0.06 0.12 0.2 0.3]
// Options below are Halcyon's, copied from its settings.glsl. AURORA, AURORA_BRIGHTNESS,
// MOON_BRIGHTNESS, RAINBOW_BRIGHTNESS and STAR_TWINKLE are shared with Belgium's sky.
// Belgium's options that used these names for something else are now BE_*.
#define AURORA_QUALITY 16 // [8 12 16 24 32]
#define AURORA_REFLECTIONS
#define AURORA_FREQUENCY 1 // [0 1 2 3 4]
#define CIRRUS_CLOUDS
#define CIRRUS_COVERAGE 0.35 // [0.0 0.1 0.2 0.35 0.5 0.65 0.8]
#define VC_WIND_SPEED 1.0 // [0.0 0.25 0.5 1.0 1.5 2.0 3.0]
#define CUSTOM_MOON
#define MOON_BUMP
#define MOON_TEXTURE_RES 2048 // [2048 4096]
#define MOON_SIZE 3.0 // [1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0]
#define ECLIPSES
#define ECLIPSE_FREQUENCY 40 // [16 24 40 64 96 160]
#define ECLIPSE_PREVIEW 0 // [0 1 2]
#define REALISTIC_STARS
#define MILKY_WAY
#define MILKY_WAY_CONTRAST 1.0 // [0.8 0.9 1.0 1.1 1.2 1.35 1.5]
#define MILKY_WAY_FILTER 1 // [0 1 2]
#define MILKY_WAY_INTENSITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define MILKY_WAY_STYLE 0 // [0 1 2]
#define MILKY_WAY_TEXTURE_RES 8192 // [4096 8192]
#define NIGHT_SKY_SEASON 0 // [0 1 2 3 4]
#define STAR_BLOOM 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define STAR_BRIGHTNESS 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define STAR_TWINKLE_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0]
#define STAR_DENSITY 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define SUN_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define SUN_SIZE 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0]
#define RAINBOWS

// Plain #ifdef references so Iris lists these toggles (see the note at the end of the file).
#ifdef END_PLANETS
#endif
#ifdef UW_SUN_SHAFTS
#endif
#ifdef BLOCK_LIGHT_DIRECTIONAL
#endif
#ifdef END_BH_DRIFT
#endif

// ---------------------------------------------------------------- Nether effects ----------
#define NETHER_SMOKE // Drifting smoke structure in the Nether haze.
#define HEAT_HAZE // Shimmering air in the Nether.
#define HEAT_HAZE_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0]

// ---------------------------------------------------------------- Water -------------------
#define WATER_STYLE 1 // [0 1 2 3]
#define WATER_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define WATER_REFRACTION 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define WATER_REFLECTIVITY 1.0 // [0.5 0.75 1.0]
#define WATER_CAUSTICS 1.0 // [0.0 0.5 0.75 1.0 1.5]
#define WATER_WAVE_COUNT 16 // [8 12 16 24 32]
#define WATER_WAVE_HEIGHT 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define WATER_WAVE_SPEED 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define WATER_WIND_SPEED 6.0 // [2.0 3.0 4.0 6.0 8.0 10.0 12.0]
#define WATER_WIND_ANGLE 30.0 // [0.0 30.0 60.0 90.0 120.0 150.0 180.0 210.0 240.0 270.0 300.0 330.0]
#define SSR_STEPS 24 // [12 16 24 32 48 64]
#define OPAQUE_SSR // Screen-space reflections on smooth blocks, metals and wet surfaces.
#define SSR_MIN_SMOOTHNESS 0.55 // [0.35 0.45 0.55 0.65 0.75]

// ---------------------------------------------------------------- Water simulation --------
#define WATER_SIMULATION // Interactive ripples, splashes and boat wakes around the player.
#define WATER_SIM_RES 512 // [256 512 1024 2048]
#define WATER_SIM_CPB 8 // [4 6 8 10 12 16]
#define WATER_SIM_WAVE_SPEED 1.4 // [0.8 1.0 1.4 2.0 2.8]
#define WATER_SIM_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define PLAYER_RIPPLE_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
#define BOAT_WAKE_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]

// ---------------------------------------------------------------- Camera ------------------
#define AUTO_EXPOSURE // Adapt exposure to scene brightness like an eye or camera.
#define EXPOSURE_COMPENSATION 0.0 // [-3.0 -2.5 -2.0 -1.5 -1.0 -0.5 0.0 0.5 1.0 1.5 2.0 2.5 3.0]
#define EXPOSURE_FIXED_EV 1.0 // [-2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 8.0 10.0]
#define EXPOSURE_SPEED 1.0 // [0.25 0.5 1.0 2.0 4.0]
#define EXPOSURE_MIN_EV -2.0 // [-6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0]
#define EXPOSURE_MAX_EV 9.0 // [4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0]
#define TAA // Temporal anti-aliasing. Also denoises soft shadows and other stochastic effects.

// ---------------------------------------------------------------- Colour ------------------
#define COLOR_PROFILE 1 // [0 1 2 3 4]
#define SUN_WARMTH 0.15 // [0.0 0.1 0.15 0.2 0.3 0.4]
#define SKY_LIGHT_TINT 0.1 // [0.0 0.1 0.2 0.3]
#define SHADOW_COLOR_INFLUENCE 1.15 // [0.8 1.0 1.15 1.3 1.5]
#define COLORED_LIGHT_INTENSITY 1.15 // [0.75 1.0 1.15 1.3 1.5 2.0]
#define COLORED_LIGHT_SATURATION 1.15 // [0.75 1.0 1.15 1.3 1.5]
#define INDIRECT_SATURATION 1.15 // [0.75 1.0 1.15 1.3 1.5]
#define REFLECTION_INTENSITY 1.0 // [0.75 0.9 1.0 1.1 1.25]
#define WATER_COLOR_RESPONSE 1.1 // [0.75 1.0 1.1 1.25 1.5]
#define CLOUD_LIGHT_INTENSITY 1.05 // [0.8 0.9 1.0 1.05 1.15 1.3]
#define TONEMAP 0 // [0 1 2]

// ---------------------------------------------------------------- Post-processing ---------
#define BLOOM // Soft glow around bright light sources (energy conserving).
#define BLOOM_STRENGTH 0.04 // [0.0 0.02 0.04 0.06 0.08 0.12 0.16]
#define BLOOM_RADIUS 0.8 // [0.5 0.65 0.8 0.9 1.0]
//#define DOF // Depth of field.
#define DOF_FOCUS 0 // [0 2 4 8 16 32 64 128]
#define DOF_APERTURE 1.0 // [0.25 0.5 1.0 2.0 4.0 8.0]
#define DOF_MAX_RADIUS 16 // [8 12 16 24 32]
#define DOF_SAMPLES 24 // [12 16 24 32 48]
//#define MOTION_BLUR // Camera motion blur.
#define MOTION_BLUR_STRENGTH 0.5 // [0.25 0.5 0.75 1.0]
#define WHITE_BALANCE 6500 // [4500 5000 5500 6000 6500 7000 7500 8500]
#define CONTRAST 1.05 // [0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2]
#define SATURATION 1.0 // [0.7 0.8 0.9 1.0 1.1 1.2]
#define VIBRANCE 1.1 // [0.8 0.9 1.0 1.1 1.2 1.3]
#define NIGHT_DESATURATION 0.6 // [0.0 0.2 0.4 0.6 0.8 1.0]
//#define VIGNETTE // Darken the corners of the image.
#define VIGNETTE_STRENGTH 0.3 // [0.1 0.2 0.3 0.4 0.5]
#define SHARPENING 2 // [0 1 2 3 4]

// ---------------------------------------------------------------- Debug ------------------
//#define LOD_SHADOWS // Distant Horizons terrain casts shadow-map shadows inside the shadow distance (untested).
#define DEBUG_VIEW 0 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24]

// Iris shows a boolean #define in the menu only if some line is exactly `#ifdef NAME` or
// `#ifndef NAME` (#if/#elif expressions do not count). These options are otherwise only
// tested inside compound #if expressions. tools/validate.py enforces this rule.
#ifdef BLOCK_LIGHT_SPECULAR
#endif
#ifdef NORMAL_MAPPING
#endif
#ifdef SPECULAR_MAPPING
#endif
#ifdef PARALLAX
#endif
#ifdef CLOUD_SHADOWS
#endif
#ifdef PUDDLES
#endif
#ifdef HEAT_HAZE
#endif
#ifdef LOD_SHADOWS
#endif


#endif

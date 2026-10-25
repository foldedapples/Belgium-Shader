// Names the Halcyon modules use that are ordinary words in Belgium's code. Included only
// between hc_begin.glsl and hc_end.glsl (lib/halcyon/halcyon_sky.glsl); adapter_region_end.glsl
// removes them again. No include guard: every region defines them afresh.
#ifdef STAGE_FRAGMENT
    #define fsh
#endif
#ifdef DIM_OVERWORLD
    #define WORLD_OVERWORLD
#endif
#define worldSunDir (fsSunDir.xyz)
#define worldLightDir (fsLightDir.xyz)
// Light reaching the scene from the dominant body, and the mean sky radiance (Glimmer stored
// these in an SSBO; Belgium's FrameState has the same quantities in its own units).
#define sunlightColor (fsLightColor.rgb)
#define skylightColor (fsSkyIrradianceUp.rgb * INV_PI)
#define sunIrradiance HC_SUN_IRRADIANCE
// World time in seconds (20 ticks per second).
#define worldTimeCounter (float(worldTime) / 20.0 + float(worldDay) * 1200.0)
#define biomeCanRainSmooth biomePrecipSmooth
// Glimmer's cave darkening of the sky; Belgium darkens caves through sky light instead.
#define skyMultiplier 1.0
#define CLOUD_EXTINCTION_COLOR vec3(1.0)
// Water: Belgium's cloud shadows already carry weather and the shafts are shadowed per step, so
// Glimmer's rain-dimmed sunlight and camera sun visibility are the plain light here.
#define weatherSunlightColor sunlightColor
#define sunVisibilitySmooth 1.0
#define biomeCanPrecipitateSmooth biomePrecipSmooth
#define oceanBiomeSmooth biomeOceanSmooth
#define riverBiomeSmooth biomeRiverSmooth
// Halcyon's deep-water darkness slider and detail-wave strength are not imported (neutral).
#define WATER_INSCATTER_GAIN 1.0
#define WAVE_DETAIL 1.0
#ifndef DIM_NETHER
    #define SHADOWS
#endif
#if defined VOLUMETRIC_CLOUDS && defined CLOUD_SHADOW_READ
    #define CLOUDS
    #define getCloudShadow(p) cloudShadow(p)
#endif

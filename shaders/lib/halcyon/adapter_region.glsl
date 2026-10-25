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

#ifndef HALCYON_SKY_GLSL
#define HALCYON_SKY_GLSL
// Halcyon's sky - real catalogue stars and NASA Milky Way, NASA moon with phases and
// earthshine, solar and lunar eclipses, aurora, cirrus with the 22 degree halo, rainbows -
// running on Belgium's atmosphere, FrameState and HDR pipeline (Sky Source = Halcyon).
//
// The Halcyon files under lib/halcyon/ are unmodified copies (tools/import_halcyon.py); this
// file is the bridge that used to be Glimmer's getSky()/prepare code, rewritten for Belgium.
// Requires lib/atmosphere/sky_view.glsl (skyRadiance) and lib/sky/sky_render.glsl
// (viewTransmittance) when HALCYON_SKY_RENDER is defined; begin_state only needs the state.
#include "/lib/halcyon/adapter_core.glsl"
#include "/lib/clouds/cirrus.glsl"

// Values begin_state copies into FrameState (outside the region, so plain member names).
struct HalcyonCelestial {
    float solarCover;      // fraction of the sun disk covered
    float umbra;           // lunar umbra / penumbra coverage of the moon disk
    float penumbra;
    float phaseAngle;      // sun-moon-observer angle (rad)
    float moonRadius;      // angular radii (rad)
    float sunRadius;
    float moonLight;       // phase brightness x MOON_BRIGHTNESS
    vec3  moonTint;        // lunar eclipse colour factor
};

#include "/lib/halcyon/hc_begin.glsl"
#include "/lib/halcyon/adapter_region.glsl"
#include "/lib/halcyon/atmosphere/sky/celestial.glsl"
#include "/lib/halcyon/atmosphere/sky/stars.glsl"
#include "/lib/halcyon/atmosphere/sky/aurora.glsl"
#include "/lib/halcyon/atmosphere/sky/rainbow.glsl"

// Halcyon's celestial model (moon opposite the sun, phase from moonPhase, eclipses on new and
// full moon days) in the form Belgium's lighting consumes. Mirrors Halcyon's prepare pass:
// sunlight x eclipseSunlightFactor, moonlight x moonPhaseBrightness x MOON_BRIGHTNESS x
// eclipseMoonlightFactor.
HalcyonCelestial halcyonCelestial() {
    EclipseState e = getEclipseState();
    HalcyonCelestial h;
    h.solarCover = e.solarCoverage;
    h.umbra = e.lunarUmbra;
    h.penumbra = e.lunarPenumbra;
    h.phaseAngle = moonPhaseAngle();
    h.moonRadius = MOON_ANGULAR_RADIUS;
    h.sunRadius = SUN_ANGULAR_RADIUS;
    h.moonLight = moonPhaseBrightness() * MOON_BRIGHTNESS;
    h.moonTint = eclipseMoonlightFactor(e);
    return h;
}

#ifdef HALCYON_SKY_RENDER
// Scale for Halcyon's moon disk and glow (its constants were tuned for Glimmer's exposure).
// The moon's surface is lit by the sun, so by day it has its physical radiance (lunar albedo
// 0.12 against the texture's normalised mean 0.35, times E_sun / pi) and stays visible against
// the blue sky. At night the eye adapts locally: the disk is held at MOON_DISK_CONTRAST times
// the radiance of moonlit ground (albedo 0.25), so craters and phases keep their detail.
// Before, the night disk was ~530x moonlit ground and clipped to a white disk (seen in game).
const float MOON_DISK_CONTRAST = 12.0;
float halcyonMoonDiskScale() {
    const float base = 0.32 * 0.35;                          // Halcyon disk constant x mean albedo
    float day = (0.12 / 0.35) * SUN_IRRADIANCE * INV_PI / 0.32;
    float night = MOON_DISK_CONTRAST * 0.25 * SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO * INV_PI / base;
    return mix(day, night, smoothstep(0.05, -0.12, fsSunDir.y));
}

// Halcyon's getSky() composition on Belgium's atmosphere. `includeSun = false` is the
// reflection/ambient variant (no disks or stars; aurora only with Aurora in Reflections).
vec3 halcyonSkyRadiance(vec3 rayDir, bool includeSun) {
    vec3 lum = skyRadiance(rayDir);
    EclipseState eclipse = getEclipseState();
    float camR = ATM_GROUND + cameraAltitudeKm(cameraPosition.y);
    vec3 viewT = rayHitsGround(camR, rayDir.y) ? vec3(0.0) : viewTransmittance(rayDir);

    float aurora = 0.0;
    #ifdef AURORA
        aurora = auroraActivity();
        #ifndef AURORA_REFLECTIONS
        if (includeSun)
        #endif
        {
            lum += getAurora(rayDir, aurora) * HC_NIGHT_SCALE * viewT;
        }
    #endif
    if (!includeSun) return lum;

    float moonCoverage;
    float moonScale = halcyonMoonDiskScale();
    vec3 moonLum = moonDiskRadiance(rayDir, eclipse, moonCoverage) * moonScale;
    vec3 catalogStarLum = vec3(0.0);
    #if defined REALISTIC_STARS || defined MILKY_WAY
    {
        vec3 stars;
        vec3 mw = nightSky(rayDir, aurora, smoothstep(0.97, 1.0, eclipse.solarCoverage), stars);
        float visible = 1.0 - moonCoverage;
        lum += mw * HC_NIGHT_SCALE * visible * viewT;
        catalogStarLum = stars * HC_NIGHT_SCALE * visible * viewT;
    }
    #endif
    lum += (moonLum + moonGlow(rayDir, eclipse) * moonScale) * viewT;

    float cirrusTrans = 1.0;
    #ifdef CIRRUS_CLOUDS
    {
        // Belgium's cirrus layer (8 km, band-limited, physical phase plus the 22 degree halo),
        // driven by Halcyon's Cirrus Coverage and Cloud Movement Speed. Halcyon's own layer at
        // 3.2 km, stretched 3.3x along the wind, fanned into long streaks across the sky under
        // perspective, and its x-pi scattering made the area around the sun blaze (seen in game).
        bool sunUp = fsSunDir.y > -0.12;
        float pixelAngle = 2.0 / max(gbufferProjection[1][1] * viewHeight, 1.0);
        vec4 ci = cirrusLayer(rayDir, sunUp ? fsSunDir.xyz : fsMoonDir.xyz,
                              sunUp ? fsSunIrradiance.rgb : fsMoonIrradiance.rgb, fsSkyIrradianceUp.rgb,
                              pixelAngle, CIRRUS_COVERAGE * 1.4, VC_WIND_SPEED);
        lum = lum * ci.a + ci.rgb;
        cirrusTrans = ci.a;
    }
    #endif
    // Glimmer greyed the sky toward its rain skylight here; Belgium's atmosphere and weather
    // state already darken and desaturate the sky in rain, so that step is not repeated.
    #ifdef RAINBOWS
    {
        vec4 bow = rainbow(rayDir);
        lum = lum * bow.a + luminance(lum) * bow.rgb * viewT;
    }
    #endif
    lum += sunDiskRadiance(rayDir, eclipse) * viewT * cirrusTrans;
    lum += catalogStarLum * cirrusTrans * (1.0 - wetness);
    return lum * clamp01(1.0 - darknessLightFactor * 2.5);
}
#endif

#include "/lib/halcyon/adapter_region_end.glsl"
#include "/lib/halcyon/hc_end.glsl"

#endif

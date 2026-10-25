// begin.csh - one thread updates FrameState: celestial model and eclipses, light choice and
// colour at the camera, sky irradiance, weather smoothing, shadow matrices.
#include "/lib/core/common.glsl"
#define FRAME_STATE_WRITER
#include "/lib/core/frame_state.glsl"
#include "/lib/sky/celestial.glsl"
#include "/lib/lighting/shadow_space.glsl"
#if defined DIM_OVERWORLD
    #define ATMOSPHERE_LUTS
    #define SKY_VIEW_READ
#endif
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/atmosphere/sky_view.glsl"
#include "/lib/end/end_params.glsl"
#include "/lib/post/color_profile.glsl"
#if defined DIM_OVERWORLD && SKY_SOURCE == 1
    #include "/lib/halcyon/halcyon_sky.glsl"
#endif
#if defined DIM_OVERWORLD && CLOUD_SOURCE == 1
    #include "/lib/halcyon/halcyon_clouds.glsl"
#endif
#if !defined DIM_NETHER
    #define WATER_SIM_WRITER
    #include "/lib/water/water_sim_control.glsl"
#endif

#ifdef STAGE_COMPUTE
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

// Hemispherical irradiance from last frame's sky-view LUT (one frame of latency is invisible
// and avoids a reduction pass). Returns irradiance onto up-facing and vertical surfaces.
void integrateSkyIrradiance(out vec3 up, out vec3 side) {
    up = vec3(0.0); side = vec3(0.0);
    #ifdef SKY_VIEW_READ
    const int NE = 8, NA = 16;
    for (int i = 0; i < NE; i++) {
        float e = (float(i) + 0.5) / float(NE) * HALF_PI;      // elevation 0..90
        float dOmegaE = (HALF_PI / float(NE)) * cos(e);          // solid-angle weight
        for (int j = 0; j < NA; j++) {
            float a = (float(j) + 0.5) / float(NA) * TAU;
            vec3 d = vec3(cos(e) * cos(a), sin(e), cos(e) * sin(a));
            vec3 L = skyRadiance(d);
            float dOmega = dOmegaE * (TAU / float(NA));
            up += L * sin(e) * dOmega;
            side += L * cos(e) * INV_PI * dOmega;
        }
    }
    #endif
}

void main() {
    bool init = fsHeader.x != FS_VERSION;
    if (init) {
        fsExposure = vec4(1.0, 0.18, 1.0, 0.0);
        fsHeader = ivec4(FS_VERSION, 0, 0, 0);
    }
    fsHeader.y = min(fsHeader.y + 1, 1 << 30);
    int framesValid = fsHeader.y;

    vec3 sunDir = safeNormalize(viewToSceneDir(sunPosition), vec3(0.0, 1.0, 0.0));
    vec3 lightDir = sunDir;
    float lightKind = 1.0;
    vec3 lightColor = vec3(0.0);
    vec3 skyUp = vec3(0.0), skySide = vec3(0.0);

    #if defined DIM_OVERWORLD
    {
        CelestialState c = computeCelestial(sunDir);
        #if SKY_SOURCE == 1
            // Halcyon's celestial model drives the lighting, so the moon, eclipses and
            // moonlight seen in the sky and cast on the world agree (lib/halcyon/halcyon_sky.glsl).
            HalcyonCelestial hcel = halcyonCelestial();
            c.moonDir = -c.sunDir;
            c.phaseAngle = hcel.phaseAngle;
            c.elongation = PI - hcel.phaseAngle;
            c.sunRadius = hcel.sunRadius;
            c.moonRadius = hcel.moonRadius;
            c.solarCoverage = hcel.solarCover;
            c.lunarUmbra = hcel.umbra;
            c.lunarPenumbra = hcel.penumbra;
        #endif
        fsSunDir = vec4(c.sunDir, c.sunDir.y);
        float litFraction = 0.5 * (1.0 + cos(c.phaseAngle));
        fsMoonDir = vec4(c.moonDir, litFraction);
        fsCelestialAxis = vec4(c.axis, c.sunRadius);
        // Earthshine: Earth seen from the moon is "full" when the moon is new.
        float earthshine = 0.5 * (1.0 - cos(c.phaseAngle)) * 0.012;
        fsMoonParams = vec4(c.moonRadius, c.phaseAngle, c.elongation, earthshine);
        fsEclipse = vec4(c.solarCoverage, c.lunarUmbra, c.lunarPenumbra,
                         smoothstep(0.96, 0.999, c.solarCoverage));

        // Colour profile: a warmer (lower colour temperature) solar spectrum. Applied at the top
        // of the atmosphere so sky, clouds and terrain all receive the same light.
        vec3 warmth = blackbody(mix(5800.0, 4300.0, CP_SUN_WARMTH)) / blackbody(5800.0);
        warmth /= max(luminance(warmth), 1e-4);
        vec3 sunE = vec3(SUN_IRRADIANCE) * warmth * (1.0 - c.solarCoverage);
        fsSunIrradiance = vec4(sunE, c.solarCoverage);
        // Moon: phase law, then lunar eclipse. Umbral light is sunlight refracted through
        // Earth's atmosphere at grazing incidence, i.e. the transmittance LUT at the horizon.
        float r0 = ATM_GROUND + 0.001;
        vec3 grazing = transmittanceToTop(r0, 0.0);
        vec3 umbralTint = grazing * grazing * 0.35;
        vec3 eclipseFactor = mix(vec3(1.0 - c.lunarPenumbra), umbralTint, c.lunarUmbra);
        #if SKY_SOURCE == 1
            vec3 moonE = vec3(SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO * hcel.moonLight) * hcel.moonTint;
        #else
            vec3 moonE = vec3(SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO * lunarPhaseLaw(c.phaseAngle)) * eclipseFactor;
        #endif
        fsMoonIrradiance = vec4(moonE, c.lunarUmbra);

        // Dominant light: sun while it is up, otherwise the moon, otherwise none.
        float camR = ATM_GROUND + cameraAltitudeKm(cameraPosition.y);
        vec3 sunAtCam = sunE * sunTransmittance(camR, sunDir.y, c.sunRadius);
        vec3 moonAtCam = moonE * sunTransmittance(camR, c.moonDir.y, c.moonRadius);
        if (sunDir.y > -0.05) {
            lightDir = sunDir; lightKind = 1.0; lightColor = sunAtCam;
        } else if (c.moonDir.y > -0.05) {
            lightDir = c.moonDir; lightKind = 0.0; lightColor = moonAtCam;
        } else {
            lightDir = sunDir; lightKind = -1.0; lightColor = vec3(0.0);
        }
        fsTime.w = c.preview ? 1.0 : 0.0;
        if (framesValid > 2) integrateSkyIrradiance(skyUp, skySide);
        // Stars and the Milky Way are drawn separately from skyRadiance(); add their light.
        skyUp += starlightIrradiance();
        skySide += starlightIrradiance() * 0.5;
    }
    #elif defined DIM_END
    {
        vec3 bh = endBlackHoleDir();
        fsSunDir = vec4(bh, bh.y);
        fsMoonDir = vec4(-bh, 0.0);
        fsCelestialAxis = vec4(vec3(0.0, 0.0, 1.0), 0.02);
        fsMoonParams = vec4(0.0);
        fsEclipse = vec4(0.0);
        fsSunIrradiance = vec4(endLightIrradiance(), 0.0);
        fsMoonIrradiance = vec4(0.0);
        lightDir = bh; lightKind = 1.0; lightColor = endLightIrradiance();
        skyUp = endAmbientIrradiance(); skySide = skyUp * 0.8;
    }
    #else
    {
        // Nether: no celestial light, no shadow map. Ambient comes from fog colour in lighting.
        fsSunDir = vec4(0.0, 1.0, 0.0, 1.0);
        fsMoonDir = vec4(0.0, -1.0, 0.0, 0.0);
        fsCelestialAxis = vec4(0.0, 0.0, 1.0, 0.0);
        fsMoonParams = vec4(0.0);
        fsEclipse = vec4(0.0);
        fsSunIrradiance = vec4(0.0);
        fsMoonIrradiance = vec4(0.0);
        lightDir = vec3(0.0, 1.0, 0.0); lightKind = -1.0;
    }
    #endif

    // Clouds: coverage drifts day to day, rain closes the sky, storms build towers. Changes
    // are smoothed so weather transitions take tens of seconds.
    {
        float ft = clamp(frameTime, 0.0, 0.25);
        float daily = (hash11(uint(worldDay) * 2654435761u + 19u) - 0.5) * CLOUD_DAILY_VARIATION;
        float target = saturate(CLOUD_COVERAGE + daily);
        target = mix(target, max(target, 0.86), saturate(rainStrength));
        target = mix(target, 0.95, saturate(thunderStrength));
        float k = 1.0 - exp(-ft / 25.0);
        bool fresh = fsHeader.y <= 1;
        fsCloud.x = fresh ? target : fsCloud.x + (target - fsCloud.x) * k;
        fsCloud.y = fresh ? thunderStrength : fsCloud.y + (thunderStrength - fsCloud.y) * k;
        fsCloud.z = CLOUD_ALTITUDE;
        fsCloud.w = CLOUD_ALTITUDE + 1900.0 + 5000.0 * fsCloud.y;
        #if defined DIM_OVERWORLD && CLOUD_SOURCE == 1
            // Halcyon's layer and coverage, so the cloud shadow plane, the temporal pass and the
            // overcast lighting below follow the clouds that are drawn.
            vec2 hcLayer = halcyonCloudLayer();
            fsCloud.z = hcLayer.x;
            fsCloud.w = hcLayer.y;
            fsCloud.x = halcyonCloudCoverage();
        #endif
        float a = radians(WATER_WIND_ANGLE);
        vec2 wind = vec2(cos(a), sin(a)) * CLOUD_WIND_SPEED * (1.0 + fsCloud.y);
        vec4 off = fresh ? vec4(0.0) : fsCloudWind;
        off.xy = mod(off.xy + wind * ft, 16384.0);
        off.zw = mod(off.zw + wind * ft * 1.25, 2400.0);
        fsCloudWind = off;
        #if defined DIM_OVERWORLD && defined VOLUMETRIC_CLOUDS && defined CLOUD_SHADOWS
            // Overcast skies: the direct beam is removed by the cloud shadow map, and the sky
            // dome becomes a dim diffuse emitter (~a quarter of clear-sky global light).
            float overcast = sq(fsCloud.x);
            vec3 global = lightColor * max(lightDir.y, 0.0) * float(lightKind >= 0.0) + skyUp;
            skyUp = mix(skyUp, global * 0.28, overcast);
            skySide = mix(skySide, global * 0.22, overcast);
        #endif
    }

    // Colour profile: sky light tint toward blue and stronger colour separation between sunlit
    // and shaded surfaces (saturation of the sky irradiance). Luminance is preserved.
    {
        vec3 tint = vec3(0.86, 0.96, 1.2);
        tint /= luminance(tint);
        skyUp = cpSaturate(skyUp * mix(vec3(1.0), tint, CP_SKY_TINT), CP_SHADOW_COLOR);
        skySide = cpSaturate(skySide * mix(vec3(1.0), tint, CP_SKY_TINT), CP_SHADOW_COLOR);
    }
    fsLightDir = vec4(lightDir, lightKind);
    fsLightColor = vec4(lightColor, 0.0);
    fsSkyIrradianceUp = vec4(skyUp, 0.0);
    fsSkyIrradianceSide = vec4(skySide, 0.0);

    // Aurora: decided once per night from a per-day hash, then a slow substorm modulation.
    {
        float target = 0.0;
        #if defined DIM_OVERWORLD && defined AURORA
            int nightDay = worldDay - (worldTime < 6000 ? 1 : 0);
            float roll = hash11(uint(nightDay) * 747796405u + 2891336453u);
            float strength = 0.35 + 0.65 * hash11(uint(nightDay) * 2654435761u + 977u);
            float night = smoothstep(-0.04, -0.2, sunDir.y);
            float substorm = 0.7 + 0.3 * sin(frameTimeCounter * 0.021 + float(nightDay));
            target = roll < BE_AURORA_FREQUENCY ? strength * night * substorm : 0.0;
        #endif
        float k = 1.0 - exp(-clamp(frameTime, 0.0, 0.25) / 20.0);
        fsWeather.w = fsHeader.y <= 1 ? target : fsWeather.w + (target - fsWeather.w) * k;
    }

    // Weather: Minecraft already smooths rain into `wetness`; storms use thunderStrength.
    fsWeather.x = saturate(wetness);
    fsWeather.y = saturate(thunderStrength);
    fsWeather.z = saturate(rainStrength);

    fsTime.x = mod(frameTimeCounter, 3600.0);
    fsTime.z = dayFraction();

    #if !defined DIM_NETHER && defined WATER_SIMULATION
        updateWaterSimControl();
    #endif

    // Shadow map centre: follows the camera with hysteresis (distance measured across the light
    // direction, the plane the map lies in). Re-anchors on the first frame, after a reload or
    // dimension change (state reset), and on teleports.
    {
        vec3 a = fsShadowAnchor.xyz;
        vec3 d = cameraPosition - a;
        vec3 Ld = safeNormalize(lightDir);
        float lateral = length(d - Ld * dot(d, Ld));
        bool reset = init || fsShadowAnchor.w != 1.0 || lateral > max(SHADOW_ANCHOR_RADIUS, 0.0) || lateral > 64.0;
        if (reset) fsShadowAnchor = vec4(cameraPosition, 1.0);
    }
    mat4 view, proj;
    buildShadowMatrices(lightDir, fsCelestialAxis.xyz, cameraPosition, fsShadowAnchor.xyz, view, proj);
    fsShadowView = view;
    fsShadowProj = proj;
    fsShadowInfo = vec4(shadowDistance, SHADOW_DEPTH_HALF, shadowCentreTexelWorld(), SHADOW_DISTORTION);
}
#endif

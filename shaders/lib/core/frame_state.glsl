#ifndef CORE_FRAME_STATE_GLSL
#define CORE_FRAME_STATE_GLSL
// FrameState SSBO (binding 0). Written by begin.csh (celestial, weather, shadow matrices) and
// composite6.csh (exposure); read by every other stage. Iris zero-fills the buffer at creation,
// so fsHeader.x != FS_VERSION means "never initialised" (first frame, pack reload, dimension
// change) and readers must use the fallbacks below.

#define FS_VERSION 0x42454C34

#ifdef FRAME_STATE_WRITER
    #define FS_ACCESS
#else
    #define FS_ACCESS readonly
#endif

layout(std430, binding = 0) FS_ACCESS buffer FrameStateBuffer {
    ivec4 fsHeader;            // x version, y frames since init, z flags, w reserved
    vec4  fsSunDir;            // scene-space unit vector, w = sin(elevation)
    vec4  fsMoonDir;           // w = illuminated fraction of the disk
    vec4  fsLightDir;          // shadow/dominant light, w = 1 sun, 0 moon, -1 none
    vec4  fsSunIrradiance;     // top-of-atmosphere sun irradiance (incl. eclipse), w = solar coverage
    vec4  fsMoonIrradiance;    // top-of-atmosphere moon irradiance (phase, lunar eclipse)
    vec4  fsLightColor;        // irradiance of the dominant light at the camera after the atmosphere
    vec4  fsSkyIrradianceUp;   // sky irradiance on an up-facing surface at the camera
    vec4  fsSkyIrradianceSide; // sky irradiance on a vertical surface (azimuth average)
    vec4  fsEclipse;           // x solar coverage, y lunar umbra (disk avg), z penumbra (disk avg), w corona
    vec4  fsCelestialAxis;     // diurnal rotation axis, w = sun angular radius (rad)
    vec4  fsMoonParams;        // x moon angular radius, y phase angle (sun-moon-observer), z elongation, w earthshine
    vec4  fsWeather;           // x wetness, y storm, z rain, w aurora activity
    vec4  fsTime;              // x wrapped seconds, y star-field rotation, z day fraction, w eclipse preview active
    vec4  fsExposure;          // x exposure, y metered luminance, z target exposure, w frames metered
    vec4  fsShadowInfo;        // x half extent (blocks), y depth half range, z texel world size at centre, w distortion k
    vec4  fsCloud;             // x coverage (smoothed), y storm factor (smoothed), z base altitude, w top altitude
    vec4  fsCloudWind;         // xy weather-map offset (m, wrapped), zw shape-noise offset (m, wrapped)
    vec4  fsFocus;             // x smoothed focus distance (blocks), y last measured distance
    mat4  fsShadowView;
    mat4  fsShadowProj;
};

bool frameStateValid() { return fsHeader.x == FS_VERSION; }

#endif

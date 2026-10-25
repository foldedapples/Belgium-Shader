#ifndef SKY_SKY_RENDER_GLSL
#define SKY_SKY_RENDER_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#define ATMOSPHERE_LUTS
#define SKY_VIEW_READ
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/atmosphere/sky_view.glsl"
#include "/lib/sky/celestial.glsl"
#include "/lib/sky/moon.glsl"
#include "/lib/sky/stars.glsl"

// Overworld sky: atmosphere in-scatter + (transmittance x celestial objects).
// `pixelAngle` is the angular size of a pixel, used to anti-alias disk edges.

// Mean of the quadratic limb-darkening law over the disk (closed form of the area integral).
const float LIMB_MEAN = 0.77333;

vec3 sunDiskRadiance(vec3 dir, float pixelAngle) {
    vec3 s = fsSunDir.xyz;
    float r = fsCelestialAxis.w;
    float cosA = dot(dir, s);
    if (cosA < cos(r + 2.0 * pixelAngle)) return vec3(0.0);
    float ang = acos(clamp(cosA, -1.0, 1.0));
    float rr = saturate(ang / r);
    float mu = sqrt(max(1.0 - rr * rr, 0.0));
    float coverageAA = 1.0 - smoothstep(r - pixelAngle, r + pixelAngle, ang);
    // Use the un-eclipsed irradiance: the moon disk occludes the sun per pixel.
    float centre = SUN_IRRADIANCE / (PI * r * r * LIMB_MEAN);
    return vec3(centre * solarLimbDarkening(mu) * coverageAA);
}

// Inner corona visible near totality: steep radial falloff with faint streamers.
vec3 solarCorona(vec3 dir) {
    float strength = fsEclipse.w;
    if (strength <= 0.0) return vec3(0.0);
    vec3 s = fsSunDir.xyz;
    float r = fsCelestialAxis.w;
    float ang = acos(clamp(dot(dir, s), -1.0, 1.0));
    float x = ang / r;
    if (x < 1.0 || x > 8.0) return vec3(0.0);
    mat3 b = basisFromNormal(s);
    vec2 p = vec2(dot(dir, b[0]), dot(dir, b[1]));
    float theta = atan(p.y, p.x);
    float streamers = 0.75 + 0.25 * sin(theta * 3.0 + 1.3) * sin(theta * 7.0 + 0.4) + 0.12 * sin(theta * 17.0);
    float falloff = pow(x, -4.5) * streamers;
    float centre = SUN_IRRADIANCE / (PI * r * r * LIMB_MEAN);
    return vec3(1.0, 0.97, 0.93) * centre * 2.5e-6 * falloff * strength * 40.0;
}

vec3 celestialRadiance(vec3 dir, float pixelAngle, out bool moonCovers) {
    vec3 moon = moonDiskRadiance(dir, pixelAngle, moonCovers);
    if (moonCovers) return moon;
    vec3 sun = sunDiskRadiance(dir, pixelAngle) + solarCorona(dir);
    return sun + moon + nightSky(dir, pixelAngle);
}

vec3 viewTransmittance(vec3 dir) {
    float r = ATM_GROUND + cameraAltitudeKm(cameraPosition.y);
    return transmittanceToTop(r, dir.y);
}

#endif

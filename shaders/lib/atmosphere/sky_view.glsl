#ifndef ATMOSPHERE_SKY_VIEW_GLSL
#define ATMOSPHERE_SKY_VIEW_GLSL
#include "/lib/core/common.glsl"

// Sky-view LUT layout: 192 x 216 texels = two 192 x 108 panels.
//   panel 0 (rows   0..107): sky radiance lit by the sun
//   panel 1 (rows 108..215): sky radiance lit by the moon
// u: azimuth difference between view and light, [0, pi] (the sky is mirror-symmetric about
//    the light's vertical plane), v: elevation with a square-root warp that concentrates
//    texels at the horizon where the gradient is steepest.
// Values are absolute radiance (light irradiance and eclipses included).

const vec2 SKY_VIEW_PANEL = vec2(192.0, 108.0);

vec2 skyViewParamsToUv(float azimuth, float elevation) {
    float u = saturate(azimuth / PI);
    float e = elevation / HALF_PI;
    float v = 0.5 + 0.5 * sign(e) * sqrt(abs(e));
    return vec2(u, v);
}

void skyViewUvToParams(vec2 uv, out float azimuth, out float elevation) {
    azimuth = uv.x * PI;
    float s = uv.y * 2.0 - 1.0;
    elevation = sign(s) * s * s * HALF_PI;
}

// Direction in the LUT's local frame (light in the +X/Y plane).
vec3 skyViewLocalDir(float azimuth, float elevation) {
    return vec3(cos(elevation) * cos(azimuth), sin(elevation), cos(elevation) * sin(azimuth));
}

#ifdef SKY_VIEW_READ
uniform sampler2D skyViewLutTex;

vec3 sampleSkyViewPanel(vec3 dir, vec3 lightDir, int panel) {
    vec2 dh = dir.xz, lh = lightDir.xz;
    float az = 0.0;
    float ld = dot(dh, dh), ll = dot(lh, lh);
    if (ld > 1e-8 && ll > 1e-8) az = acos(clamp(dot(dh, lh) * inversesqrt(ld * ll), -1.0, 1.0));
    vec2 uv = skyViewParamsToUv(az, asin(clamp(dir.y, -1.0, 1.0)));
    // Clamp inside the panel so bilinear filtering never bleeds into the other panel.
    uv = clamp(uv, 0.5 / SKY_VIEW_PANEL, 1.0 - 0.5 / SKY_VIEW_PANEL);
    uv.y = (uv.y + float(panel)) * 0.5;
    return texture(skyViewLutTex, uv).rgb;
}

// Night-sky background (airglow from the upper atmosphere, ~90 km): radiance relative to the
// full moon's irradiance. A dark rural sky is ~21.8 mag/arcsec^2, i.e. pi * L / E_fullmoon
// ~ 2.5e-3, so L ~ 8e-4 E_fullmoon at the zenith. Brightens toward the horizon by the van
// Rhijn factor of a thin shell (capped: near the horizon extinction takes over). Scaled by
// NIGHT_SKY_BRIGHTNESS like the stars, so stars, Milky Way and background keep their real
// ratios. It is part of skyRadiance(), so distant terrain, fog, clouds and the sky ambient
// all see the same night sky the camera sees.
vec3 nightGlowRadiance(vec3 dir) {
    const vec3 AIRGLOW_COLOUR = vec3(0.62, 0.78, 0.82) / 0.7463;   // unit luminance
    float y = max(dir.y, 0.0);
    float vanRhijn = min(inversesqrt(max(1.0 - 0.972 * (1.0 - y * y), 1e-3)), 3.0);
    return AIRGLOW_COLOUR * (SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO * 8e-4 * NIGHT_SKY_BRIGHTNESS) * vanRhijn;
}

// Irradiance on a horizontal surface from the stars and the Milky Way of stars.glsl, as a
// fraction of the full moon's: ~13.6k stars to m = 6.8 give ~1.1e-3 over the sphere and the
// Milky Way ~2.9e-3; a cosine-weighted upper hemisphere receives about a quarter of that.
vec3 starlightIrradiance() {
    return vec3(0.95, 0.97, 1.0) * (SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO * 1.0e-3 * NIGHT_SKY_BRIGHTNESS);
}

// Total sky radiance: atmosphere scattering of sun and moon light plus the night-sky
// background (no disks, no stars).
vec3 skyRadiance(vec3 dir) {
    return sampleSkyViewPanel(dir, fsSunDir.xyz, 0) + sampleSkyViewPanel(dir, fsMoonDir.xyz, 1)
         + nightGlowRadiance(dir);
}
#endif

#endif

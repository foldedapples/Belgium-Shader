#ifndef MERIDIAN_SKY
#define MERIDIAN_SKY

// Overworld sky along a player-space direction: atmospheric scattering (sky-view LUT, sun and
// moon light), the solar disk with limb darkening, the Moon, stars, the Milky Way and airglow,
// each attenuated by the atmosphere's transmittance. Requires ATMOSPHERE_SAMPLERS, celestial,
// moon, stars, encoding.

// Solar limb darkening, I(mu)/I(1) = 1 - u (1 - mu), with a wavelength-dependent coefficient
// (stronger in blue), normalised to keep the disk's total flux.
vec3 sunDiskRadiance(vec3 dir, vec3 sunDir, float illum, float pixelAngle) {
    float c = dot(dir, sunDir);
    float ang = acos(clamp(c, -1.0, 1.0));
    float edge = (SUN_ANGULAR_RADIUS - ang) / max(pixelAngle, 1e-5);
    float cover = saturate(edge + 0.5);
    if (cover <= 0.0) return vec3(0.0);
    float rho = saturate(ang / SUN_ANGULAR_RADIUS);
    float mu = sqrt(max(1.0 - rho * rho, 0.0));
    const vec3 u = vec3(0.48, 0.60, 0.72);
    vec3 limb = (1.0 - u * (1.0 - mu)) / (1.0 - u / 3.0);
    float peak = illum / (PI * SUN_ANGULAR_RADIUS * SUN_ANGULAR_RADIUS);
    #ifdef MERIDIAN_STATE
    // Limb darkening keeps its shape; only the overall level is adapted (celestial.glsl).
    peak = min(peak, sunRadianceLimit() / 1.32);
    #endif
    return vec3(peak) * limb * cover;
}

// Natural night-sky background (airglow plus zodiacal light): about 22 mag/arcsec^2 at the
// zenith at a dark site, i.e. ~3.5e-4 of the full Moon's illuminance per steradian, brightening
// towards the horizon as the emitting layer (~90 km) is seen obliquely (van Rhijn factor, capped
// where extinction takes over). `k` is the full-Moon illuminance with the night lift applied.
float vanRhijn(float cosZenith) {
    const float R = 6371.0, H = 90.0;
    float s2 = sq(R / (R + H)) * (1.0 - cosZenith * cosZenith);
    return min(inversesqrt(max(1.0 - s2, 1e-3)), 3.0);
}

vec3 airglow(vec3 dir, float k) {
    return vec3(0.85, 1.0, 0.75) * (3.5e-4 * k * vanRhijn(max(dir.y, 0.0)));
}

vec3 nightSkyRadiance(vec3 dir, float pixelAngle, float gain) {
    vec3 eq = equatorialFromPlayer() * dir;
    vec3 c = vec3(0.0);
    // Star flux and Milky Way radiance are stored relative to the full Moon (tools/prep_stars.py),
    // so they scale with the same (night-lifted) full-Moon illuminance as moonlight: the number of
    // visible stars then follows moonlight and exposure without any day/night switch.
    float k = SUN_ILLUMINANCE * MOON_PHYSICAL_RATIO * gain;
    #ifdef STARS
    c += starRadiance(eq, pixelAngle) * (k * STAR_BRIGHTNESS);
    #endif
    #ifdef MILKY_WAY
    c += milkyWayRadiance(eq) * (k * MILKY_WAY_BRIGHTNESS);
    #endif
    return c;
}

// `withSun` / `withMoon` add the disks. Reflections leave out whichever body is the shadow-casting
// light: the BRDF already adds that one as an analytic, area-correct glint, and adding the disk
// too counted it twice (and as an aliased sub-pixel spot).
vec3 skyRadianceDisks(vec3 dir, SkyLights L, float pixelAngle, bool withSun, bool withMoon) {
    float r = cameraRadius(cameraPosition.y);
    vec3 scatter = sampleSkyView(dir);
    // The LUT is a clear sky. Under rain the visible air below the overcast is lit by grey cloud
    // light instead of direct sun, so it loses its blue and darkens.
    scatter = mix(scatter, vec3(luminance(scatter)) * vec3(0.92, 0.96, 1.0) * 0.75, rainStrength * 0.85);
    #ifdef LIGHTNING_FLASH
    // A lightning flash lights the whole storm sky for a moment.
    scatter += vec3(0.65, 0.7, 0.95) * lightningBoltPosition.w * (0.6 + 0.4 * thunderStrength);
    #endif
    vec3 trans = transmittanceToTop(r, dir.y);
    vec3 space = nightSkyRadiance(dir, pixelAngle, L.skyGain);
    if (withSun || withMoon) {
        // The Moon's coverage is needed for eclipses even when only the sun is drawn.
        float cov;
        vec3 moon = moonDiskRadiance(dir, L.moonDir, L.sunDir, celestialAxis(), L.moonFullIllum, pixelAngle, cov);
        if (withMoon) space = mix(space, moon, cov);
        // The new Moon occludes the sun in an eclipse; draw the sun first, the Moon over it.
        if (withSun) space += sunDiskRadiance(dir, L.sunDir, SUN_ILLUMINANCE, pixelAngle) * (1.0 - cov);
    }
    // Airglow emits at ~90 km, in front of the Moon and stars but behind most of the air.
    space += airglow(dir, SUN_ILLUMINANCE * MOON_PHYSICAL_RATIO * L.skyGain);
    // Below the horizon the planet blocks space (transmittance is 0 there).
    return scatter + space * trans;
}

// `withDisks` adds the sun and moon disks (off for reflections of rough surfaces).
vec3 skyRadiance(vec3 dir, SkyLights L, float pixelAngle, bool withDisks) {
    return skyRadianceDisks(dir, L, pixelAngle, withDisks, withDisks);
}

#endif

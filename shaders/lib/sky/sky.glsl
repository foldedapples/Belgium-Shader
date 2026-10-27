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

// ---- rainbow
// A rainbow is sunlight refracted and reflected inside raindrops, concentrated at the angle of
// minimum deviation, which depends on the refractive index n(lambda) of water. Measured from the
// antisolar point: primary bow (one internal reflection) at 4r - 2i with cos^2 i = (n^2 - 1) / 3;
// secondary (two reflections) at pi - (6r - 2i) with cos^2 i = (n^2 - 1) / 8, colours reversed and
// fainter. Between them lies Alexander's dark band, where no once- or twice-reflected light
// arrives; inside the primary the sky is slightly brighter. n(lambda): Cauchy fit through measured
// values for water (tools/tests/test_rainbow.py).
float rainbowAngle(float lambdaNm, bool secondary) {
    float n = 1.3242 + 3080.0 / (lambdaNm * lambdaNm);    // n(400 nm) = 1.3435, n(700 nm) = 1.3305
    float cosI = sqrt((n * n - 1.0) / (secondary ? 8.0 : 3.0));
    float i = acos(cosI);
    float r = asin(sin(i) / n);
    return secondary ? PI - (6.0 * r - 2.0 * i) : 4.0 * r - 2.0 * i;
}

// Approximate linear-RGB response to a spectral line (sums to white over the samples below).
vec3 spectralRgb(float lambdaNm) {
    vec3 c = vec3(exp(-sq((lambdaNm - 605.0) / 42.0)) + 0.3 * exp(-sq((lambdaNm - 445.0) / 22.0)),
                  exp(-sq((lambdaNm - 545.0) / 44.0)),
                  exp(-sq((lambdaNm - 455.0) / 32.0)));
    return c;
}

// Multiplier and additive light for a sky direction: (scale, added colour relative to the sky).
vec3 rainbowLight(vec3 dir, vec3 sunDir, out float skyScale) {
    skyScale = 1.0;
    #ifdef RAINBOWS
    // After rain with the air still wet; the sun out (not in a storm) and below 42 degrees.
    float vis = smoothstep(0.08, 0.35, wetness) * (1.0 - smoothstep(0.2, 0.6, rainStrength))
              * (1.0 - thunderStrength) * biomeWet
              * smoothstep(-0.02, 0.05, sunDir.y) * (1.0 - smoothstep(0.62, 0.68, sunDir.y));
    if (vis <= 0.001 || dir.y <= 0.0) return vec3(0.0);
    float ang = acos(clamp(dot(dir, -sunDir), -1.0, 1.0));
    const float WIDTH = 0.0105;              // ~0.6 deg: sun disk plus drop-size spread
    vec3 bow = vec3(0.0), norm = vec3(0.0);
    for (int k = 0; k < 7; k++) {
        float lam = 410.0 + float(k) * 48.0;
        vec3 rgb = spectralRgb(lam);
        norm += rgb;
        bow += rgb * exp(-sq((ang - rainbowAngle(lam, false)) / WIDTH));
        bow += rgb * 0.42 * exp(-sq((ang - rainbowAngle(lam, true)) / (WIDTH * 1.4)));
    }
    bow /= norm;
    float p = rainbowAngle(560.0, false), s = rainbowAngle(560.0, true);
    // Alexander's dark band and the brighter sky inside the primary.
    skyScale = 1.0 - vis * 0.18 * smoothstep(p + 0.01, p + 0.03, ang) * (1.0 - smoothstep(s - 0.03, s - 0.01, ang))
             + vis * 0.08 * (1.0 - smoothstep(p - 0.15, p - 0.01, ang));
    // Fade towards the ground, where the rain curtain thins out.
    return bow * vis * RAINBOW_STRENGTH * 0.55 * smoothstep(0.0, 0.08, dir.y);
    #else
    return vec3(0.0);
    #endif
}

// ---- aurora
// Emission curtains in the upper atmosphere: sheets folded along slowly drifting wavy lines, with
// fine vertical rays (striations along the magnetic field). The view ray is intersected with
// AURORA_SHELLS altitude shells between 100 and 280 km, so curtains converge towards the horizon
// and never shift as the player moves. Colour comes from altitude: atomic-oxygen green
// (557.7 nm) peaks near 110 km, the fainter red line (630 nm) dominates above ~200 km. Brightness
// is tied to the night-sky illuminance `k` (full-Moon units with the night lift), so it sits
// above airglow and the Milky Way without flooding the exposure. "Some nights" picks about one
// night in four from a hash of the day, fading in and out over the night.
const int AURORA_SHELLS = 8;

float auroraCurtain(vec2 p, float t) {
    // Two folded sheets, each a narrow band around a wavy line.
    float a = 0.0;
    for (int s = 0; s < 2; s++) {
        float fs = float(s);
        float line = 0.9 * sin(p.x * 0.55 + t * 0.03 + fs * 2.1) + 0.45 * sin(p.x * 1.37 - t * 0.05 + fs)
                   + (valueNoise(vec2(p.x * 0.8 + t * 0.02, fs * 7.0)) - 0.5) * 1.2 + fs * 2.4 - 1.2;
        float d = p.y - line;
        // Sharp lower edge, softer upper: curtains are brightest at their base.
        float band = exp(-sq(d) * (d > 0.0 ? 9.0 : 30.0));
        float rays = 0.45 + 0.55 * valueNoise(vec2(p.x * 9.0 + t * 0.15, fs * 3.0 + t * 0.02));
        a += band * rays;
    }
    return a;
}

vec3 auroraRadiance(vec3 dir, vec3 sunDir, float k) {
    #if AURORA > 0
    if (dir.y <= 0.0) return vec3(0.0);
    float dark = smoothstep(-0.10, -0.22, sunDir.y);
    #if AURORA == 1
    float day = float(worldDay) + float(worldTime) / 24000.0 + 0.5;    // the night spans two days
    float tonight = step(0.75, hash1(float(int(floor(day)))));
    float phase = fract(day);                                            // 0.25 .. 0.75 is night
    float activity = tonight * smoothstep(0.30, 0.42, phase) * (1.0 - smoothstep(0.62, 0.72, phase));
    #else
    float activity = 1.0;
    #endif
    float vis = dark * activity * (1.0 - rainStrength);
    if (vis <= 0.001) return vec3(0.0);
    float t = frameTimeCounter + float(worldTime) * 0.05;
    vec3 col = vec3(0.0);
    for (int i = 0; i < AURORA_SHELLS; i++) {
        float h = 100.0 + float(i) * (180.0 / float(AURORA_SHELLS - 1));   // km
        float dist = h / max(dir.y, 0.03);                                     // flat-shell approximation
        vec2 p = dir.xz * dist * 0.006;                                        // curtain coordinates
        float c = auroraCurtain(p, t);
        vec3 green = vec3(0.12, 1.0, 0.35) * exp(-max(h - 110.0, 0.0) / 45.0);
        vec3 red = vec3(1.0, 0.12, 0.25) * 0.35 * smoothstep(170.0, 240.0, h);
        col += c * (green + red);
    }
    // Longer path through the emitting layer near the horizon, faded at the very bottom.
    float path = min(1.0 / max(dir.y, 0.05), 6.0) * smoothstep(0.0, 0.06, dir.y);
    // Peak curtain radiance ~0.2 k: about twice moonlit ground, well below the Moon.
    return col * (path / float(AURORA_SHELLS)) * vis * k * 0.5 * AURORA_BRIGHTNESS;
    #else
    return vec3(0.0);
    #endif
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
    // Rainbow: relative to the sky light behind it, so it can never outshine the sky.
    float bowScale;
    vec3 bow = rainbowLight(dir, L.sunDir, bowScale);
    scatter = scatter * bowScale + bow * luminance(scatter);
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
    // The aurora emits at 100-280 km, above most of the air, like airglow.
    space += auroraRadiance(dir, L.sunDir, SUN_ILLUMINANCE * MOON_PHYSICAL_RATIO * L.skyGain);
    // Below the horizon the planet blocks space (transmittance is 0 there).
    return scatter + space * trans;
}

// `withDisks` adds the sun and moon disks (off for reflections of rough surfaces).
vec3 skyRadiance(vec3 dir, SkyLights L, float pixelAngle, bool withDisks) {
    return skyRadianceDisks(dir, L, pixelAngle, withDisks, withDisks);
}

#endif

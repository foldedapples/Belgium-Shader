#ifndef MERIDIAN_CELESTIAL
#define MERIDIAN_CELESTIAL

// Celestial geometry and light levels (player space, y up).
//
// The sun follows Minecraft's path (from sunPosition). The Moon is placed by an orbital model:
// its elongation from the sun follows the phase cycle (new moon beside the sun, full moon
// opposite), continuously through the day, and its orbit is inclined 5.1 degrees to the sun's
// path with nodes that regress over 18 lunar cycles. The Moon is lit by the actual sun direction,
// so phases, the terminator and the crescent's orientation come from geometry; eclipses happen
// when the bodies line up near a node.
//
// Brightness scale: TOA solar illuminance is SUN_ILLUMINANCE (arbitrary units; exposure adapts).
// Physical full-moon / sun illuminance is ~2.5e-6; nights are lifted by nightGain() so moonlit
// scenes stay playable (documented in docs/ARCHITECTURE.md, "Light levels").

const float sunPathRotation = -25.0;
const float SUN_ILLUMINANCE = 10.0 * SUN_BRIGHTNESS;
const float SUN_ANGULAR_RADIUS = 0.004654 * SUN_SIZE;      // 0.2666 deg
const float MOON_ANGULAR_RADIUS = 0.004521 * MOON_SIZE;    // 0.2590 deg
const float MOON_PHYSICAL_RATIO = 2.5e-6;                  // full moon / sun illuminance at Earth
const float NIGHT_GAIN_MAX = 450.0 * NIGHT_BRIGHTNESS;

// Night lift: 1 by day (the Moon and stars keep their physical radiance against the day sky),
// rising to NIGHT_GAIN_MAX once the sun is well below the horizon (a stand-in for the eye's
// dark adaptation, which spans far more than a display can show).
float nightGain(vec3 sunDir) { return mix(1.0, NIGHT_GAIN_MAX, smoothstep(0.04, -0.16, sunDir.y)); }
const float MOON_INCLINATION = 0.0890;                     // 5.1 deg
const float EARTH_UMBRA_RADIUS = 0.0120;                   // ~0.69 deg at the Moon's distance
const float EARTH_PENUMBRA_RADIUS = 0.0218;

vec3 sunDirection() { return celestialDirection(sunPosition); }

// Axis of the daily rotation of the sky in player space. With Iris's celestial matrix
// (rotate Y -90, rotate Z sunPathRotation, rotate X skyAngle) the sun moves on a great circle about
// (0, +-sin r, cos r). The sign convention of r is not documented, so begin.csh measures it from
// the observed sun direction while the sun is well away from the horizon (where the two
// candidates are clearly distinguishable) and stores it in state.lightBasis[0].w.
float celestialAxisSignFromSun(vec3 sunDir) {
    float r = radians(sunPathRotation);
    float d1 = abs(dot(vec3(0.0, sin(r), cos(r)), sunDir));
    float d2 = abs(dot(vec3(0.0, -sin(r), cos(r)), sunDir));
    return abs(d1 - d2) > 0.05 ? (d1 < d2 ? 1.0 : -1.0) : 0.0;   // 0: undecidable now
}

vec3 celestialAxis() {
    float r = radians(sunPathRotation);
    float sgn = 1.0;
    #ifdef MERIDIAN_STATE
    if (state.lightBasis[0].w != 0.0) sgn = sign(state.lightBasis[0].w);
    #endif
    return vec3(0.0, sgn * sin(r), cos(r));
}

// Continuous position in the 8-day phase cycle: 0 full, 4 new.
float lunarCycle() {
    return mod(float(worldDay) + float(worldTime) / 24000.0, 8.0);
}

vec3 moonDirection() {
    vec3 s = sunDirection();
    vec3 a = celestialAxis();
    float cyc = lunarCycle();
    // Elongation east of the sun: 180 deg at full, 0 at new. Waxing moon trails the sun.
    float elong = PI * abs(4.0 - cyc) / 4.0;
    float side = cyc < 4.0 ? 1.0 : -1.0;      // waning (0..4) leads the sun, waxing (4..8) trails
    vec3 m = rotateAxis(s, a, side * elong);
    // Ecliptic latitude from the inclined orbit; the node regresses once every 144 days.
    #ifdef ECLIPSES
    float node = TAU * (float(worldDay) + float(worldTime) / 24000.0) / 144.0;
    float lat = MOON_INCLINATION * sin(cyc / 8.0 * TAU + node);
    #else
    float lat = MOON_INCLINATION * 1.2;
    #endif
    vec3 b = normalize(cross(a, m));
    return normalize(rotateAxis(m, b, lat));
}

// Lunar phase angle (sun-moon-observer) and the brightness law of the Moon (Allen 1973:
// magnitude rises by 0.026 |a| + 4e-9 a^4 with a in degrees).
float moonPhaseAngle(vec3 sunDir, vec3 moonDir) { return acos(clamp(-dot(sunDir, moonDir), -1.0, 1.0)); }

float moonPhaseBrightness(float phaseAngle) {
    float a = degrees(phaseAngle);
    return pow(10.0, -0.4 * (0.026 * a + 4.0e-9 * a * a * a * a));
}

// Area fraction of disk 1 (radius r1) covered by disk 2 (radius r2) at centre distance d.
float diskOverlap(float r1, float r2, float d) {
    if (d >= r1 + r2) return 0.0;
    if (d <= abs(r2 - r1)) return r2 >= r1 ? 1.0 : (r2 * r2) / (r1 * r1);
    float a1 = r1 * r1 * acos(clamp((d * d + r1 * r1 - r2 * r2) / (2.0 * d * r1), -1.0, 1.0));
    float a2 = r2 * r2 * acos(clamp((d * d + r2 * r2 - r1 * r1) / (2.0 * d * r2), -1.0, 1.0));
    float a3 = 0.5 * sqrt(max((-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2), 0.0));
    return (a1 + a2 - a3) / (PI * r1 * r1);
}

// Fraction of the solar disk still visible (solar eclipse).
float solarVisibility(vec3 sunDir, vec3 moonDir) {
    #ifdef ECLIPSES
    float d = acos(clamp(dot(sunDir, moonDir), -1.0, 1.0));
    return 1.0 - diskOverlap(SUN_ANGULAR_RADIUS, MOON_ANGULAR_RADIUS, d);
    #else
    return 1.0;
    #endif
}

// Light reaching the Moon through Earth's shadow (lunar eclipse): 1 outside, deep red inside.
vec3 lunarEclipseFactor(vec3 sunDir, vec3 moonDir) {
    #ifdef ECLIPSES
    float d = acos(clamp(-dot(sunDir, moonDir), -1.0, 1.0));
    float pen = smoothstep(EARTH_UMBRA_RADIUS, EARTH_PENUMBRA_RADIUS, d);
    float umbra = smoothstep(EARTH_UMBRA_RADIUS - MOON_ANGULAR_RADIUS, EARTH_UMBRA_RADIUS + MOON_ANGULAR_RADIUS, d);
    // Inside the umbra only light refracted through Earth's atmosphere arrives: reddened, ~1e-3.
    vec3 refracted = vec3(0.012, 0.0035, 0.0012);
    return mix(refracted, vec3(1.0), umbra) * mix(0.55, 1.0, pen);
    #else
    return vec3(1.0);
    #endif
}

struct SkyLights {
    vec3 sunDir;
    vec3 moonDir;
    vec3 lightDir;      // shadow-casting light (sun by day, moon by night)
    float sunIllum;     // TOA solar illuminance after eclipse
    vec3 moonIllum;     // illuminance from the Moon at the top of the atmosphere (night-gained)
    vec3 moonFullIllum; // the same without the phase law (for shading the disk itself)
    float moonPhase;    // phase angle, radians
    bool sunIsLight;
    float skyGain;      // night lift for sky light (stars, airglow): stronger without the Moon
};

SkyLights skyLights() {
    SkyLights s;
    s.sunDir = sunDirection();
    s.moonDir = moonDirection();
    s.moonPhase = moonPhaseAngle(s.sunDir, s.moonDir);
    s.sunIllum = SUN_ILLUMINANCE * solarVisibility(s.sunDir, s.moonDir);
    // The Moon reflects sunlight; its own albedo is slightly red (LRO WAC mean colour).
    vec3 lunarTint = vec3(1.0, 0.93, 0.84);
    s.moonFullIllum = SUN_ILLUMINANCE * MOON_PHYSICAL_RATIO * nightGain(s.sunDir) * MOON_BRIGHTNESS *
                      lunarTint * lunarEclipseFactor(s.sunDir, s.moonDir);
    s.moonIllum = s.moonFullIllum * moonPhaseBrightness(s.moonPhase);
    // Dark adaptation goes further on moonless nights; the faint sky light (airglow, stars) is
    // lifted up to 8x more when the Moon is new or below the horizon. Moonlight itself is not.
    float moonPresence = moonPhaseBrightness(s.moonPhase) * smoothstep(-0.05, 0.10, s.moonDir.y);
    s.skyGain = nightGain(s.sunDir) * mix(1.0, 8.0, (1.0 - moonPresence) * smoothstep(0.0, -0.2, s.sunDir.y));
    s.sunIsLight = s.sunDir.y > -0.03 || s.moonDir.y < 0.0;
    s.lightDir = s.sunIsLight ? s.sunDir : s.moonDir;
    // Moonlight fades in after the switch so moon shadows never pop at dusk.
    s.moonIllum *= smoothstep(-0.03, -0.12, s.sunDir.y) * smoothstep(-0.02, 0.06, s.moonDir.y);
    return s;
}

// Sidereal rotation of the star sphere: the sky turns once per day around the celestial axis,
// plus the yearly drift (stars rise ~4 minutes earlier each day). Returns a matrix taking
// player-space directions to equatorial coordinates (x towards RA 0h, z north pole).
mat3 equatorialFromPlayer() {
    vec3 pole = celestialAxis();
    float daysF = float(worldDay) + float(worldTime) / 24000.0;
    float angle = sunAngle * TAU + daysF * TAU / 365.25;
    vec3 ref = normalize(cross(pole, vec3(1.0, 0.0, 0.0)));
    ref = rotateAxis(ref, pole, -angle);
    vec3 third = cross(pole, ref);
    return transpose(mat3(ref, third, pole));
}

#endif

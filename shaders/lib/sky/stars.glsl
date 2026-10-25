#ifndef SKY_STARS_GLSL
#define SKY_STARS_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

// Procedural night sky (ORIGINAL_ARCHITECTURE.md sec. 9). No catalogue or image is used.
//
// Stars: each cell of a cube-mapped grid in the celestial frame may hold one star at a
// random position. Magnitudes follow the cumulative count law N(<m) ~ 10^(0.5 m) up to the
// limiting magnitude, colours come from Planck's law at a randomly drawn temperature, and
// each star is drawn with an energy-normalised Gaussian PSF evaluated analytically per pixel,
// so positions are stable to sub-pixel accuracy while the camera moves.
//
// Brightness scale: Vega (m = 0) is 8.3e-6 of the full moon's irradiance, as in reality.
// NIGHT_SKY_BRIGHTNESS then multiplies stars and the Milky Way together to compensate for
// display range and the eye's dark adaptation, which the exposure limits cannot reproduce.

const float STAR_LIMIT_MAG = 6.8;
const float VEGA_FRACTION_OF_FULL_MOON = 8.3e-6;

// Celestial frame: undo the diurnal rotation so the stars turn with the sun around the
// celestial axis.
vec3 toCelestial(vec3 dir) {
    return rotateAxis(dir, fsCelestialAxis.xyz, -TAU * sunAngle);
}

// Cube-face projection: face index and coordinates in [0,1]^2.
void cubeFace(vec3 d, out int face, out vec2 uv) {
    vec3 a = abs(d);
    if (a.x >= a.y && a.x >= a.z) { face = d.x > 0.0 ? 0 : 1; uv = d.zy / a.x; }
    else if (a.y >= a.z)          { face = d.y > 0.0 ? 2 : 3; uv = d.xz / a.y; }
    else                          { face = d.z > 0.0 ? 4 : 5; uv = d.xy / a.z; }
    uv = uv * 0.5 + 0.5;
}

vec3 cubeFaceDir(int face, vec2 uv) {
    vec2 p = uv * 2.0 - 1.0;
    if (face == 0) return normalize(vec3(1.0, p.y, p.x));
    if (face == 1) return normalize(vec3(-1.0, p.y, p.x));
    if (face == 2) return normalize(vec3(p.x, 1.0, p.y));
    if (face == 3) return normalize(vec3(p.x, -1.0, p.y));
    if (face == 4) return normalize(vec3(p.x, p.y, 1.0));
    return normalize(vec3(p.x, p.y, -1.0));
}

vec3 starField(vec3 dirCelestial, float pixelAngle, float airmassFactor) {
    const int CELLS = 180 * BE_STAR_DENSITY;
    int face; vec2 uv;
    cubeFace(dirCelestial, face, uv);
    vec2 g = uv * float(CELLS);
    ivec2 base = ivec2(floor(g - 0.5));
    float fullMoonE = SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO;
    float sigma = max(pixelAngle * 0.75, 1e-5);       // PSF width ~ 0.75 px
    float norm = 1.0 / (TAU * sigma * sigma);
    vec3 total = vec3(0.0);
    for (int y = 0; y <= 1; y++) for (int x = 0; x <= 1; x++) {
        ivec2 c = clamp(base + ivec2(x, y), ivec2(0), ivec2(CELLS - 1));
        uint h = hashU(uvec3(uvec2(c), uint(face) * 7919u + 17u));
        float occupancy = u32ToUnit(h);
        // ~7% occupancy: ~13k stars brighter than m = 6.8 per sky at density 1 (the real
        // naked-eye count is of the same order).
        if (occupancy > 0.07) continue;
        uint h2 = hashU(h);
        uint h3 = hashU(h2);
        vec2 jitter = vec2(u32ToUnit(h2), u32ToUnit(h3)) * 0.8 + 0.1;
        vec3 sd = cubeFaceDir(face, (vec2(c) + jitter) / float(CELLS));
        float ang = acos(clamp(dot(sd, dirCelestial), -1.0, 1.0));
        if (ang > sigma * 5.0) continue;
        // Cumulative count ~ 10^(0.5 m): m = m_lim + 2 log10(u).
        float u = max(u32ToUnit(hashU(h3)), 1e-6);
        float mag = STAR_LIMIT_MAG + 2.0 * log(u) / log(10.0);
        mag = max(mag, -1.4);
        float flux = VEGA_FRACTION_OF_FULL_MOON * fullMoonE * pow(10.0, -0.4 * mag);
        float temp = mix(3200.0, 11000.0, pow(u32ToUnit(hashU(h3 ^ 0x5bd1e995u)), 1.6));
        vec3 colour = blackbody(temp);
        // Scintillation grows with airmass; kept subtle so TAA does not smear it.
        float tw = 1.0;
        #ifdef STAR_TWINKLE
            float phase = u32ToUnit(h2 ^ h3) * TAU;
            tw = 1.0 + 0.35 * airmassFactor * sin(frameTimeCounter * 9.0 + phase) * sin(frameTimeCounter * 5.3 + phase * 1.7);
        #endif
        total += colour * flux * norm * exp(-0.5 * sq(ang / sigma)) * tw;
    }
    return total;
}

// Milky Way: band around a galactic plane tilted 62 deg from the celestial axis, a bulge
// toward the galactic centre, star-cloud structure and a dust rift from fbm noise.
vec3 milkyWay(vec3 dirCelestial) {
    vec3 axis = vec3(0.0, 0.0, 1.0);
    vec3 pole = normalize(vec3(0.0, cos(radians(62.0)), sin(radians(62.0))));
    vec3 centreDir = normalize(cross(pole, vec3(1.0, 0.0, 0.0)));
    float b = asin(clamp(dot(dirCelestial, pole), -1.0, 1.0));          // galactic latitude
    vec3 inPlane = dirCelestial - pole * dot(dirCelestial, pole);
    float l = atan(dot(inPlane, cross(pole, centreDir)), dot(inPlane, centreDir)); // longitude
    float width = radians(9.0) + radians(7.0) * exp(-sq(l / 0.6));
    float disk = exp(-sq(b / width));
    float bulge = exp(-sq(l / 0.55) - sq(b / radians(11.0)));
    vec3 p = dirCelestial * 6.0;
    float clouds = valueNoise(p) * 0.5 + valueNoise(p * 2.1) * 0.3 + valueNoise(p * 4.3) * 0.2;
    float rift = smoothstep(0.45, 0.75, valueNoise(p * 1.7 + 3.1) * 0.6 + valueNoise(p * 3.9) * 0.4);
    float riftMask = exp(-sq(b / radians(3.5))) * rift;
    float brightness = (disk * (0.35 + 0.65 * clouds) + bulge * 1.6) * (1.0 - 0.85 * riftMask);
    vec3 colour = mix(blackbody(7000.0), blackbody(4300.0), saturate(bulge * 1.5));
    float fullMoonE = SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO;
    // Peak surface brightness ~ mag 20.5 per square arcsecond relative to Vega.
    float peak = VEGA_FRACTION_OF_FULL_MOON * fullMoonE * pow(10.0, -0.4 * 20.5) / 2.35e-11;
    return colour * brightness * peak * MILKY_WAY_BRIGHTNESS;
}

#ifdef MILKY_WAY_TEXTURE
// NASA SVS Deep Star Maps 2020 (svs.gsfc.nasa.gov/4851), Milky Way layer without the bright
// Hipparcos/Tycho stars (those are the procedural star field above). Plate carree in RA/Dec:
// u = 0.5 - RA / 2pi, v = 0.5 - Dec / pi (verified from the data, tools/prep_milkyway.py),
// stored as linear^(1/3).
uniform sampler2D beMilkyWayTex;

// Right ascension of the sun. The sun keeps a fixed place among the stars in this model; at
// RA 6h (June solstice) the galactic centre culminates near midnight, as in a real summer sky.
const float MW_SUN_RA = HALF_PI;

vec3 milkyWayNasa(vec3 dirCelestial) {
    // The sky turns by +angle about fsCelestialAxis, i.e. clockwise seen from outside above
    // -fsCelestialAxis: that is the north celestial pole, and RA grows anticlockwise about it.
    vec3 north = -fsCelestialAxis.xyz;
    vec3 s = toCelestial(fsSunDir.xyz);
    vec3 ref = safeNormalize(s - north * dot(s, north));      // RA of the sun
    vec3 east = cross(north, ref);                            // RA of the sun + 6h
    float dec = asin(clamp(dot(dirCelestial, north), -1.0, 1.0));
    float ra = MW_SUN_RA + atan(dot(dirCelestial, east), dot(dirCelestial, ref));
    vec2 uv = vec2(fract(0.5 - ra * INV_TAU), 0.5 - dec * INV_PI);
    vec3 v = texture(beMilkyWayTex, uv).rgb;
    vec3 linear = v * v * v;
    // Scale: the map's bright star clouds (99th percentile 0.193) are the Milky Way's peak
    // surface brightness, ~mag 20.5 per square arcsecond, as in the procedural model.
    float fullMoonE = SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO;
    float peak = VEGA_FRACTION_OF_FULL_MOON * fullMoonE * pow(10.0, -0.4 * 20.5) / 2.35e-11;
    return linear * (peak / 0.193) * MILKY_WAY_BRIGHTNESS;
}
#endif

vec3 nightSky(vec3 dir, float pixelAngle) {
    if (dir.y < -0.05) return vec3(0.0);
    vec3 c = toCelestial(dir);
    float airmass = 1.0 / max(dir.y + 0.08, 0.08);
    float airmassFactor = saturate((airmass - 1.0) / 6.0);
    #ifdef MILKY_WAY_TEXTURE
        vec3 sky = starField(c, pixelAngle, airmassFactor) + milkyWayNasa(c);
    #else
        vec3 sky = starField(c, pixelAngle, airmassFactor) + milkyWay(c);
    #endif
    // The diffuse night-sky background (airglow) is part of skyRadiance() (sky_view.glsl).
    return sky * NIGHT_SKY_BRIGHTNESS;
}

#endif

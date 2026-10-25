#ifndef SKY_AURORA_GLSL
#define SKY_AURORA_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/post/color_profile.glsl"

// Aurora (ORIGINAL_ARCHITECTURE.md sec. 9). Emission-only volume between 95 and 320 km.
// Curtains are thin sheets around meandering east-west curves placed poleward of the
// observer (north = -Z in Minecraft); fine vertical rays come from 1-D noise along each
// curve. The spectrum follows the dominant auroral lines: atomic-oxygen green (557.7 nm)
// peaking near 110 km, oxygen red (630 nm) high up near 200-260 km, and an occasional
// N2+ blue-violet fringe at the lower edge during strong displays.
// Activity (fsWeather.w, 0..1) is decided per night in begin.csh.

const float AURORA_BOTTOM = 95.0;
const float AURORA_TOP = 320.0;

float auroraNoise1(float x) {
    float i = floor(x), f = x - i;
    float u = f * f * (3.0 - 2.0 * f);
    return mix(hash11(uint(int(i) + 4096)), hash11(uint(int(i) + 4097)), u);
}

float auroraFbm1(float x) {
    return auroraNoise1(x) * 0.5 + auroraNoise1(x * 2.13 + 7.1) * 0.3 + auroraNoise1(x * 4.37 + 3.3) * 0.2;
}

vec3 auroraSpectrum(float altitude, float intensity) {
    float green = exp(-sq((altitude - 112.0) / 22.0)) + 0.25 * exp(-sq((altitude - 150.0) / 45.0));
    float red = exp(-sq((altitude - 230.0) / 55.0)) * mix(0.25, 0.9, smoothstep(0.6, 1.0, intensity));
    float violet = exp(-sq((altitude - 98.0) / 6.0)) * smoothstep(0.7, 1.0, intensity);
    // AURORA_HIGH_EMISSION scales the red oxygen and violet nitrogen lines against the green.
    red *= AURORA_HIGH_EMISSION;
    violet *= AURORA_HIGH_EMISSION;
    return vec3(0.12, 1.0, 0.35) * green + vec3(1.0, 0.12, 0.08) * red + vec3(0.55, 0.25, 1.0) * violet;
}

// Horizontal position (km, x east / y north) -> curtain emission factor and ray coordinate.
float curtainField(vec2 pKm, float t, float activity) {
    float sum = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float north = mix(260.0, 70.0, activity) + fi * 55.0;          // poleward distance
        float x = pKm.x / 180.0 + fi * 3.7;
        float meander = (auroraFbm1(x + t * 0.04 * AURORA_SPEED + fi * 11.0) - 0.5) * 160.0;
        float d = pKm.y - (north + meander);
        float thickness = 3.0 + 6.0 * auroraFbm1(x * 3.0 + fi);
        // Sheets are sharp on the poleward side and diffuse toward the equator.
        float sheet = d > 0.0 ? exp(-sq(d / thickness)) : exp(-sq(d / (thickness * 4.0)));
        float rays = pow(auroraNoise1(pKm.x * 0.9 + fi * 40.0 + t * 0.6 * AURORA_SPEED), 3.0) * 0.8 + 0.2;
        float envelope = smoothstep(0.15, 0.6, auroraFbm1(x * 0.6 + 5.0 + fi * 2.0 + t * 0.01));
        sum += sheet * rays * envelope;
    }
    return sum;
}

vec3 auroraRadiance(vec3 dir, float jitter) {
    float activity = fsWeather.w;
    if (activity <= 0.0 || dir.y < -0.02) return vec3(0.0);
    float r0 = ATM_GROUND + cameraAltitudeKm(cameraPosition.y);
    vec3 ro = vec3(0.0, r0, 0.0);
    vec2 inner = raySphere(ro, dir, ATM_GROUND + AURORA_BOTTOM);
    vec2 outer = raySphere(ro, dir, ATM_GROUND + AURORA_TOP);
    float t0 = max(inner.y, 0.0);
    float t1 = outer.y;
    if (t1 <= t0) return vec3(0.0);
    // Long grazing paths near the horizon: cap the march length but keep the brightness.
    t1 = min(t1, t0 + 1600.0);
    float dt = (t1 - t0) / float(AURORA_STEPS);
    float time = frameTimeCounter;
    vec3 sum = vec3(0.0);
    for (int i = 0; i < AURORA_STEPS; i++) {
        float t = t0 + (float(i) + jitter) * dt;
        vec3 p = ro + dir * t;
        float alt = length(p) - ATM_GROUND;
        // North is -Z in Minecraft.
        vec2 hz = vec2(p.x, -p.z);
        float field = curtainField(hz, time, activity);
        if (field > 1e-3) sum += auroraSpectrum(alt, activity) * field * dt;
    }
    // Airglow-relative scale: a strong display is a few times brighter than the Milky Way.
    float fullMoonE = SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO;
    return sum * fullMoonE * 1.5e-6 * AURORA_BRIGHTNESS * CP_AURORA * activity * NIGHT_SKY_BRIGHTNESS;
}

#endif

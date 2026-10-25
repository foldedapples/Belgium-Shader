#ifndef CLOUDS_CIRRUS_GLSL
#define CLOUDS_CIRRUS_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/core/phase_functions.glsl"

// Cirrus / cirrostratus: a thin ice layer at ~8 km drawn as a single 2-D slice (no volume
// cost). Streaks are fBm stretched along the wind; ice crystals scatter strongly forward.

#include "/lib/core/textures.glsl"

const float CIRRUS_ALTITUDE = 8000.0;

// Returns in-scattered radiance (rgb) and transmittance (a) of the layer along `dir`.
// `pixelAngle` is the angular size of a pixel. Without band limiting the 8 km slice is
// minified ~20x near the horizon (custom textures have no mipmaps): the thresholded noise
// turns into isolated specks that the forward-scattering phase makes very bright near the
// sun (seen in game as a dotted white streak pointing at the sun). Each octave fades to its
// mean once the pixel footprint reaches half its dominant feature size, and the coverage
// threshold widens by the removed amplitude so distant cirrus becomes haze, not nothing.
// noise2d channel g/b/a: dominant features 32/16/8 texels of a 256-texel period.
float cirrusOctave(vec2 q, float period, float featureTexels, float footprint, int channel, inout float removed, float amp) {
    float feature = period * featureTexels / 256.0;
    float keep = 1.0 - smoothstep(0.25, 0.5, footprint / feature);
    removed += amp * (1.0 - keep);
    if (keep <= 0.0) return 0.5;
    vec4 s = texture(noise2dTex, q / period);
    float v = channel == 1 ? s.g : (channel == 2 ? s.b : s.a);
    return mix(0.5, v, keep);
}

// 22 degree halo of randomly oriented hexagonal ice prisms: light is concentrated at the
// angle of minimum deviation (21.84 deg) with a sharp inner edge and a slow outer decay; the
// inner edge is reddish because red refracts least. Relative to the phase function (sr^-1).
vec3 iceHalo(float cosTheta) {
    float a = degrees(acos(clamp(cosTheta, -1.0, 1.0)));
    if (a < 20.5 || a > 32.0) return vec3(0.0);
    float edge = smoothstep(21.3, 21.95, a);
    float profile = edge * (exp(-sq((a - 22.0) / 0.55)) * 0.8 + exp(-(a - 22.0) / 3.5) * 0.25);
    vec3 tint = mix(vec3(1.0, 0.78, 0.62), vec3(0.86, 0.92, 1.0), smoothstep(21.8, 23.5, a));
    return tint * profile * 0.06;
}

// `amount` is the cover (Belgium: CIRRUS_AMOUNT, Halcyon: from CIRRUS_COVERAGE), `windScale`
// multiplies the drift with the cloud wind.
vec4 cirrusLayer(vec3 dir, vec3 lightDir, vec3 lightIrradiance, vec3 ambient, float pixelAngle, float amount, float windScale) {
    if (dir.y <= 0.01 || amount <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);
    float t = (CIRRUS_ALTITUDE - cameraPosition.y) / dir.y;
    vec2 xz = mod(cameraPosition.xz, 65536.0) + dir.xz * t;
    float a = radians(WATER_WIND_ANGLE);
    vec2 along = vec2(cos(a), sin(a));
    vec2 across = vec2(-along.y, along.x);
    // Anisotropic coordinates: streaks are ~6x longer along the wind.
    vec2 q = vec2(dot(xz, along) / 6.0, dot(xz, across)) + fsCloudWind.xy * 0.6 * windScale;
    // Pixel footprint on the layer (elongated along the view azimuth by 1/dir.y; conservative).
    float footprint = t * pixelAngle / max(dir.y, 0.05);
    float removed = 0.0;
    float n = cirrusOctave(q, 9000.0, 32.0, footprint, 1, removed, 0.55) * 0.55
            + cirrusOctave(q, 2600.0, 16.0, footprint, 2, removed, 0.3) * 0.3
            + cirrusOctave(q, 700.0, 8.0, footprint, 3, removed, 0.15) * 0.15;
    float cover = amount * (0.6 + 0.4 * fsCloud.x);
    float lo = 1.0 - cover * 0.75;
    float spread = removed * 0.45;
    float density = smoothstep(lo - spread, lo + 0.25 + spread, n);
    // Fade toward the horizon where the slice would alias.
    density *= smoothstep(0.01, 0.12, dir.y);
    float tau = density * 0.35;
    float trans = exp(-tau);
    float cosT = dot(dir, lightDir);
    float phase = mix(henyeyGreenstein(cosT, 0.7), INV_PI * 0.25, 0.4);
    vec3 scatter = (lightIrradiance * (phase + iceHalo(cosT)) + ambient * INV_PI * 0.6) * (1.0 - trans);
    return vec4(scatter, trans);
}

#endif

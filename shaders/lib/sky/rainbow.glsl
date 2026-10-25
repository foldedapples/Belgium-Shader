#ifndef SKY_RAINBOW_GLSL
#define SKY_RAINBOW_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"

// Rainbows from geometric optics. For a sphere of index n the deviation after k internal
// reflections, D(i) = 2(i - r) + k(pi - 2r), is stationary where cos^2 i = (n^2 - 1)/(k^2 + 2k)
// (Descartes). The bow sits at pi - D_min from the antisolar point (primary, k = 1) and at
// D_min - pi (secondary, k = 2, colours reversed). Dispersion of water at 650/550/450 nm gives
// the colour separation; the sun's disk and the drop-size spread give the band width.

float bowAngle(float n, float k) {
    float cosI = sqrt((n * n - 1.0) / (k * k + 2.0 * k));
    float i = acos(cosI);
    float r = asin(sin(i) / n);
    float d = 2.0 * (i - r) + k * (PI - 2.0 * r);
    return k == 1.0 ? PI - d : d - PI;
}

// Rainbow radiance for view direction `dir`. `sunlit` is the visibility of the sun from the
// rain curtain (cloud shadow), `rain` the rain intensity, `distanceFade` 0..1 how much rain
// lies in front of the background (1 for sky).
vec3 rainbowRadiance(vec3 dir, vec3 sunIrradiance, float sunlit, float rain, float distanceFade) {
    if (rain <= 0.0 || fsSunDir.y < -0.02 || RAINBOW_BRIGHTNESS <= 0.0) return vec3(0.0);
    vec3 anti = -fsSunDir.xyz;
    float theta = acos(clamp(dot(dir, anti), -1.0, 1.0));
    if (theta < 0.6 || theta > 0.98) return vec3(0.0);
    const vec3 n = vec3(1.3311, 1.3345, 1.3395);
    vec3 p1 = vec3(bowAngle(n.r, 1.0), bowAngle(n.g, 1.0), bowAngle(n.b, 1.0));
    vec3 p2 = vec3(bowAngle(n.r, 2.0), bowAngle(n.g, 2.0), bowAngle(n.b, 2.0));
    float width = radians(0.55) + fsCelestialAxis.w;
    vec3 primary = exp(-0.5 * sq((theta - p1) / width));
    vec3 secondary = exp(-0.5 * sq((theta - p2) / (width * 1.3))) * 0.42;
    // Inside the primary bow the sky is slightly brighter (light at all larger deviations).
    float inner = smoothstep(p1.g + 0.02, p1.g - 0.25, theta) * 0.06;
    vec3 bow = primary + secondary + vec3(inner);
    // Rain must be lit by the sun and the sun low enough for the bow to clear the horizon.
    float strength = rain * sunlit * distanceFade * smoothstep(0.75, 0.45, fsSunDir.y);
    return bow * sunIrradiance * strength * 0.004 * RAINBOW_BRIGHTNESS;
}

#endif

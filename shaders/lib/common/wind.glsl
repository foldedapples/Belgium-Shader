#ifndef MERIDIAN_WIND
#define MERIDIAN_WIND

// One wind model shared by plants, rain, clouds and water so they agree on direction and
// strength. Direction drifts slowly over in-game days; storms strengthen and gust it.

vec2 windDirection() {
    float a = 0.6 + 0.35 * sin(float(worldDay) * 1.7 + float(worldTime) * 2.6e-4);
    return vec2(cos(a), sin(a));
}

// 0..1 nominal wind strength (calm ~0.15, rain ~0.55, thunder ~1).
float windStrength() {
    return 0.15 + 0.40 * rainStrength + 0.45 * thunderStrength;
}

// Gust factor at a world position: slow travelling waves along the wind direction.
float windGust(vec3 worldPos, float t) {
    vec2 d = windDirection();
    float along = dot(worldPos.xz, d);
    float g = sin(along * 0.045 - t * 1.3) * 0.5 + 0.5;
    g = g * g * (0.6 + 0.4 * sin(along * 0.11 + worldPos.y * 0.05 - t * 2.1));
    return 0.55 + 0.9 * g;
}

// Displacement for vegetation vertices. `anchor` is 0 at a rooted vertex and 1 at a free one.
vec3 plantSway(vec3 worldPos, float anchor, float stiffness, float t) {
    if (anchor <= 0.0) return vec3(0.0);
    vec2 d = windDirection();
    float s = windStrength() * windGust(worldPos, t);
    float phase = dot(worldPos, vec3(1.7, 0.9, 1.3));
    vec2 sway = d * (0.06 + 0.10 * s) * (0.5 + 0.5 * sin(t * (1.6 + s) + phase));
    sway += vec2(-d.y, d.x) * 0.025 * s * sin(t * 3.1 + phase * 1.7);
    sway *= anchor / stiffness;
    return vec3(sway.x, -0.25 * dot(sway, sway), sway.y);
}

vec3 leafFlutter(vec3 worldPos, float t) {
    float s = windStrength() * windGust(worldPos, t);
    vec3 p = worldPos * vec3(1.3, 1.1, 1.7);
    vec3 o = vec3(sin(t * 2.3 + p.x + p.y), sin(t * 1.9 + p.z * 1.3) * 0.5, cos(t * 2.1 + p.z + p.x * 0.7));
    vec2 d = windDirection();
    return (o * 0.03 + vec3(d.x, 0.0, d.y) * 0.02 * (sin(t * 1.2 + p.x * 0.2) + 1.0)) * (0.3 + s);
}

#endif

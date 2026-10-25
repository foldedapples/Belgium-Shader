#ifndef ATMOSPHERE_FOG_GLSL
#define ATMOSPHERE_FOG_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

// Overworld aerial perspective: transmittance of a scaled exponential atmosphere along the
// view segment and in-scatter approximated as horizon-clamped sky radiance x (1 - T).
// AERIAL_PERSPECTIVE scales distances so a few hundred blocks read like kilometres of air
// (artistic; Minecraft view distances are short).

#ifdef SKY_VIEW_READ
vec3 aerialPerspective(vec3 color, vec3 scenePos, float sceneDistance) {
    vec3 dir = safeNormalize(scenePos);
    float camAlt = cameraAltitudeKm(cameraPosition.y);
    float dKm = sceneDistance * 1e-3 * AERIAL_PERSPECTIVE;
    float midAlt = max(camAlt + dir.y * dKm * 0.5 / max(AERIAL_PERSPECTIVE, 1.0), 0.0);
    AtmosphereSample a = sampleAtmosphere(midAlt);
    // Rain thickens low aerosols.
    float haze = 1.0 + fsWeather.z * 6.0 + fsWeather.y * 6.0;
    vec3 ext = a.rayleigh + vec3(MIE_EXTINCTION) * exp(-midAlt / MIE_HEIGHT) * haze;
    vec3 T = exp(-ext * dKm);
    vec3 skyDir = normalize(vec3(dir.x, max(dir.y, 0.03), dir.z));
    vec3 inscatter = skyRadiance(skyDir);
    return color * T + inscatter * (1.0 - T);
}

// Hides the edge of loaded terrain by blending to the sky over the last part of the render
// distance.
vec3 borderFog(vec3 color, vec3 scenePos, float sceneDistance, float renderDistance) {
    float t = smoothstep(renderDistance * 0.78, renderDistance * 0.98, length(scenePos.xz));
    if (t <= 0.0) return color;
    vec3 dir = safeNormalize(scenePos);
    vec3 skyDir = normalize(vec3(dir.x, max(dir.y, 0.0), dir.z));
    return mix(color, skyRadiance(skyDir), t);
}
#endif

#endif

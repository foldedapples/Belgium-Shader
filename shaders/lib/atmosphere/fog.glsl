#ifndef MERIDIAN_FOG
#define MERIDIAN_FOG

// Participating media along view rays inside the playable world.
//
// Two components:
//  * Air: the same Rayleigh + aerosol atmosphere as the sky, applied at exaggerated scale for
//    in-game distances (a 256-block view would otherwise show almost no aerial perspective).
//    For long paths the in-scatter tends to the sky radiance near the horizon, which is what an
//    observer sees for an infinitely long horizontal path; we use that as the asymptote.
//  * Haze/mist: a low, height-limited aerosol layer whose density follows the weather (rain,
//    thunder), the time of day (morning mist in humid biomes) and caves (dust). It is what makes
//    light shafts visible; the volumetric pass marches it with shadow-map visibility.
// Requires atmosphere.glsl (with samplers), celestial.glsl.

// Effective in-game distance for aerial perspective: exaggerated near, compressed far, so LOD
// terrain at kilometres still reads.
float aerialDistance(float d) {
    return d * (6.0 * AERIAL_PERSPECTIVE) / (1.0 + d / 3000.0);
}

// Mist phase function: a broad forward lobe plus a little back-scatter. Real droplet scattering is
// more forward-peaked (g ~ 0.8), but at game exposures a g = 0.72 lobe turned the 20 degrees around
// a low sun into a blown-out disc (docs/REGRESSION_AUDIT.md, R6); g = 0.6 keeps the shafts
// directional while halving the peak.
float hazePhase(float cosTheta) {
    return mix(phaseMie(cosTheta, 0.6), phaseMie(cosTheta, -0.15), 0.4);
}

// Haze extinction (per block) at a world height.
float hazeDensity(float worldY) {
    float morning = smoothstep(0.98, 1.0, sunAngle) + (1.0 - smoothstep(0.0, 0.08, sunAngle));
    float humid = saturate(rainfall * 1.2) * (1.0 - biomeSnowy * 0.3);
    float base = 1.2e-4 + 1.6e-3 * rainStrength + 1.0e-3 * thunderStrength + 0.8e-3 * morning * humid;
    float h = max(worldY - 63.0, 0.0);
    float profile = exp(-h / mix(60.0, 140.0, rainStrength));
    return base * profile * HAZE_DENSITY;
}

// Analytic air + haze for a straight path of `dist` blocks from the camera along `dir`.
// Returns in-scatter in rgb and mean transmittance in a.
vec4 aerialPerspective(vec3 dir, float dist, SkyLights L, bool includeHaze) {
    float camAlt = max(cameraPosition.y - 62.0, 1.0);
    Medium m = mediumAt(camAlt, aerosolFactor());
    float dEff = aerialDistance(dist);
    vec3 tAir = exp(-m.extinction * dEff);
    // Haze: integrate the exponential height profile analytically along the ray.
    float y0 = cameraPosition.y, dy = dir.y * dist;
    float H = mix(60.0, 140.0, rainStrength);
    float hz0 = hazeDensity(y0);
    float od = abs(dy) > 1e-3 ? hz0 * H * (1.0 - exp(-dy / H)) / (dy / dist) : hz0 * dist;
    od = includeHaze ? max(od, 0.0) : 0.0;
    vec3 trans = tAir * exp(-od);
    vec3 horizon = sampleSkyView(normalize(vec3(dir.x, max(abs(dir.y) * 0.3, 0.02), dir.z)));
    // Mist is grey-white, lit by the sky and the sun's forward lobe.
    float cosS = dot(dir, L.sunDir);
    vec3 sunLight = L.sunIllum * transmittanceToTop(PLANET_RADIUS + camAlt, L.sunDir.y);
    vec3 mist = (skyIrradiance(vec3(0.0, 1.0, 0.0)) * PI * INV_4PI + sunLight * hazePhase(cosS) * 0.6);
    vec3 inscatter = horizon * (1.0 - tAir) + mist * (1.0 - exp(-od)) * tAir;
    return vec4(inscatter, dot(trans, vec3(1.0 / 3.0)));
}

// Water as a medium: pure-water absorption (Pope & Fry 1997, approx. per metre at 650/550/450 nm)
// plus scattering by suspended matter tinted by the biome's water colour.
vec3 waterAbsorption() {
    return vec3(0.42, 0.065, 0.025) / WATER_CLARITY;
}

vec3 waterScattering(vec3 biomeTint) {
    vec3 t = srgbToLinear(saturate(biomeTint));
    return (0.012 + 0.03 * rainStrength) * mix(vec3(0.5, 0.8, 1.0), t / max(maxOf(t), 1e-3), 0.6) / WATER_CLARITY;
}

#endif

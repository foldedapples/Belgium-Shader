#ifndef SKY_MOON_GLSL
#define SKY_MOON_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/sky/celestial.glsl"
#include "/lib/atmosphere/atmosphere.glsl"

// Moon disk (ORIGINAL_ARCHITECTURE.md sec. 4, sec. 9).
// * Geometry: the pixel direction is intersected with a sphere of angular radius r; lunar
//   north is the orbital axis, longitude 0 faces the observer, east longitude on the right.
// * Albedo: NASA SVS CGI Moon Kit colour map (LRO LROC WAC), equirectangular, stored as a
//   prefiltered mip atlas because Iris does not mipmap custom textures. Relief from the LOLA
//   elevation model is stored as a normal map with the same layout.
// * Shading: Lommel-Seeliger (flat full moon) blended with Lambert near the terminator, lit by
//   the true sun direction, so phases follow from geometry. Per-pixel umbra/penumbra for
//   lunar eclipses; earthshine on the night side.

#if MOON_TEXTURE > 0
uniform sampler2D moonAlbedoTex;
uniform sampler2D moonNormalTex;
#endif

// Mip atlas: base level W x H at the left, level k (k >= 1) in a right-hand column of width
// W/2, stacked top to bottom. Atlas size (1.5 W) x H.
vec4 sampleMipAtlas(sampler2D tex, vec2 uv, float lod) {
    vec2 atlas = vec2(textureSize(tex, 0));
    vec2 base = vec2(atlas.x / 1.5, atlas.y);
    float maxLod = floor(log2(base.y)) - 2.0;
    lod = clamp(lod, 0.0, maxLod);
    float l0 = floor(lod);
    float f = lod - l0;
    vec4 result = vec4(0.0);
    for (int k = 0; k < 2; k++) {
        float level = l0 + float(k);
        vec2 size = base / exp2(level);
        vec2 offset = vec2(0.0);
        if (level >= 1.0) {
            offset.x = base.x;
            // Level 1 starts at y = 0; level n starts at y = H * (1 - 2^(1-n)).
            offset.y = base.y * (1.0 - exp2(1.0 - level));
        }
        vec2 p = vec2(fract(uv.x), clamp(uv.y, 0.0, 1.0)) * size;
        p = clamp(p, vec2(0.5), size - 0.5);
        vec4 s = texture(tex, (offset + p) / atlas);
        result += s * (k == 0 ? 1.0 - f : f);
    }
    return result;
}

vec3 moonDiskRadiance(vec3 dir, float pixelAngle, out bool covers) {
    covers = false;
    vec3 f = fsMoonDir.xyz;
    float r = fsMoonParams.x;
    if (r <= 0.0) return vec3(0.0);
    float cosA = dot(dir, f);
    if (cosA < cos(r + 2.0 * pixelAngle)) return vec3(0.0);

    vec3 up = safeNormalize(fsCelestialAxis.xyz - f * dot(fsCelestialAxis.xyz, f), vec3(0.0, 1.0, 0.0));
    vec3 right = cross(f, up);
    // Tangent-plane coordinates in units of the disk radius.
    vec3 perp = dir - f * cosA;
    vec2 q = vec2(dot(perp, right), dot(perp, up)) / sin(r);
    float q2 = dot(q, q);
    float ang = acos(clamp(cosA, -1.0, 1.0));
    float edge = 1.0 - smoothstep(r - pixelAngle, r + pixelAngle, ang);
    if (edge <= 0.0) return vec3(0.0);
    covers = edge > 0.5;
    q *= min(1.0, inversesqrt(max(q2, 1e-8)));
    q2 = min(q2, 1.0);
    // Outward sphere normal on the visible hemisphere.
    vec3 n = safeNormalize(q.x * right + q.y * up - sqrt(max(1.0 - q2, 0.0)) * f);

    float lat = asin(clamp(dot(n, up), -1.0, 1.0));
    float lon = atan(dot(n, right), dot(n, -f));
    vec2 uv = vec2(0.5 + lon * INV_TAU, 0.5 - lat * INV_PI);

    vec3 albedo = vec3(1.0);
    vec3 shadingN = n;
    #if MOON_TEXTURE > 0
    {
        vec2 base = vec2(textureSize(moonAlbedoTex, 0)) / vec2(1.5, 1.0);
        // Texels per pixel at this point of the disk (foreshortening grows towards the limb).
        float texelsPerRadian = base.x / TAU / max(r, 1e-5);
        float foreshorten = 1.0 / max(sqrt(1.0 - q2), 0.08);
        float lod = log2(max(pixelAngle * texelsPerRadian * foreshorten, 1e-3)) + MOON_SHARPNESS_BIAS;
        albedo = sampleMipAtlas(moonAlbedoTex, uv, lod).rgb;
        // Normal map is stored in the local (east, north, out) frame, xy in [0,1].
        // The normal atlas may be smaller than the albedo atlas: fewer texels per pixel.
        float normalBase = float(textureSize(moonNormalTex, 0).x) / 1.5;
        float lodN = lod - log2(max(base.x / normalBase, 1e-3));
        vec2 nm = sampleMipAtlas(moonNormalTex, uv, lodN).rg * 2.0 - 1.0;
        nm *= MOON_RELIEF;
        vec3 east = safeNormalize(cross(up, n), right);
        vec3 north = cross(n, east);
        shadingN = safeNormalize(n + east * nm.x + north * nm.y, n);
        // The map's mean albedo is normalised to 1 offline; keep the physical mean in k below.
        albedo = srgbToLinear(albedo) / 0.28;
    }
    #else
    {
        // Procedural fallback: broad maria and highlands from low-frequency noise.
        vec3 sp = n * 3.0;
        float maria = smoothstep(0.42, 0.62, valueNoise(sp * 1.3) * 0.65 + valueNoise(sp * 3.1) * 0.35);
        albedo = mix(vec3(1.12, 1.1, 1.06), vec3(0.62, 0.62, 0.64), maria);
    }
    #endif

    vec3 sunDir = fsSunDir.xyz;
    float cosI = dot(shadingN, sunDir);
    float cosE = saturate(dot(shadingN, -f));
    float ls = cosI > 0.0 ? 2.0 * cosI / (cosI + cosE + 1e-4) : 0.0;
    float lambert = max(cosI, 0.0);
    float shade = mix(ls, lambert, 0.25);

    // Radiance scale: the full moon's disk integral equals the configured moon irradiance.
    float k = SUN_IRRADIANCE * MOON_IRRADIANCE_RATIO / (PI * r * r * 0.92);
    // Lunar eclipse: Earth's shadow at this point of the disk.
    float d = acos(clamp(dot(dir, -sunDir), -1.0, 1.0));
    float sunlit = lunarSunlitFraction(d, r);
    float r0 = ATM_GROUND + 0.001;
    vec3 grazing = exp(-opticalDepthToTop(r0, 0.0, 12));
    vec3 umbral = grazing * grazing * 0.35;
    float inUmbra = step(d, UMBRA_RATIO * r);
    vec3 eclipse = mix(vec3(sunlit), umbral, inUmbra * (1.0 - sunlit));

    vec3 dayside = albedo * shade * eclipse;
    vec3 earthshine = albedo * fsMoonParams.w * cosE;
    return k * (dayside + earthshine) * edge * MOON_BRIGHTNESS;
}

#endif

#ifndef END_BLACK_HOLE_GLSL
#define END_BLACK_HOLE_GLSL
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#include "/lib/core/textures.glsl"
#include "/lib/end/black_hole_common.glsl"
#include "/lib/end/end_params.glsl"
#include "/lib/sky/stars.glsl"

// End sky: deep space seen through the gravitational lens of a Schwarzschild black hole with
// a thin accretion disk (ORIGINAL_ARCHITECTURE.md sec. 9).
//
// For a view direction d the impact parameter is b = D sin(alpha) / sqrt(1 - 1/D) (alpha
// measured from the hole). The photon moves in the plane spanned by e1 (hole -> observer) and
// e2 (transverse part of d); its position is r(phi) (cos phi e1 + sin phi e2). It crosses the
// disk plane where cos phi (e1.n) + sin phi (e2.n) = 0, i.e. at phi0 + k pi. r(phi) comes from
// the setup LUT (or per-pixel integration in Cinematic mode). Escaping rays sample the
// background along their final direction, which bends the star field and forms the Einstein
// ring; rays grazing b_c wind around the hole and pick up the disk again (photon ring).
//
// Artistic simplifications, documented: the disk is geometrically thin and optically
// semi-transparent; emission is bolometric (g^4) with colour from Planck at g*T; the disk's
// angular velocity is Keplerian in the static frame; light travel time is ignored.

uniform sampler2D blackHoleLutTex;

struct BlackHoleFrame { vec3 dir; vec3 n; vec3 t1; vec3 t2; };

BlackHoleFrame blackHoleFrame() {
    BlackHoleFrame f;
    f.dir = endBlackHoleDir();
    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 n0 = normalize(up - f.dir * dot(up, f.dir));      // edge-on disk
    float tilt = radians(BH_DISK_TILT);
    vec3 n = normalize(n0 * cos(tilt) - f.dir * sin(tilt)); // tilt the top face toward us
    f.n = rotateAxis(n, f.dir, radians(BH_DISK_ROLL));
    f.t1 = normalize(cross(f.n, f.dir));
    f.t2 = cross(f.n, f.t1);
    return f;
}

vec4 bhLut(float b, float phi) {
    float x = bhXFromImpact(b);
    float row = 1.0 + clamp(phi / BH_PHI_MAX, 0.0, 1.0) * float(BH_LUT_PHI - 2);
    return texture(blackHoleLutTex, vec2(x, (row + 0.5) / float(BH_LUT_PHI)));
}
// Row 0 holds sentinels (-1 = never) that must not be blended across the capture boundary:
// fetch the two neighbouring columns, interpolate only when both agree on the ray's fate.
vec4 bhMeta(float b) {
    float x = bhXFromImpact(b) * float(BH_LUT_B) - 0.5;
    int c0 = clamp(int(floor(x)), 0, BH_LUT_B - 1);
    int c1 = min(c0 + 1, BH_LUT_B - 1);
    float f = saturate(x - float(c0));
    vec4 m0 = texelFetch(blackHoleLutTex, ivec2(c0, 0), 0);
    vec4 m1 = texelFetch(blackHoleLutTex, ivec2(c1, 0), 0);
    bool cap0 = m0.y > 0.0, cap1 = m1.y > 0.0;
    if (cap0 == cap1) return mix(m0, m1, f);
    return f < 0.5 ? m0 : m1;
}

// Thin-disk temperature profile T ~ r^-3/4 (1 - sqrt(r_in/r))^1/4, normalised to its peak.
float diskTemperatureProfile(float r) {
    float x = BH_ISCO / r;
    return pow(x, 0.75) * pow(max(1.0 - sqrt(x), 0.0), 0.25) / 0.4882;
}

float diskTurbulence(float r, float theta, float t) {
    float omega = pow(r, -1.5) * 6.0 * BH_ROTATION_SPEED;
    const float P = 9.0;
    float pa = fract(t / P), pb = fract(t / P + 0.5);
    vec2 qa = vec2((theta - omega * pa * P) * INV_TAU * 5.0, log(r) * 1.8);
    vec2 qb = vec2((theta - omega * pb * P) * INV_TAU * 5.0 + 0.37, log(r) * 1.8);
    float na = texture(noise2dTex, qa * vec2(1.0, 0.25)).r * 0.6 + texture(noise2dTex, qa * vec2(3.0, 0.9)).g * 0.4;
    float nb = texture(noise2dTex, qb * vec2(1.0, 0.25)).r * 0.6 + texture(noise2dTex, qb * vec2(3.0, 0.9)).g * 0.4;
    // Cross-fade the two phases so differential rotation never winds the pattern up.
    float n = mix(na, nb, abs(2.0 * pa - 1.0));
    float rings = 0.65 + 0.35 * sin(r * 4.7 + n * 3.0);
    return n * rings;
}

vec4 diskEmission(vec3 p, vec3 photonDir, BlackHoleFrame f, float r) {
    if (r < BH_ISCO * 0.98 || r > BH_DISK_OUTER) return vec4(0.0);
    float theta = atan(dot(p, f.t2), dot(p, f.t1));
    vec3 v = normalize(cross(f.n, p));                    // prograde orbital direction
    float beta = min(sqrt(0.5 / max(r - 1.0, 1e-3)), 0.95);
    float cosPsi = dot(photonDir, v);
    float g = sqrt(max(1.0 - 1.0 / r, 0.0)) * sqrt(1.0 - beta * beta) / max(1.0 - beta * cosPsi, 0.05);
    #ifndef BH_DOPPLER
        g = sqrt(max(1.0 - 1.0 / r, 0.0));
    #endif
    float profile = diskTemperatureProfile(r);
    float temperature = BH_DISK_TEMPERATURE * profile;
    float intensity = pow(g, 4.0) * pow(profile, 4.0);
    vec3 colour = blackbody(max(temperature * g, 900.0));
    float density = diskTurbulence(r, theta, frameTimeCounter);
    float innerFade = smoothstep(BH_ISCO * 0.98, BH_ISCO * 1.15, r);
    float outerFade = 1.0 - smoothstep(BH_DISK_OUTER * 0.55, BH_DISK_OUTER, r);
    float alpha = saturate(density * 1.4) * innerFade * outerFade * 0.9;
    return vec4(colour * intensity * BH_DISK_BRIGHTNESS * 6.0, alpha);
}

// Deep-space background: stars, faint nebulae and rare distant galaxies.
vec3 spaceBackground(vec3 dir, float pixelAngle) {
    vec3 stars = starField(dir, pixelAngle, 0.0) * END_STAR_BRIGHTNESS * NIGHT_SKY_BRIGHTNESS * 0.5;
    vec3 p = dir * 3.0;
    float n1 = valueNoise(p) * 0.55 + valueNoise(p * 2.3) * 0.3 + valueNoise(p * 5.1) * 0.15;
    float n2 = valueNoise(p * 1.7 + 11.0) * 0.6 + valueNoise(p * 4.1 + 3.0) * 0.4;
    float neb = smoothstep(0.5, 0.85, n1);
    vec3 nebColour = mix(vec3(0.35, 0.15, 0.55), vec3(0.1, 0.35, 0.5), n2) * neb;
    float dust = smoothstep(0.55, 0.8, n2) * 0.7;
    vec3 nebula = nebColour * (1.0 - dust) * 0.004 * END_NEBULA_BRIGHTNESS;
    // Galaxies: one in ~200 coarse cells holds a small elliptical smudge.
    int face; vec2 uv;
    cubeFace(dir, face, uv);
    vec2 g = uv * 48.0;
    ivec2 c = ivec2(floor(g));
    uint h = hashU(uvec3(uvec2(c), uint(face) + 101u));
    vec3 galaxy = vec3(0.0);
    if (u32ToUnit(h) < 0.03) {
        vec2 centre = vec2(c) + 0.3 + 0.4 * vec2(u32ToUnit(hashU(h)), u32ToUnit(hashU(h ^ 0x9e3779b9u)));
        vec2 d = g - centre;
        float a = u32ToUnit(hashU(h + 7u)) * PI;
        d = rotate2(a) * d;
        float e = exp(-(sq(d.x / 0.08) + sq(d.y / 0.03)));
        galaxy = mix(blackbody(5200.0), blackbody(9000.0), u32ToUnit(hashU(h + 3u))) * e * 0.006;
    }
    return stars + nebula + galaxy;
}

vec3 blackHoleSky(vec3 d, float pixelAngle) {
    BlackHoleFrame f = blackHoleFrame();
    float D = bhObserverDistance();
    float cosA = clamp(dot(d, f.dir), -1.0, 1.0);
    float sinA = sqrt(max(1.0 - cosA * cosA, 0.0));
    vec3 e1 = -f.dir;
    vec3 tr = d - e1 * dot(d, e1);
    if (dot(tr, tr) < 1e-12) return vec3(0.0);                 // dead centre: the shadow
    vec3 e2 = normalize(tr);
    float b = D * sinA / sqrt(1.0 - 1.0 / D);

    bool towardHole = cosA > 0.0;
    float phiEnd, phiCapture = -1.0;
    bool inLut = towardHole && b > bhMinImpact() && b < bhMaxImpact();
    if (!towardHole || b >= bhMaxImpact()) {
        float alpha = acos(cosA);
        phiEnd = PI - alpha + 2.0 / max(b, 1e-3);                   // weak-field deflection
    } else if (b <= bhMinImpact()) {
        phiEnd = -1.0; phiCapture = 0.5;
    } else {
        vec4 meta = bhMeta(b);
        phiEnd = meta.x; phiCapture = meta.y;
    }
    bool captured = phiCapture > 0.0 && (phiEnd < 0.0 || phiCapture < phiEnd);
    float phiLimit = captured ? phiCapture : phiEnd;

    vec3 colour = vec3(0.0);
    float T = 1.0;
    float e1n = dot(e1, f.n), e2n = dot(e2, f.n);
    float phi0 = atan(-e1n, e2n);
    if (phi0 < 0.0) phi0 += PI;
    #if BH_QUALITY == 0
        const int MAX_IMAGES = 2;
    #else
        const int MAX_IMAGES = 3;
    #endif

    #if BH_QUALITY >= 2
    {
        // Cinematic: integrate this pixel's geodesic directly.
        vec2 s = bhInitialState(max(b, 1e-3), D);
        if (!towardHole) s.y = -s.y;
        const int STEPS = 480;
        float h = BH_PHI_MAX / float(STEPS);
        float phi = 0.0;
        float prevSide = dot(cos(phi) * e1 + sin(phi) * e2, f.n);
        phiLimit = -1.0; captured = false;
        for (int i = 0; i < STEPS; i++) {
            vec2 next = bhRk4(s, h);
            float phiN = phi + h;
            if (next.x >= 1.0) { captured = true; break; }
            if (next.x <= 0.0) { phiLimit = phi + h * s.x / max(s.x - next.x, 1e-9); break; }
            float side = dot(cos(phiN) * e1 + sin(phiN) * e2, f.n);
            if (side * prevSide < 0.0 && T > 0.01) {
                float w = prevSide / (prevSide - side);
                float u = mix(s.x, next.x, w), du = mix(s.y, next.y, w);
                float pc = phi + w * h;
                float r = 1.0 / max(u, 1e-5);
                vec3 radial = cos(pc) * e1 + sin(pc) * e2;
                vec3 tangent = -sin(pc) * e1 + cos(pc) * e2;
                vec3 trace = normalize(-du / (u * u) * radial + r * tangent);
                vec4 em = diskEmission(r * radial, -trace, f, r);
                colour += T * em.a * em.rgb; T *= 1.0 - em.a;
            }
            prevSide = side; s = next; phi = phiN;
        }
        if (!captured && phiLimit < 0.0) phiLimit = BH_PHI_MAX;
        phiEnd = phiLimit;
    }
    #else
    if (inLut || b <= bhMinImpact()) {
        for (int k = 0; k < MAX_IMAGES; k++) {
            float phiK = phi0 + float(k) * PI;
            if (phiK >= phiLimit || T < 0.01) break;
            vec4 s = bhLut(b, phiK);
            float u = s.x;
            if (u <= 1e-5) break;
            float r = 1.0 / u;
            vec3 radial = cos(phiK) * e1 + sin(phiK) * e2;
            vec3 tangent = -sin(phiK) * e1 + cos(phiK) * e2;
            vec3 trace = normalize(-s.y / (u * u) * radial + r * tangent);
            vec4 em = diskEmission(r * radial, -trace, f, r);
            colour += T * em.a * em.rgb;
            T *= 1.0 - em.a;
        }
    }
    #endif

    if (!captured) {
        vec3 outDir = cos(phiEnd) * e1 + sin(phiEnd) * e2;
        colour += T * spaceBackground(outDir, pixelAngle);
    }
    return colour;
}

#endif

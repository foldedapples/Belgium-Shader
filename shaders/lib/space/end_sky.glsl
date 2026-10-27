#ifndef MERIDIAN_END_SKY
#define MERIDIAN_END_SKY
#include "/lib/common/math.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/lighting/emitters.glsl"
#include "/lib/lighting/shadow_proj.glsl"


// The End as deep space: the real Milky Way and star catalogue (NASA SVS 4851) seen from
// galactic coordinates, faint nebulae, three procedural planets on slow orbits, and a black hole
// whose accretion disk is the dimension's light source.
//
// The planets and nebulae are artistic and procedural; their placement is not an observed
// configuration. The background is real astronomical data.

#include "/lib/sky/stars.glsl"
#include "/lib/space/black_hole.glsl"

// Equatorial (J2000) -> galactic rotation (IAU 1958 definition, as tabulated by Hipparcos vol. 1).
const mat3 EQ_TO_GAL = mat3(
    -0.0548755604, 0.4941094279, -0.8676661490,
    -0.8734370902, -0.4448296300, -0.1980763734,
    -0.4838350155, 0.7469822445, 0.4559837762);

// Player-space -> "space" frame of the End background. The galactic plane is tilted across the
// sky so the Milky Way arches behind the black hole.
vec3 endSpaceDir(vec3 d) {
    vec3 g = vec3(d.x, d.z, d.y);
    g = rotateAxis(g, normalize(vec3(0.3, 1.0, 0.2)), 0.9);
    return transpose(EQ_TO_GAL) * g;   // back to equatorial for the data textures
}

vec3 endDiskColor() { return blackbody(5200.0); }

// Illuminance at End terrain from the accretion disk (warm, directional).
vec3 endLightIlluminance() {
    return endDiskColor() * 3.2 * END_LIGHT_STRENGTH;
}

vec3 endAmbient(vec3 n) {
    vec3 space = vec3(0.010, 0.010, 0.016);
    vec3 disk = endDiskColor() * 0.06 * saturate(dot(n, END_LIGHT_DIR) * 0.5 + 0.5) * END_LIGHT_STRENGTH;
    vec3 flash = vec3(0.55, 0.35, 1.0) * endFlashIntensity * 0.4;
    return (space + disk + flash) * PI * INV_PI;
}

// ---------------------------------------------------------------- nebulae
vec3 nebula(vec3 d) {
    #ifdef END_NEBULAE
    vec3 p = d * 3.0;
    float n = valueNoise(p * 1.7) * 0.5 + valueNoise(p * 3.9) * 0.25 + valueNoise(p * 8.3) * 0.125 + valueNoise(p * 17.1) * 0.0625;
    float m = valueNoise(p * 0.9 + 11.0);
    float shape = smoothstep(0.55, 1.0, n * (0.55 + 0.8 * m));
    // Emission-line palette: H-alpha red, OIII teal, with dark dust lanes.
    vec3 col = mix(vec3(1.0, 0.18, 0.32), vec3(0.15, 0.75, 0.85), smoothstep(0.3, 0.7, valueNoise(p * 2.3 + 5.0)));
    float dust = smoothstep(0.55, 0.75, valueNoise(p * 5.1 - 3.0));
    // Subtle: a faint, partly desaturated glow well below the Milky Way's brightness.
    col = mix(vec3(luminance(col)), col, 0.65);
    return col * shape * shape * (1.0 - 0.7 * dust) * 0.012;
    #else
    return vec3(0.0);
    #endif
}

// ---------------------------------------------------------------- planets
struct Planet {
    vec3 dir;       // centre direction
    float radius;   // angular radius
    vec3 axis;      // spin axis
    float spin;     // rotation angle
    int kind;       // 0 gas giant, 1 ringed ice giant, 2 rocky moon
};

Planet endPlanet(int i, float t) {
    Planet p;
    // Each planet drifts along its own great circle; periods of tens of real minutes.
    float speeds[3] = float[3](0.0011, 0.0007, 0.0019);
    vec3 bases[3] = vec3[3](normalize(vec3(-0.75, 0.32, 0.3)), normalize(vec3(0.2, 0.55, 0.7)), normalize(vec3(-0.3, 0.18, -0.9)));
    vec3 axes[3] = vec3[3](normalize(vec3(0.1, 1.0, 0.2)), normalize(vec3(0.4, 1.0, -0.3)), normalize(vec3(-0.2, 1.0, 0.1)));
    float radii[3] = float[3](0.085, 0.05, 0.022);
    p.dir = rotateAxis(bases[i], axes[i], t * speeds[i]);
    p.radius = radii[i];
    p.axis = normalize(vec3(0.25, 1.0, 0.1) + vec3(float(i) * 0.2, 0.0, -0.1 * float(i)));
    p.spin = t * (0.02 + 0.015 * float(i));
    p.kind = i;
    return p;
}

vec3 planetAlbedo(Planet p, vec3 local) {
    // local: point on the unit sphere in the planet's rotating frame (y = spin axis).
    float lat = asin(clamp(local.y, -1.0, 1.0));
    float lon = atan(local.z, local.x);
    if (p.kind == 0) {
        float band = sin(lat * 14.0 + valueNoise(vec2(lon * 2.0, lat * 9.0)) * 1.6);
        float swirl = valueNoise(vec2(lon * 5.0 + lat * 3.0, lat * 22.0));
        vec3 a = mix(vec3(0.78, 0.62, 0.45), vec3(0.93, 0.88, 0.78), band * 0.5 + 0.5);
        a = mix(a, vec3(0.55, 0.32, 0.22), smoothstep(0.65, 0.8, swirl) * 0.6);
        // A long-lived storm oval.
        float storm = smoothstep(0.16, 0.0, length(vec2((lon - 1.0) * 0.6, lat + 0.35)));
        return mix(a, vec3(0.75, 0.36, 0.25), storm);
    } else if (p.kind == 1) {
        float band = sin(lat * 8.0) * 0.5 + 0.5;
        return mix(vec3(0.55, 0.78, 0.82), vec3(0.68, 0.86, 0.9), band * 0.6);
    }
    // Rocky moon with procedural craters.
    vec3 q = local * 6.0;
    float craters = 0.0;
    for (int i = 0; i < 3; i++) {
        vec3 c = floor(q);
        vec3 f = fract(q) - 0.5 - (hash3(ivec3(c) + i * 17) - 0.5) * 0.6;
        float rr = length(f);
        craters += smoothstep(0.35, 0.28, rr) * 0.25 - smoothstep(0.28, 0.0, rr) * 0.18;
        q *= 2.1;
    }
    float tone = 0.55 + valueNoise(local * 9.0) * 0.25 + craters;
    return vec3(0.42, 0.40, 0.38) * tone;
}

// ---- rings (planet kind 1)
// Ring system between RING_INNER and RING_OUTER planet radii (Saturn: C ring from ~1.24, A ring to
// ~2.27). Optical depth over x in [0,1], inner to outer: faint C ring, dense B ring, the nearly
// empty Cassini Division, the A ring with the Encke Gap, a thin F ring, all modulated by aperiodic
// radial ringlets. The old profile, 0.55 + 0.45 sin(60x) sin(13x), was a perfectly regular set
// of identical grey circles. `fx` is the pixel footprint in x; ringlets finer than it fade out.
const float RING_INNER = 1.24;
const float RING_OUTER = 2.30;

float ringOpticalDepth(float x, float fx) {
    float tau = 0.10 * smoothstep(0.0, 0.03, x) * (1.0 - smoothstep(0.23, 0.26, x));          // C
    tau += 1.5 * smoothstep(0.24, 0.29, x) * (1.0 - smoothstep(0.555, 0.575, x));             // B
    tau += 0.04 * smoothstep(0.57, 0.59, x) * (1.0 - smoothstep(0.62, 0.635, x));             // Cassini
    tau += 0.55 * smoothstep(0.625, 0.66, x) * (1.0 - smoothstep(0.92, 0.94, x));             // A
    tau *= 1.0 - 0.9 * (1.0 - smoothstep(0.0, 0.004 + fx, abs(x - 0.86)));                   // Encke Gap
    tau += 0.25 * (1.0 - smoothstep(0.0, 0.008 + fx, abs(x - 0.975)));                        // F
    // Ringlets: three octaves of 1D value noise in radius, each faded once finer than a pixel.
    float fine = 0.0, wsum = 0.0;
    for (int i = 0; i < 3; i++) {
        float freq = 70.0 * pow(3.1, float(i));
        float w = (0.5 / float(i + 1)) * saturate(1.0 - freq * fx * 1.5);
        fine += w * valueNoise(vec2(x * freq, 3.7 * float(i)));
        wsum += w;
    }
    fine = wsum > 0.0 ? fine / wsum : 0.5;
    return tau * (0.45 + 1.1 * fine);
}

// Distance along unit direction `rd` from `ro` to a sphere (centre c, radius r); < 0 if missed.
float sphereHit(vec3 ro, vec3 rd, vec3 c, float r) {
    vec3 oc = ro - c;
    float b = dot(oc, rd);
    float h = b * b - dot(oc, oc) + r * r;
    if (h < 0.0) return -1.0;
    float t = -b - sqrt(h);
    return t > 0.0 ? t : (-b + sqrt(h) > 0.0 ? 0.0 : -1.0);
}

// Ring transmittance for the light reaching point `s` (planet-centre units) of planet p.
float ringShadowOn(Planet p, vec3 rn, vec3 s) {
    float dl = dot(END_LIGHT_DIR, rn);
    if (abs(dl) < 1e-4) return 1.0;
    float t = dot(p.dir - s, rn) / dl;
    if (t <= 0.0) return 1.0;
    float rr = length(s + END_LIGHT_DIR * t - p.dir) / sin(p.radius);
    if (rr < RING_INNER || rr > RING_OUTER) return 1.0;
    float tau = ringOpticalDepth((rr - RING_INNER) / (RING_OUTER - RING_INNER), 0.002);
    return exp(-tau / max(abs(dl), 0.05));
}

// Radiance of planets along `d` (or zero), lit from the black hole direction. Each planet sits at
// unit distance in direction p.dir with physical radius sin(p.radius).
vec4 planetsRadiance(vec3 d, float pixelAngle) {
    #ifdef END_PLANETS
    float t = frameTimeCounter + float(worldTime) * 0.05;
    vec4 outC = vec4(0.0);
    for (int i = 0; i < 3; i++) {
        Planet p = endPlanet(i, t);
        float R = sin(p.radius);
        float c = dot(d, p.dir);
        float ang = acos(clamp(c, -1.0, 1.0));
        vec3 rn = normalize(p.axis + vec3(0.0, 0.0, 0.25));

        // Ring layer along this ray (kind 1).
        vec4 ring = vec4(0.0);
        float ringT = 1e9;
        if (p.kind == 1) {
            float denom = dot(d, rn);
            if (abs(denom) > 1e-4) {
                float tr = dot(p.dir, rn) / denom;
                vec3 hit = d * tr;
                float rr = length(hit - p.dir) / R;
                if (tr > 0.0 && rr > RING_INNER && rr < RING_OUTER) {
                    float x = (rr - RING_INNER) / (RING_OUTER - RING_INNER);
                    float mu = max(abs(denom), 0.03);
                    float fx = pixelAngle / (R * (RING_OUTER - RING_INNER) * mu);
                    float tau = ringOpticalDepth(x, fx);
                    float alpha = 1.0 - exp(-tau / mu);              // slant path: thicker edge-on
                    // Lit face seen: diffuse back-scatter. Unlit face seen: light diffusing through.
                    float dl = dot(END_LIGHT_DIR, rn);
                    bool litSide = sign(dl) == sign(-denom);
                    float through = (1.0 - exp(-tau / max(abs(dl), 0.05))) * exp(-tau / mu) * 0.6;
                    float bright = litSide ? abs(dl) * 0.9 + 0.1 : through;
                    // Planet shadow on the rings.
                    float shadow = sphereHit(hit, END_LIGHT_DIR, p.dir, R) >= 0.0 ? 0.04 : 1.0;
                    vec3 tint = mix(vec3(0.80, 0.73, 0.62), vec3(0.63, 0.57, 0.50), smoothstep(0.6, 0.7, x));
                    vec3 col = tint * (0.85 + 0.3 * valueNoise(vec2(x * 23.0, 1.3))) * bright * shadow
                             * endLightIlluminance() * INV_PI;
                    ring = vec4(col, alpha);
                    ringT = tr;
                }
            }
        }

        // Planet body.
        vec4 body = vec4(0.0);
        float bodyT = 1e9;
        if (ang <= p.radius + pixelAngle) {
            vec3 f = -p.dir;
            vec3 r = normalize(cross(p.axis, f));
            vec3 u = cross(f, r);
            vec3 off = d - p.dir * c;
            vec2 disk = vec2(dot(off, -r), dot(off, u)) / R;
            float rr = dot(disk, disk);
            float cov = saturate((p.radius - ang) / max(pixelAngle, 1e-5) + 0.5);
            vec3 n = normalize(-r * disk.x + u * disk.y + f * sqrt(max(1.0 - rr, 0.0)));
            vec3 local = rotateAxis(n, p.axis, p.spin);
            local = vec3(dot(local, r), dot(local, p.axis), dot(local, f));
            vec3 alb = planetAlbedo(p, normalize(local));
            float ndl = dot(n, END_LIGHT_DIR);
            float ringShadow = p.kind == 1 ? ringShadowOn(p, rn, p.dir + n * R) : 1.0;
            vec3 lit = alb * saturate(ndl) * endLightIlluminance() * INV_PI * ringShadow;
            // Atmospheric rim and a soft terminator for the gas worlds.
            float rim = pow(saturate(1.0 - dot(n, f)), 3.0);
            vec3 atmo = (p.kind == 0 ? vec3(0.9, 0.7, 0.5) : p.kind == 1 ? vec3(0.4, 0.7, 1.0) : vec3(0.0)) * rim * saturate(ndl + 0.3) * 0.06 * endLightIlluminance();
            lit += atmo + alb * 0.002;
            body = vec4(lit, cov);
            bodyT = c - sqrt(max(R * R - (1.0 - c * c), 0.0));      // distance to the near surface
        }

        // Composite back to front: whichever of ring and body is farther goes first.
        vec4 far_ = ringT > bodyT ? ring : body;
        vec4 near_ = ringT > bodyT ? body : ring;
        outC.rgb = mix(outC.rgb, far_.rgb, far_.a);
        outC.a = max(outC.a, far_.a);
        outC.rgb = mix(outC.rgb, near_.rgb, near_.a);
        outC.a = max(outC.a, near_.a);
    }
    return outC;
    #else
    return vec4(0.0);
    #endif
}

// ---------------------------------------------------------------- galaxies
// The End shows deep space, not our own galaxy from inside: the Milky Way band belongs to the
// Overworld night. Instead: one large spiral galaxy seen at an angle, and a field of small
// distant galaxies (ellipticals and spirals of varied size, shape, orientation and colour).

// Face-on brightness of a spiral galaxy at disk coordinates q (unit = disk radius).
float spiralGalaxy(vec2 q, float arms, float wind, float seed) {
    float r = length(q);
    if (r > 1.3) return 0.0;
    float a = atan(q.y, q.x);
    float bulge = exp(-r * r / 0.012) * 1.6;
    float disk = exp(-r / 0.28);
    // Logarithmic spiral arms: brightness peaks where a - wind * log(r) is a multiple of 2 pi / arms.
    float spiral = 0.5 + 0.5 * cos(arms * (a - wind * log(max(r, 0.02))) + seed);
    float clumps = valueNoise(q * 9.0 + seed) * 0.6 + valueNoise(q * 23.0 - seed) * 0.4;
    float armLight = disk * pow(spiral, 3.0) * (0.6 + 0.8 * clumps);
    // Dust lanes on the inner edge of the arms.
    float dust = smoothstep(0.55, 0.9, 0.5 + 0.5 * cos(arms * (a - wind * log(max(r, 0.02))) + seed - 0.9));
    return bulge + armLight * (1.0 - 0.6 * dust * smoothstep(0.05, 0.25, r)) + disk * 0.15;
}

vec3 heroGalaxy(vec3 d) {
    const vec3 C = vec3(0.57735, -0.3, 0.76);          // direction of its centre (normalised below)
    vec3 c = normalize(C);
    vec3 n = normalize(vec3(0.3, 0.9, -0.2));          // disk normal (inclined to the view)
    vec3 e1 = normalize(cross(n, c));
    vec3 e2 = cross(n, e1);
    float denom = dot(d, n);
    if (abs(denom) < 1e-4) return vec3(0.0);
    // Intersect the view ray with the galaxy's plane at unit distance; disk radius 0.22.
    float t = dot(c, n) / denom;
    if (t <= 0.0) return vec3(0.0);
    vec3 p = d * t - c;
    vec2 q = vec2(dot(p, e1), dot(p, e2)) / 0.22;
    float b = spiralGalaxy(q, 2.0, 2.6, 1.3);
    float r = length(q);
    vec3 col = mix(vec3(1.0, 0.82, 0.6), vec3(0.62, 0.74, 1.0), smoothstep(0.05, 0.5, r));   // old bulge, young arms
    return col * b * 0.02;
}

vec3 distantGalaxies(vec3 d, float pixelAngle) {
    vec3 col = vec3(0.0);
    const float CELLS = 60.0;
    vec3 g = d * CELLS;
    ivec3 c0 = ivec3(floor(g));
    for (int k = 0; k < 8; k++) {
        ivec3 c = c0 + ivec3(k & 1, (k >> 1) & 1, k >> 2);
        vec4 h = hash4(c);
        if (h.w > 0.10) continue;                          // ~1 galaxy per 10 cells
        vec3 centre = normalize(vec3(c) + 0.2 + 0.6 * h.xyz);
        vec3 off = d - centre * dot(d, centre);
        float size = mix(0.0012, 0.006, h.x * h.x);        // angular radius
        if (dot(off, off) > size * size * 4.0) continue;
        // Orientation and tilt of this galaxy.
        vec3 e1 = normalize(cross(centre, normalize(h.xyz - 0.5 + 1e-3)));
        vec3 e2 = cross(centre, e1);
        float tilt = mix(0.25, 1.0, h.y);
        vec2 q = vec2(dot(off, e1), dot(off, e2) / tilt) / size;
        float px = pixelAngle / size;
        float b = h.z < 0.55 ? exp(-dot(q, q) * 2.5) * 1.4                      // elliptical
                             : spiralGalaxy(q, 2.0, 2.2, h.x * 6.0) * 0.7;    // spiral
        b /= 1.0 + px * px * 4.0;                          // sub-pixel galaxies stay faint, no sparkle
        vec3 tint = h.z < 0.55 ? vec3(1.0, 0.86, 0.7) : mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.9, 0.8), h.y);
        col += tint * b * 0.012;
    }
    return col;
}

// ---------------------------------------------------------------- full sky
vec3 endBackground(vec3 d, float pixelAngle) {
    vec3 eq = endSpaceDir(d);
    vec3 c = vec3(0.0);
    // Deep-space backdrop as a long-exposure photograph would show it: star flux and Milky Way
    // radiance (full-Moon units, tools/prep_stars.py) are lifted so the galaxy reads at the
    // exposure set by the disk-lit End islands (artistic; real space would look black here).
    const float k = 10.0;
    #ifdef STARS
    c += starRadiance(eq, pixelAngle, -1.0) * (k * STAR_BRIGHTNESS);   // no air: no twinkling
    #endif
    // The Milky Way band is the Overworld's night sky; the End shows other galaxies instead.
    c += heroGalaxy(d) + distantGalaxies(d, pixelAngle);
    c += nebula(d);
    return c;
}

vec3 endSkyRadiance(vec3 d, float pixelAngle) {
    #ifndef END_SPACE
    return vec3(0.02, 0.015, 0.03);
    #else
    vec3 bg;
    vec4 planets = planetsRadiance(d, pixelAngle);
    #ifdef BLACK_HOLE
    vec3 bhDir = END_LIGHT_DIR;
    float ang = acos(clamp(dot(d, bhDir), -1.0, 1.0));
    float scale = bhShadowAngle() / bhApparentShadow();
    float influence = bhApparentShadow() * 9.0;
    if (ang < influence) {
        // Build the ray in the black-hole frame: the observer sits on the -z axis.
        vec3 fz = bhDir;
        vec3 fx = normalize(cross(vec3(0.0, 1.0, 0.0), fz));
        vec3 fy = cross(fz, fx);
        vec3 local = vec3(dot(d, fx), dot(d, fy), dot(d, fz));
        float a = ang * scale;
        vec2 azi = normalize(local.xy + 1e-6);
        vec3 rd = normalize(vec3(azi * sin(a), cos(a)));
        vec3 ro = vec3(0.0, 0.0, -BH_OBSERVER_DIST);
        // Disk tilted ~78 degrees from face-on: an edge-lit, cinematic view.
        vec3 diskN = normalize(vec3(0.0, 1.0, 0.21));
        BHResult bh = traceBlackHole(ro, rd, diskN, frameTimeCounter);
        vec3 bgCol = vec3(0.0);
        if (!bh.captured) {
            // Map the escape direction back to the sky with the same angular magnification.
            float ea = acos(clamp(bh.escapeDir.z, -1.0, 1.0)) / scale;
            vec2 ez = normalize(bh.escapeDir.xy + 1e-6);
            vec3 ed = normalize(fx * ez.x * sin(ea) + fy * ez.y * sin(ea) + fz * cos(ea));
            bgCol = endBackground(ed, pixelAngle * 2.0);
        }
        // The disk is bright enough to light the islands (endLightIlluminance), which would leave
        // it as a white shape at any exposure that shows the terrain. As for the Moon, the disk is
        // scaled as a whole so its brightest part sits ~5x above display white: temperature
        // colours, Doppler asymmetry and turbulence stay visible. Terrain lighting is unchanged.
        const float DISK_PHYSICAL = 40.0;
        float diskScale = DISK_PHYSICAL;
        #ifdef MERIDIAN_STATE
        diskScale = min(DISK_PHYSICAL, 5.0 / max(state.exposure, 1e-6));
        #endif
        vec3 disk = bh.radiance * BH_DISK_BRIGHTNESS * diskScale;
        bg = disk + bgCol * bh.transmit;
        // Fade the traced region into the plain sky at the edge of its influence.
        float edge = smoothstep(influence * 0.8, influence, ang);
        bg = mix(bg, endBackground(d, pixelAngle), edge);
    } else {
        bg = endBackground(d, pixelAngle);
    }
    // Soft glow of disk light scattered by dust around (not in front of) the hole: it fades to
    // zero inside the shadow so the event horizon stays black.
    float outside = smoothstep(bhApparentShadow() * 1.05, bhApparentShadow() * 1.6, ang);
    float glowScale = 40.0;
    #ifdef MERIDIAN_STATE
    glowScale = min(40.0, 5.0 / max(state.exposure, 1e-6));
    #endif
    bg += endDiskColor() * 0.004 * glowScale * BH_DISK_BRIGHTNESS * exp(-ang / (bhApparentShadow() * 3.0)) * outside;
    #else
    bg = endBackground(d, pixelAngle);
    #endif
    bg = mix(bg, planets.rgb, planets.a);
    // End flash (1.21.9+): a brief purple flare from its direction.
    bg += vec3(0.6, 0.35, 1.0) * endFlashIntensity * 0.3 * pow(saturate(dot(d, normalize(endFlashPosition + vec3(1e-4)))), 16.0);
    return bg;
    #endif
}

#endif

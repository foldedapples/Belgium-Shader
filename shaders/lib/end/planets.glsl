#ifndef END_PLANETS_GLSL
#define END_PLANETS_GLSL
#include "/lib/core/common.glsl"
#include "/lib/end/end_params.glsl"

// Planets of the End sky (ORIGINAL_ARCHITECTURE.md sec. 9). Each is a sphere between the
// observer and the black hole (the hole sits at distance 1, planets closer), lit by the
// accretion disk, so the lit fraction - the phase - follows from the geometry and changes as
// the planet moves along its orbit. They are drawn over the lensed sky, unlensed (they are
// in front of the hole). Only sky pixels reach this code, so terrain always occludes them.
//
// Motion: frameTimeCounter wraps every 3600 s in Iris; every period below divides 3600 s, so
// orbits and spins are continuous and the same for every player at the same time.

struct EndPlanet {
    vec3  orbitAxis;
    vec3  orbitStart;   // direction at t = 0
    float orbitPeriod;  // seconds per revolution across the sky
    float angularRadius;
    float distance;     // relative to the black hole's distance
    vec3  spinAxis;
    float spinPeriod;
    int   kind;         // 0 rocky, 1 banded gas giant with rings, 2 ice world
    vec3  colourA, colourB;
};

EndPlanet endPlanet(int i) {
    EndPlanet p;
    if (i == 0) {           // large ringed gas giant, slow
        p.orbitAxis = normalize(vec3(0.15, 1.0, 0.35));
        p.orbitStart = normalize(vec3(-0.75, 0.38, 0.45));
        p.orbitPeriod = 3600.0; p.angularRadius = radians(4.2); p.distance = 0.55;
        p.spinAxis = normalize(vec3(0.25, 1.0, -0.2)); p.spinPeriod = 600.0; p.kind = 1;
        p.colourA = vec3(0.62, 0.46, 0.33); p.colourB = vec3(0.86, 0.78, 0.62);
    } else if (i == 1) {    // rocky world with a thin atmosphere
        p.orbitAxis = normalize(vec3(-0.3, 1.0, 0.1));
        p.orbitStart = normalize(vec3(0.55, 0.52, 0.62));
        p.orbitPeriod = 1800.0; p.angularRadius = radians(1.6); p.distance = 0.35;
        p.spinAxis = normalize(vec3(0.0, 1.0, 0.3)); p.spinPeriod = 300.0; p.kind = 0;
        p.colourA = vec3(0.32, 0.27, 0.24); p.colourB = vec3(0.58, 0.45, 0.36);
    } else {                // small ice world, fast
        p.orbitAxis = normalize(vec3(0.4, 1.0, -0.25));
        p.orbitStart = normalize(vec3(0.1, 0.72, -0.68));
        p.orbitPeriod = 1200.0; p.angularRadius = radians(0.9); p.distance = 0.25;
        p.spinAxis = normalize(vec3(-0.2, 1.0, 0.1)); p.spinPeriod = 240.0; p.kind = 2;
        p.colourA = vec3(0.55, 0.66, 0.74); p.colourB = vec3(0.86, 0.9, 0.94);
    }
    return p;
}

vec3 endPlanetDirection(EndPlanet p) {
    return normalize(rotateAxis(p.orbitStart, p.orbitAxis, TAU * frameTimeCounter / p.orbitPeriod));
}

float planetFbm(vec3 q) {
    return valueNoise(q) * 0.5 + valueNoise(q * 2.03 + 7.1) * 0.27 + valueNoise(q * 4.1 + 3.3) * 0.15
         + valueNoise(q * 8.3 + 1.7) * 0.08;
}

// Surface albedo at local (planet-fixed) unit position q.
vec3 planetAlbedo(EndPlanet p, vec3 q) {
    float lat = dot(q, p.spinAxis);
    if (p.kind == 1) {
        float turb = planetFbm(q * 3.0) - 0.5;
        float bands = sin(lat * 19.0 + turb * 4.0) * 0.5 + 0.5;
        float fine = sin(lat * 57.0 + turb * 7.0) * 0.5 + 0.5;
        vec3 c = mix(p.colourA, p.colourB, bands * 0.75 + fine * 0.25);
        // A long-lived storm in the southern belt.
        vec3 storm = normalize(p.spinAxis * -0.35 + normalize(cross(p.spinAxis, vec3(1.0, 0.0, 0.0))));
        float s = exp(-sq(distance(q, storm) / 0.09));
        return mix(c, vec3(0.72, 0.36, 0.24), s * 0.8);
    }
    float h = planetFbm(q * 3.5);
    vec3 c = mix(p.colourA, p.colourB, smoothstep(0.35, 0.7, h));
    if (p.kind == 0) {
        // Craters: darker basins from a second noise field.
        c *= 1.0 - 0.35 * smoothstep(0.62, 0.8, valueNoise(q * 11.0 + 5.0));
    } else {
        // Ice: bright polar caps, cracked darker lineae.
        c = mix(c, vec3(0.95), smoothstep(0.55, 0.8, abs(lat)));
        c *= 1.0 - 0.3 * smoothstep(0.47, 0.5, abs(valueNoise(q * 9.0) - 0.5) + 0.48);
    }
    return c;
}

// Returns radiance (rgb) and coverage (a) of the planets along `dir`. `holeDir` is the black
// hole (the light), `lightE` its irradiance, `ambientE` the faint End sky light.
vec4 endPlanets(vec3 dir, float pixelAngle, vec3 holeDir, vec3 lightE, vec3 ambientE) {
    vec3 colour = vec3(0.0);
    float alpha = 0.0;
    float nearest = 1e9;
    for (int i = 0; i < 3; i++) {
        EndPlanet p = endPlanet(i);
        vec3 c = endPlanetDirection(p);
        vec3 centre = c * p.distance;
        float R = p.distance * sin(p.angularRadius);
        vec3 L = normalize(holeDir - centre);         // from the planet toward the hole
        float ringOuter = p.kind == 1 ? 2.3 : 1.0;
        float cosA = dot(dir, c);
        // Cheap reject outside the planet (and its rings).
        if (cosA < cos(p.angularRadius * ringOuter + 2.0 * pixelAngle)) continue;

        vec4 body = vec4(0.0); float tBody = 1e9;
        float b = dot(dir, centre);
        float disc = b * b - (dot(centre, centre) - R * R);
        float ang = acos(clamp(cosA, -1.0, 1.0));
        float cover = 1.0 - smoothstep(p.angularRadius - pixelAngle, p.angularRadius + pixelAngle, ang);
        if (cover > 0.0) {
            float tHit = b - sqrt(max(disc, 0.0));
            vec3 P = dir * tHit;
            vec3 N = normalize(P - centre);
            vec3 q = rotateAxis(N, p.spinAxis, -TAU * frameTimeCounter / p.spinPeriod);
            vec3 albedo = planetAlbedo(p, q);
            float nl = dot(N, L);
            vec3 rad = albedo * INV_PI * (lightE * max(nl, 0.0) + ambientE * 0.6);
            if (p.kind != 1) {
                // Thin atmosphere: a lit rim scattering toward the observer.
                float rim = pow(1.0 - saturate(dot(N, -dir)), 4.0);
                vec3 sky = p.kind == 0 ? vec3(0.45, 0.6, 1.0) : vec3(0.6, 0.8, 1.0);
                rad += sky * lightE * INV_PI * rim * smoothstep(-0.25, 0.4, nl) * 0.35;
            }
            body = vec4(rad, cover);
            tBody = tHit;
        }

        vec4 ring = vec4(0.0); float tRing = 1e9;
        if (p.kind == 1) {
            float dn = dot(dir, p.spinAxis);
            if (abs(dn) > 1e-4) {
                float t = dot(centre, p.spinAxis) / dn;
                vec3 P = dir * t;
                float r = length(P - centre) / R;
                if (t > 0.0 && r > 1.35 && r < ringOuter) {
                    float bands = 0.55 + 0.45 * sin(r * 41.0) * sin(r * 13.0 + 1.0);
                    float gap = 1.0 - 0.85 * (1.0 - smoothstep(0.0, 0.035, abs(r - 1.86)));
                    float dens = bands * gap * smoothstep(1.35, 1.45, r) * (1.0 - smoothstep(2.15, ringOuter, r));
                    // Shadow of the planet on the ring.
                    vec3 toC = centre - P;
                    float along = dot(toC, L);
                    float shadow = (along > 0.0 && dot(toC, toC) - along * along < R * R) ? 0.08 : 1.0;
                    vec3 albedo = mix(vec3(0.62, 0.55, 0.45), vec3(0.85, 0.8, 0.7), bands);
                    // Rings scatter forward and back; lit from either face.
                    vec3 rad = albedo * INV_PI * (lightE * abs(dot(p.spinAxis, L)) * shadow + ambientE * 0.4);
                    ring = vec4(rad, saturate(dens * 0.75));
                    tRing = t;
                }
            }
        }

        // Composite this planet's ring and body front to back.
        vec4 front = tRing < tBody ? ring : body;
        vec4 back = tRing < tBody ? body : ring;
        vec4 pl = vec4(front.rgb * front.a + back.rgb * back.a * (1.0 - front.a), front.a + back.a * (1.0 - front.a));
        if (pl.a <= 0.0) continue;
        // Planets are far apart: order by distance, nearer over farther.
        float tPl = min(tBody, tRing);
        if (tPl < nearest) {
            colour = pl.rgb + colour * (1.0 - pl.a);
            alpha = pl.a + alpha * (1.0 - pl.a);
            nearest = tPl;
        } else {
            colour += pl.rgb * (1.0 - alpha);
            alpha += pl.a * (1.0 - alpha);
        }
    }
    return vec4(colour, alpha);
}

#endif

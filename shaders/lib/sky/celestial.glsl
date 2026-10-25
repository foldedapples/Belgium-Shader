#ifndef SKY_CELESTIAL_GLSL
#define SKY_CELESTIAL_GLSL
#include "/lib/core/common.glsl"

// Deterministic celestial model (ORIGINAL_ARCHITECTURE.md sec. 4).
//
// Sun: vanilla direction (authoritative for gameplay time).
// Moon: its hour angle trails the sun's by the elongation E. E advances 2*pi per synodic
// period of 8 Minecraft days and is phase-locked so moonPhase 0 (vanilla "full moon") is
// E = pi at midnight. The moon is lifted out of the sun's path by an ecliptic latitude
// beta = i * sin(u); the argument of latitude u is built so that syzygies drift through the
// orbital nodes with period ECLIPSE_CYCLE_DAYS - eclipses happen when a new/full moon falls
// near a node, exactly as in reality, just on a compressed calendar.

const float SYNODIC_DAYS = 8.0;

float deg2rad(float d) { return d * (PI / 180.0); }

// Diurnal rotation axis of the sun's path. Minecraft's path always passes through the east and
// west horizon points and is tilted by sunPathRotation; the sign convention is resolved
// against the live sun direction so we never depend on an assumed handedness.
vec3 celestialAxis(vec3 sunDir) {
    float r = deg2rad(sunPathRotation);
    vec3 a0 = vec3(0.0, sin(r), cos(r));
    vec3 a1 = vec3(0.0, -sin(r), cos(r));
    vec3 a2 = -a0;
    vec3 a3 = -a1;
    // The sun rises at +X and moves by +2*pi*sunAngle about the axis.
    float ang = TAU * sunAngle;
    vec3 east = vec3(1.0, 0.0, 0.0);
    float s0 = dot(rotateAxis(east, a0, ang), sunDir);
    float s1 = dot(rotateAxis(east, a1, ang), sunDir);
    float s2 = dot(rotateAxis(east, a2, ang), sunDir);
    float s3 = dot(rotateAxis(east, a3, ang), sunDir);
    vec3 best = a0; float bs = s0;
    if (s1 > bs) { best = a1; bs = s1; }
    if (s2 > bs) { best = a2; bs = s2; }
    if (s3 > bs) { best = a3; bs = s3; }
    return best;
}

// Continuous time in days, split to keep precision for large worldDay values.
float dayFraction() { return float(worldTime % 24000) / 24000.0; }

// Monotonic time warp that slows the moon only near new and full moon, so eclipses last
// minutes of real time instead of seconds while the rest of the month advances normally.
// Phase speed = 1 - k*(cos^8(2*pi*phi) - 35/128): narrow dip of depth `strength` at syzygy.
// Its antiderivative has a finite Fourier series (cos^8 expansion), giving this closed form.
float warpSynodicPhase(float phi, float strength) {
    float s = clamp(strength, 0.0, 0.92);
    float k = s * 128.0 / 93.0;
    float x = TAU * phi;
    float series = 28.0 * sin(2.0 * x) + 7.0 * sin(4.0 * x) + (4.0 / 3.0) * sin(6.0 * x) + 0.125 * sin(8.0 * x);
    return phi - k / (TAU * 128.0) * series;
}

struct CelestialState {
    vec3  sunDir;
    vec3  moonDir;
    vec3  axis;
    float elongation;   // radians, 0 new .. pi full
    float phaseAngle;   // sun-moon-observer angle
    float sunRadius;    // angular radius (rad)
    float moonRadius;
    float solarCoverage; // 0..1 fraction of the (limb-darkened) sun hidden
    float lunarUmbra;    // 0..1 disk-averaged depth in umbra
    float lunarPenumbra; // 0..1 disk-averaged penumbral dimming
    bool  preview;
};

// Synodic phase phi in [0,1): 0 full moon, 0.5 new moon. Full moon is at midnight of
// day 0 (vanilla moonPhase 0); new moon is placed at noon of day 4 so conjunctions - and
// therefore solar eclipses - happen with the sun up. The waning half lasts 3.5 days and the
// waxing half 4.5; the syzygy slowdown hides the change of rate.
float synodicPhase() {
    float t = mod(float(worldDay % 8) + dayFraction() - 0.75, 8.0);
    return t < 3.5 ? t / 7.0 : 0.5 + (t - 3.5) / 9.0;
}

// Phase of the nodal cycle. The effective period is ECLIPSE_CYCLE_DAYS + 2.5 days: node
// passages then drift 1.25 days per eclipse season against the 8-day month, so seasons
// alternate between catching new moons (solar) and full moons (lunar). An integer multiple
// of 8 would lock every season to the same phase. 2*(C + 2.5) is an integer, so wrapping
// worldDay by it keeps the cycle exact for any world age.
float nodalPhase() {
    int c = max(int(ECLIPSE_CYCLE_DAYS), 1);
    int wrap = 2 * c + 5;
    float period = float(c) + 2.5;
    float t = float(worldDay % wrap) + dayFraction();
    return fract(t / period);
}

// Limb darkening of the solar photosphere (quadratic law with typical visible coefficients).
float solarLimbDarkening(float mu) {
    return 1.0 - 0.56 * (1.0 - mu) - 0.24 * sq(1.0 - mu);
}

// Fraction of the sun's limb-darkened flux hidden by a disk of radius rm at angular separation
// sep. Integrated numerically on a polar grid (begin.csh runs this once per frame).
float solarOcclusion(float rs, float rm, float sep) {
    if (sep >= rs + rm) return 0.0;
    float hidden = 0.0, total = 0.0;
    const int NR = 12, NA = 24;
    for (int i = 0; i < NR; i++) {
        float rr = (float(i) + 0.5) / float(NR);
        float mu = sqrt(max(1.0 - rr * rr, 0.0));
        float w = solarLimbDarkening(mu) * rr;
        for (int j = 0; j < NA; j++) {
            float a = TAU * (float(j) + 0.5) / float(NA);
            vec2 p = rr * rs * vec2(cos(a), sin(a));
            float d = length(p - vec2(sep, 0.0));
            hidden += w * step(d, rm);
            total += w;
        }
    }
    return hidden / max(total, EPSILON);
}

// Earth's shadow at the moon's distance, in units of the moon's angular radius (real-world
// ratios: umbra ~2.7, penumbra ~4.9 lunar radii).
const float UMBRA_RATIO = 2.7;
const float PENUMBRA_RATIO = 4.9;

// Direct-sunlight fraction reaching a point on the moon at angular distance d from the
// anti-sun point: 0 inside the umbra, linear across the penumbra (the penumbral profile is the
// sun's disk progressively uncovered by Earth).
float lunarSunlitFraction(float d, float rm) {
    float ru = UMBRA_RATIO * rm, rp = PENUMBRA_RATIO * rm;
    return smoothstep(ru, rp, d);
}

void lunarShadowAverages(vec3 moonDir, vec3 antiSun, float rm, out float umbra, out float penumbra) {
    float sep = acos(clamp(dot(moonDir, antiSun), -1.0, 1.0));
    umbra = 0.0; penumbra = 0.0;
    if (sep > (PENUMBRA_RATIO + 1.0) * rm) return;
    float sumLit = 0.0, sumUmbra = 0.0, n = 0.0;
    const int NG = 9;
    for (int i = 0; i < NG; i++) for (int j = 0; j < NG; j++) {
        vec2 q = (vec2(i, j) + 0.5) / float(NG) * 2.0 - 1.0;
        if (dot(q, q) > 1.0) continue;
        // Offset along the separation axis only matters radially; use planar approximation.
        float d = length(vec2(sep, 0.0) + q * rm);
        float lit = lunarSunlitFraction(d, rm);
        sumLit += lit;
        sumUmbra += step(d, UMBRA_RATIO * rm);
        n += 1.0;
    }
    penumbra = 1.0 - sumLit / max(n, 1.0);
    umbra = sumUmbra / max(n, 1.0);
}

CelestialState computeCelestial(vec3 sunDir) {
    CelestialState c;
    c.sunDir = sunDir;
    c.axis = celestialAxis(sunDir);
    c.sunRadius = deg2rad(BE_SUN_SIZE) * 0.5;
    c.moonRadius = deg2rad(BE_MOON_SIZE) * 0.5;
    c.preview = false;

    float phi = synodicPhase();
    float phiWarped = warpSynodicPhase(phi, ECLIPSE_SLOWDOWN);
    float E = PI + TAU * phiWarped;               // elongation east of the sun
    // Argument of latitude: at syzygy (phi = 0 or 0.5) beta = +/-i*sin(2*pi*nodalPhase), so
    // eclipse seasons recur twice per ECLIPSE_CYCLE_DAYS.
    float beta = deg2rad(MOON_INCLINATION) * sin(TAU * (phiWarped + nodalPhase()));

    #if BE_ECLIPSE_PREVIEW != 0
    {
        // Preview: hold the moon at the relevant syzygy and sweep it across the sun/umbra over
        // a 60-second loop of real time, independent of world time.
        c.preview = true;
        float sweep = cos(TAU * fract(frameTimeCounter / 60.0));
        float sumR = c.sunRadius + c.moonRadius;
        #if BE_ECLIPSE_PREVIEW == 1 || BE_ECLIPSE_PREVIEW == 3
            float minSep = 0.55;   // partial
        #else
            float minSep = 0.0;    // total
        #endif
        float reach = (BE_ECLIPSE_PREVIEW <= 2) ? sumR : (PENUMBRA_RATIO + 1.0) * c.moonRadius;
        beta = mix(minSep * reach, 1.6 * reach, 0.5 + 0.5 * sweep);
        E = (BE_ECLIPSE_PREVIEW <= 2) ? 0.0 : PI;
        phi = (BE_ECLIPSE_PREVIEW <= 2) ? 0.5 : 0.0;
    }
    #endif

    vec3 inPlane = rotateAxis(sunDir, c.axis, -E);
    c.moonDir = safeNormalize(inPlane * cos(beta) + c.axis * sin(beta));
    c.elongation = acos(clamp(dot(c.moonDir, sunDir), -1.0, 1.0));
    c.phaseAngle = PI - c.elongation;

    float sepSun = c.elongation;
    c.solarCoverage = solarOcclusion(c.sunRadius, c.moonRadius, sepSun);
    lunarShadowAverages(c.moonDir, -sunDir, c.moonRadius, c.lunarUmbra, c.lunarPenumbra);
    return c;
}

// Disk-integrated reflectance law of the moon as a function of phase angle: a Lambert sphere
// blended with a Lommel-Seeliger sphere (which matches the flat-looking full moon), plus a
// small opposition surge near full moon. Normalised to 1 at full.
float lunarPhaseLaw(float alpha) {
    // tan(alpha/2) diverges at alpha = pi (new moon) where the integral itself goes to 0.
    alpha = clamp(alpha, 1e-3, PI - 2e-2);
    float lambert = (sin(alpha) + (PI - alpha) * cos(alpha)) / PI;
    float ls = 1.0 - sin(alpha * 0.5) * tan(alpha * 0.5) * log(1.0 / tan(alpha * 0.25));
    ls = max(ls, 0.0);
    float opposition = 1.0 + 0.35 * exp(-alpha * 12.0);
    return clamp(mix(lambert, ls, 0.6) * opposition / 1.35, 0.0, 1.0);
}

#endif

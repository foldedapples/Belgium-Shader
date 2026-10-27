#ifndef MERIDIAN_OKLAB
#define MERIDIAN_OKLAB

// Oklab perceptual colour space (Björn Ottosson 2020, public domain / MIT; matrices from the
// published definition, see THIRD_PARTY_NOTICES.md). L lightness, a/b opponent axes; scaling a
// and b at constant L changes chroma without changing the perceived hue, which RGB-space
// saturation does not (blues drift to purple, oranges to yellow).

vec3 linearToOklab(vec3 c) {
    const mat3 M1 = mat3(0.4122214708, 0.2119034982, 0.0883024619,
                         0.5363325363, 0.6806995451, 0.2817188376,
                         0.0514459929, 0.1073969566, 0.6299787005);
    const mat3 M2 = mat3(0.2104542553, 1.9779984951, 0.0259040371,
                         0.7936177850, -2.4285922050, 0.7827717662,
                         -0.0040720468, 0.4505937099, -0.8086757660);
    vec3 lms = M1 * c;
    lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    return M2 * lms;
}

vec3 oklabToLinear(vec3 lab) {
    const mat3 M2I = mat3(1.0, 1.0, 1.0,
                          0.3963377774, -0.1055613458, -0.0894841775,
                          0.2158037573, -0.0638541728, -1.2914855480);
    const mat3 M1I = mat3(4.0767416621, -1.2684380046, -0.0041960863,
                          -3.3077115913, 2.6097574011, -0.7034186147,
                          0.2309699292, -0.3413193965, 1.7076147010);
    vec3 lms = M2I * lab;
    return M1I * (lms * lms * lms);
}

// Brings an Oklab colour into the sRGB gamut by reducing its chroma at constant lightness and hue
// (bisection for the boundary), with a soft knee from 80 % of the boundary so saturated colours
// keep their gradations instead of flattening against it. Returns linear sRGB in [0, 1].
vec3 oklabToDisplay(vec3 lab) {
    float lo = 0.0, hi = 1.0;
    for (int i = 0; i < 10; i++) {
        float mid = 0.5 * (lo + hi);
        vec3 c = oklabToLinear(vec3(lab.x, lab.yz * mid));
        if (all(greaterThanEqual(c, vec3(-1e-4))) && all(lessThanEqual(c, vec3(1.0001)))) lo = mid;
        else hi = mid;
    }
    float r = 1.0 / max(lo, 1e-4);            // distance of the colour from the boundary (1 = on it)
    const float KNEE = 0.8;
    float rc = r < KNEE ? r : KNEE + (1.0 - KNEE) * tanh((r - KNEE) / (1.0 - KNEE));
    return saturate(oklabToLinear(vec3(lab.x, lab.yz * (rc / r))));
}

#endif

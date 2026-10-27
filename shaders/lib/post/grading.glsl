#ifndef MERIDIAN_GRADING
#define MERIDIAN_GRADING

#include "/lib/post/oklab.glsl"

// Colour profiles (COLOR_PROFILE): 0 Natural, 1 Vibrant (default), 2 Cinematic, 3 Realistic,
// 4 Fantasy, 5 Custom. Grading happens in two places: white balance and scene-referred saturation before
// tone mapping, contrast/vibrance/split-tone after it. "Vibrance" raises the chroma of muted
// colours more than of already vivid ones (in Oklab, so hues do not drift), less for foliage
// hues (no neon grass) and not in highlights. The profiles are milder than before because the
// default tone mapper (Belgium filmic) now supplies the contrast and mid-tone saturation that the
// flat old curve lacked.

struct Grade {
    float saturation;   // scene-referred, applied before tone mapping
    float vibrance;     // display-referred
    float contrast;     // display-referred, around mid grey
    float whiteBalance; // kelvin of the light treated as white
    vec3  shadowTint;   // split toning
    vec3  highlightTint;
};

Grade currentGrade() {
    Grade g;
    g.saturation = 1.0; g.vibrance = 0.0; g.contrast = 1.0; g.whiteBalance = 6500.0;
    g.shadowTint = vec3(0.0); g.highlightTint = vec3(0.0);
    #if COLOR_PROFILE == 1
    g.saturation = 1.03; g.vibrance = 0.15; g.contrast = 1.03;
    #elif COLOR_PROFILE == 2
    g.saturation = 0.95; g.vibrance = 0.04; g.contrast = 1.08;
    g.shadowTint = vec3(-0.012, 0.004, 0.018); g.highlightTint = vec3(0.020, 0.006, -0.016);
    #elif COLOR_PROFILE == 3
    // Photographic: the tone mapper's own contrast and colour, a little vibrance, slightly cooler
    // shadows, no stylisation.
    g.saturation = 1.0; g.vibrance = 0.06; g.contrast = 1.0;
    g.shadowTint = vec3(-0.004, 0.0, 0.006);
    #elif COLOR_PROFILE == 4
    g.saturation = 1.12; g.vibrance = 0.28; g.contrast = 1.03;
    g.shadowTint = vec3(0.010, -0.006, 0.020); g.highlightTint = vec3(0.012, 0.010, -0.004);
    #elif COLOR_PROFILE == 5
    g.saturation = CUSTOM_SATURATION; g.vibrance = CUSTOM_VIBRANCE; g.contrast = CUSTOM_CONTRAST;
    g.whiteBalance = float(CUSTOM_WHITE_BALANCE);
    g.shadowTint = vec3(-0.6, 0.0, 0.6) * CUSTOM_SHADOW_TINT * 0.05;
    g.highlightTint = vec3(0.6, 0.2, -0.6) * CUSTOM_SHADOW_TINT * 0.05;
    #endif
    return g;
}

// Von Kries adaptation in the Bradford cone space (Lam 1985), from the white of a blackbody at
// `kelvin` to D65.
vec3 whiteBalance(vec3 c, float kelvin) {
    if (abs(kelvin - 6500.0) < 1.0) return c;
    const mat3 RGB_TO_XYZ = mat3(0.4124, 0.2126, 0.0193, 0.3576, 0.7152, 0.1192, 0.1805, 0.0722, 0.9505);
    const mat3 XYZ_TO_RGB = mat3(3.2406, -0.9689, 0.0557, -1.5372, 1.8758, -0.2040, -0.4986, 0.0415, 1.0570);
    const mat3 BRADFORD = mat3(0.8951, -0.7502, 0.0389, 0.2664, 1.7135, -0.0685, -0.1614, 0.0367, 1.0296);
    vec3 src = RGB_TO_XYZ * blackbody(kelvin);
    vec3 dst = RGB_TO_XYZ * blackbody(6500.0);
    vec3 s = BRADFORD * (src / src.y), d = BRADFORD * (dst / dst.y);
    vec3 lms = BRADFORD * (RGB_TO_XYZ * c);
    lms *= d / s;
    return max(XYZ_TO_RGB * (inverse(BRADFORD) * lms), 0.0);
}

vec3 applySceneGrade(vec3 c, Grade g) {
    c = whiteBalance(c, g.whiteBalance);
    float l = luminance(c);
    return max(mix(vec3(l), c, g.saturation), 0.0);
}

vec3 applyDisplayGrade(vec3 c, Grade g) {
    // Contrast around display mid grey in a perceptual (sqrt) domain, weighted by 4p(1-p) so black
    // and white stay where they are. The plain (p - 0.45) * k + 0.45 it replaces is not anchored
    // at black: at Vibrant's 1.06 every display value below 0.00065 became pure black (Cinematic:
    // below 0.0026), which crushed moonlit and cave shadows. Monotonic for contrast 0.7 .. 1.4.
    vec3 p = sqrt(saturate(c));
    p += (g.contrast - 1.0) * (p - 0.45) * (4.0 * p * (1.0 - p));
    c = p * p;
    // Vibrance in Oklab: muted colours gain the most (none above chroma 0.18), foliage hues
    // (~135 degrees) half as much, highlights none.
    if (g.vibrance != 0.0) {
        vec3 lab = linearToOklab(c);
        float chroma = length(lab.yz);
        float hue = degrees(atan(lab.z, lab.y));
        float foliage = exp(-pow((hue - 135.0) / 22.0, 2.0));
        float boost = g.vibrance * (1.0 - smoothstep(0.0, 0.18, chroma)) * (1.0 - 0.5 * foliage) * (1.0 - smoothstep(0.85, 1.0, lab.x));
        c = oklabToDisplay(vec3(lab.x, lab.yz * (1.0 + boost)));
    }
    float l = luminance(c);
    // Split toning by luminance, as a gain per channel: black stays black. The tint used to be
    // added, which lifted black to (0, 0.004, 0.018) in Cinematic (a blue-grey veil over every
    // shadow, ~15 % in sRGB) and swung the hue of shaded grass by 10-25 degrees in Realistic.
    c *= 1.0 + 5.0 * (g.shadowTint * (1.0 - smoothstep(0.0, 0.4, l)) + g.highlightTint * smoothstep(0.35, 1.0, l));
    return saturate(c);
}

// Scotopic (rod) vision at low light: desaturation and a blue shift (Purkinje effect). `dark`
// in 0..1 from the adapted exposure.
vec3 purkinje(vec3 c, float dark) {
    #ifdef PURKINJE
    // Rod response peaks near 507 nm; approximate rod luminance from linear RGB.
    float rod = dot(c, vec3(0.05, 0.65, 0.55));
    vec3 scotopic = rod * vec3(0.62, 0.78, 1.0);
    return mix(c, scotopic, dark * 0.7);
    #else
    return c;
    #endif
}

#endif

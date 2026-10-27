#ifndef MERIDIAN_GRADING
#define MERIDIAN_GRADING

// Colour profiles (COLOR_PROFILE): 0 Natural, 1 Vibrant (default), 2 Cinematic, 3 Realistic,
// 4 Fantasy, 5 Custom. Grading happens in two places: white balance and scene-referred saturation before
// tone mapping, contrast/vibrance/split-tone after it. "Vibrance" raises the saturation of muted
// colours more than of already vivid ones, so grass and skies gain richness while saturated
// light sources and dyed blocks do not clip.

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
    g.saturation = 1.06; g.vibrance = 0.18; g.contrast = 1.06;
    #elif COLOR_PROFILE == 2
    g.saturation = 0.96; g.vibrance = 0.05; g.contrast = 1.12;
    g.shadowTint = vec3(-0.012, 0.004, 0.018); g.highlightTint = vec3(0.020, 0.006, -0.016);
    #elif COLOR_PROFILE == 3
    // Photographic: a touch of contrast and vibrance, slightly cooler shadows, no stylisation.
    g.saturation = 0.98; g.vibrance = 0.08; g.contrast = 1.04;
    g.shadowTint = vec3(-0.004, 0.0, 0.006);
    #elif COLOR_PROFILE == 4
    g.saturation = 1.15; g.vibrance = 0.32; g.contrast = 1.04;
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
    // Vibrance: boost scaled by how unsaturated the colour is.
    float mx = maxOf(c), mn = minOf(c);
    float sat = mx > 1e-4 ? (mx - mn) / mx : 0.0;
    float l = luminance(c);
    c = mix(vec3(l), c, 1.0 + g.vibrance * (1.0 - sat) * (1.0 - sat));
    // Split toning by luminance.
    c += g.shadowTint * (1.0 - smoothstep(0.0, 0.4, l)) + g.highlightTint * smoothstep(0.35, 1.0, l);
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

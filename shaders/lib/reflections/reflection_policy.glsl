#ifndef REFLECTIONS_POLICY_GLSL
#define REFLECTIONS_POLICY_GLSL
#include "/lib/material/labpbr.glsl"

// Deferred lighting and the composite pass must agree on which surfaces get screen-space
// reflections: those skip the environment specular in deferred, and composite adds the
// traced (or fallback) reflection instead, so no reflection is counted twice.
// With the camera under water composite does not run the opaque branch; submerged surfaces
// keep the environment term from deferred lighting. (Surfaces seen through water from above
// lose their sky reflection, which is physically right: they are under water.)
bool usesScreenSpaceReflection(Material m, int flags) {
    #ifdef OPAQUE_SSR
        // Never on the hand (1) or LOD terrain (8): their depth is not in the traced buffer.
        return m.smoothness >= SSR_MIN_SMOOTHNESS && (flags & 9) == 0 && isEyeInWater != 1;
    #else
        return false;
    #endif
}

#endif

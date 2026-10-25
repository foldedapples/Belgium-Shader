// Halcyon compatibility shim at Glimmer's /lib/common.glsl path, included only by Halcyon's own
// programs (shaders/program/halcyon/). It provides just what they use - Belgium's settings and
// the Iris uniforms below - so they compile unmodified. Belgium's code uses /lib/core/common.glsl.
#ifndef HALCYON_SHIM_COMMON_GLSL
#define HALCYON_SHIM_COMMON_GLSL
#include "/lib/core/settings.glsl"
uniform vec3  cameraPosition;
#if IRIS_VERSION >= 10700
    uniform ivec3 cameraPositionInt;
    uniform vec3  cameraPositionFract;
#else
    #define cameraPositionInt ivec3(floor(cameraPosition))
    #define cameraPositionFract (cameraPosition - floor(cameraPosition))
#endif
uniform float frameTime;
uniform vec3  relativeEyePosition;
uniform int   isEyeInWater;
float pow2(float x) { return x * x; }
#endif

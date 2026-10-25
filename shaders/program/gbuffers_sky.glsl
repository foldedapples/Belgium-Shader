// Vanilla sky geometry (sky dome, sunrise fan, stars, void plane, textured sun/moon, End sky
// box, custom-sky resource packs). The pack renders its own sky in deferred2 for every pixel
// without geometry, so these draws are discarded entirely.
#include "/lib/core/common.glsl"

#ifdef STAGE_VERTEX
void main() {
    gl_Position = ftransform();
}
#endif

#ifdef STAGE_FRAGMENT
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;
void main() {
    discard;
}
#endif

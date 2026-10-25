#ifndef CORE_TEXTURES_GLSL
#define CORE_TEXTURES_GLSL
// Shared custom textures declared once (several modules sample them).
uniform sampler2D noise2dTex;   // 256^2 tileable value-noise fBm, four octave bases (gen_noise.py)
#endif

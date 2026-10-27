// composite4: bloom source. Builds six progressively blurred copies of the HDR image (mip levels
// 2..7, each filtered with a 9-tap tent) into a tile atlas in colortex9 (half resolution).
// Inputs are softly limited in exposed units so the sun disk cannot flood the screen.
// The final pass combines the tiles (lib/post/bloom.glsl).

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/state.glsl"
#include "/lib/post/bloom.glsl"

uniform sampler2D colortex0;

in vec2 texcoord;

/*
const bool colortex0MipmapEnabled = true;
const int colortex9Format = RGBA16F;
const bool colortex9Clear = true;
*/

/* RENDERTARGETS: 9 */
layout(location = 0) out vec4 outBloom;

void main() {
    int level;
    vec2 local;
    if (!bloomTileFromAtlas(texcoord, level, local)) { outBloom = vec4(0.0); return; }
    float lod = float(level - 1);
    vec2 texel = exp2(lod) / vec2(viewWidth, viewHeight);
    vec3 c = vec3(0.0);
    const vec3 w = vec3(1.0, 2.0, 1.0);
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        vec2 suv = clamp(local + vec2(i, j) * texel, vec2(0.0), vec2(1.0));
        c += textureLod(colortex0, suv, lod).rgb * (w[i + 1] * w[j + 1]);
    }
    c /= 16.0;
    // Soft limit in display-referred units (exposure applied) to keep the sun's glare bounded.
    float ex = max(state.exposure, 1e-6);
    float l = luminance(c) * ex;
    const float LIMIT = 24.0;
    c *= LIMIT / (LIMIT + l);
    if (any(isnan(c))) c = vec3(0.0);
    outBloom = vec4(c, 1.0);
}

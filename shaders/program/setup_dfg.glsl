// setup2.csh - split-sum DFG LUT (64x64 over NdotV x perceptual roughness). Stores the scale
// (x) and bias (y) applied to F0 for the GGX / height-correlated Smith BRDF integrated over the
// hemisphere, so prefiltered environment light can be weighted correctly: E = F0*x + y.
// Integrated numerically with GGX importance sampling (Hammersley points).
#include "/lib/core/common.glsl"
#include "/lib/lighting/brdf.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const ivec3 workGroups = ivec3(8, 8, 1);

layout(rg16f) uniform writeonly image2D dfgLut;

float radicalInverse(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10;
}

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(px, ivec2(64)))) return;
    float nDotV = max((float(px.x) + 0.5) / 64.0, 1e-3);
    float perceptual = (float(px.y) + 0.5) / 64.0;
    float alpha = max(perceptual * perceptual, 0.0016);

    vec3 v = vec3(sqrt(1.0 - nDotV * nDotV), 0.0, nDotV);
    float a = 0.0, b = 0.0;
    const uint SAMPLES = 512u;
    for (uint i = 0u; i < SAMPLES; i++) {
        vec2 xi = vec2(float(i) / float(SAMPLES), radicalInverse(i));
        // GGX half-vector sample
        float phi = TAU * xi.x;
        float cosH = sqrt((1.0 - xi.y) / (1.0 + (alpha * alpha - 1.0) * xi.y));
        float sinH = sqrt(max(1.0 - cosH * cosH, 0.0));
        vec3 h = vec3(sinH * cos(phi), sinH * sin(phi), cosH);
        vec3 l = reflect(-v, h);
        float nDotL = l.z;
        if (nDotL <= 0.0) continue;
        float nDotH = max(h.z, 0.0);
        float vDotH = max(dot(v, h), 0.0);
        // pdf(l) = D * nDotH / (4 vDotH); BRDF*cos/pdf = V * 4 * nDotL * vDotH / nDotH
        float vis = smithVisibilityCorrelated(nDotV, nDotL, alpha);
        float g = vis * 4.0 * nDotL * vDotH / max(nDotH, 1e-5);
        float fc = pow5(1.0 - vDotH);
        a += (1.0 - fc) * g;
        b += fc * g;
    }
    imageStore(dfgLut, px, vec4(a / float(SAMPLES), b / float(SAMPLES), 0.0, 0.0));
}
#endif

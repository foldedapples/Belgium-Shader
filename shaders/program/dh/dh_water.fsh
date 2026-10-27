// Distant Horizons water -> translucent G-buffer. Only the cheap analytic waves are used here; the
// interactive simulation and rain ripples stay near the player (they are invisible at LOD range).

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/common/gbuffer.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/water/waves.glsl"

in vec4 vColor;
in vec2 vLightmap;
in vec3 vNormal;
in vec3 vPlayerPos;
flat in int vMaterial;

/* RENDERTARGETS: 4,5 */
layout(location = 0) out vec4 outSurface;
layout(location = 1) out vec4 outTint;

void main() {
    // DH draws before vanilla terrain, which then overwrites the G-buffer wherever it exists.
    // Inside most of the vanilla range DH geometry is skipped so it cannot show through gaps.
    if (length(vPlayerPos.xz) < far * 0.8) discard;
    vec3 n = normalize(vNormal);
    vec2 lm = normalizeLightmap(vLightmap);
    int id = vMaterial == DH_BLOCK_WATER ? MAT_WATER : MAT_GLASS;
    float lostSlopeVar = 0.0;
    if (id == MAT_WATER && n.y > 0.5) {
        #ifdef WATER_WAVES
        // Same per-frequency footprint prefilter as vanilla water (gbuffers/translucent.fsh).
        float footprint = max(length(dFdx(vPlayerPos.xz)), length(dFdy(vPlayerPos.xz)));
        WaterParams wp = waterParamsAt(n, lm.y);
        vec3 hg = waveHeightGradFiltered((vPlayerPos + cameraPosition).xz, frameTimeCounter, wp, footprint, lostSlopeVar);
        n = normalize(vec3(-hg.y, 1.0, -hg.z));
        #endif
    }
    outSurface = vec4(octEncode(n), pack2x8(lm), pack2x8u(uint(id), uint(FLAG_LOD)));
    outTint = vec4(vColor.rgb, id == MAT_WATER ? encodeWaterRoughness(waveLostAlpha(lostSlopeVar)) : vColor.a);
}

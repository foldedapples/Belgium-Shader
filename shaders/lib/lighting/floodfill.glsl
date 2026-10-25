#ifndef LIGHTING_FLOODFILL_GLSL
#define LIGHTING_FLOODFILL_GLSL
#include "/lib/core/common.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/post/color_profile.glsl"

// Coloured block light (ORIGINAL_ARCHITECTURE.md sec. 5, 16).
//
// 1. shadow.vsh voxelises terrain into voxelMap (R32UI, 128x64x128 blocks around the camera,
//    cleared every frame): occupancy, emitter class, emission level and glass tint.
// 2. shadowcomp.csh diffuses coloured light through that grid, one step per frame, ping-
//    ponging lightVolA/B; opaque voxels block it, tinted glass filters it.
// 3. Lighting uses only the *chroma* of the diffused light. Intensity still comes from the
//    vanilla block lightmap, so coloured light can never reach further than Minecraft's own
//    light does: no leaking through walls beyond what vanilla already shows.

const ivec3 LV_SIZE = ivec3(128, 64, 128);

// Voxel word layout.
const uint LV_OPAQUE = 1u;          // blocks light
const uint LV_GLASS = 2u;           // filters light by tint
const uint LV_FOLIAGE = 4u;         // attenuates light
// bits 4..11: material class, bits 12..15: emission level, bits 16..31: tint RGB565

ivec3 lightVolumeOrigin(ivec3 cameraBlock) { return cameraBlock - LV_SIZE / 2; }

uint packVoxel(uint flags, int material, int level, vec3 tint) {
    uvec3 t = uvec3(saturate(tint) * vec3(31.0, 63.0, 31.0) + 0.5);
    return flags | (uint(material & 255) << 4) | (uint(clamp(level, 0, 15)) << 12)
         | (t.r << 27) | (t.g << 21) | (t.b << 16);
}
int voxelMaterial(uint v) { return int((v >> 4) & 255u); }
int voxelLevel(uint v) { return int((v >> 12) & 15u); }
vec3 voxelTint(uint v) {
    return vec3(float((v >> 27) & 31u) / 31.0, float((v >> 21) & 63u) / 63.0, float((v >> 16) & 31u) / 31.0);
}

#ifdef LIGHT_VOLUME_READ
uniform sampler3D lightVolATex;
uniform sampler3D lightVolBTex;

vec3 lightVolumeUvw(vec3 scenePos) {
    vec3 local = cameraPositionFract + scenePos;
    vec3 p = vec3(cameraPositionInt - lightVolumeOrigin(cameraPositionInt)) + local;
    return p / vec3(LV_SIZE);
}
vec3 sampleLightVolume(vec3 uvw) {
    // shadowcomp writes B on even frames, A on odd frames.
    return (frameCounter & 1) == 0 ? texture(lightVolBTex, uvw).rgb : texture(lightVolATex, uvw).rgb;
}

// Light-volume gradient toward the dominant nearby source (xyz) and a confidence (w), for any
// use (blockLightDirection below is the specular variant behind its own option).
vec4 blockLightDirectionAny(vec3 scenePos, vec3 normal) {
    #ifdef COLORED_LIGHTING
        vec3 uvw = lightVolumeUvw(scenePos + normal * 0.55);
        if (any(lessThan(uvw, vec3(0.03))) || any(greaterThan(uvw, vec3(0.97)))) return vec4(0.0);
        vec3 e = 1.0 / vec3(LV_SIZE);
        vec3 g = vec3(luminance(sampleLightVolume(uvw + vec3(e.x, 0.0, 0.0))) - luminance(sampleLightVolume(uvw - vec3(e.x, 0.0, 0.0))),
                      luminance(sampleLightVolume(uvw + vec3(0.0, e.y, 0.0))) - luminance(sampleLightVolume(uvw - vec3(0.0, e.y, 0.0))),
                      luminance(sampleLightVolume(uvw + vec3(0.0, 0.0, e.z))) - luminance(sampleLightVolume(uvw - vec3(0.0, 0.0, e.z))));
        float lum = luminance(sampleLightVolume(uvw));
        float len = length(g);
        if (len <= 1e-6 || lum <= 1e-6) return vec4(0.0);
        return vec4(g / len, smoothstep(0.05, 0.4, len / lum));
    #else
        return vec4(0.0);
    #endif
}

// Direction toward the dominant nearby light source (xyz) and a confidence (w): the gradient
// of the diffused light points up-hill toward emitters. Used to give block light a specular
// highlight on smooth, metallic and wet surfaces.
vec4 blockLightDirection(vec3 scenePos, vec3 normal) {
    #if defined COLORED_LIGHTING && defined BLOCK_LIGHT_SPECULAR
        vec3 uvw = lightVolumeUvw(scenePos + normal * 0.55);
        if (any(lessThan(uvw, vec3(0.03))) || any(greaterThan(uvw, vec3(0.97)))) return vec4(0.0);
        vec3 e = 1.0 / vec3(LV_SIZE);
        float lx = luminance(sampleLightVolume(uvw + vec3(e.x, 0.0, 0.0))) - luminance(sampleLightVolume(uvw - vec3(e.x, 0.0, 0.0)));
        float ly = luminance(sampleLightVolume(uvw + vec3(0.0, e.y, 0.0))) - luminance(sampleLightVolume(uvw - vec3(0.0, e.y, 0.0)));
        float lz = luminance(sampleLightVolume(uvw + vec3(0.0, 0.0, e.z))) - luminance(sampleLightVolume(uvw - vec3(0.0, 0.0, e.z)));
        vec3 g = vec3(lx, ly, lz);
        float lum = luminance(sampleLightVolume(uvw));
        float len = length(g);
        if (len <= 1e-6 || lum <= 1e-6) return vec4(0.0);
        // A clear gradient relative to the local level means a nearby, well-defined source.
        return vec4(g / len, smoothstep(0.05, 0.4, len / lum));
    #else
        return vec4(0.0);
    #endif
}

// Chroma of the coloured block light at a scene-space point (w = confidence 0..1).
vec4 blockLightChroma(vec3 scenePos, vec3 normal) {
    #ifdef COLORED_LIGHTING
        vec3 uvw = lightVolumeUvw(scenePos + normal * 0.55);
        if (any(lessThan(uvw, vec3(0.02))) || any(greaterThan(uvw, vec3(0.98)))) return vec4(1.0, 1.0, 1.0, 0.0);
        vec3 l = sampleLightVolume(uvw);
        float lum = luminance(l);
        if (lum <= 1e-6) return vec4(1.0, 1.0, 1.0, 0.0);
        vec3 chroma = cpSaturate(l / lum, CP_LIGHT_SATURATION);
        chroma /= max(luminance(chroma), 1e-4);
        float edge = 1.0 - smoothstep(0.85, 0.98, maxOf(abs(uvw - 0.5) * 2.0));
        return vec4(chroma, smoothstep(1e-5, 2e-3, lum) * edge);
    #else
        return vec4(1.0, 1.0, 1.0, 0.0);
    #endif
}
#endif

#endif

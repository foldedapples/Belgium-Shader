// shadowcomp: coloured block-light propagation, one step per dispatch. The wrapper sets
// FLOOD_A_TO_B or FLOOD_B_TO_A; dispatches come in pairs so the newest volume is always in A.
// FLOOD_ACTIVE gates the optional extra pairs (CL_ITERATIONS).
//
// Each cell takes the brightest neighbour's level minus one (vanilla's rule), plus extra loss in
// light-filtering blocks (leaves, water), and blends the colours of neighbours that are nearly
// as bright, so where two lights meet the colours mix smoothly instead of forming a hard seam.
// Solid blocks hold no light except their own emission. Cells that wrapped around the toroidal
// volume since the last frame start dark.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/state.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/lighting/emitters.glsl"
#include "/lib/lighting/light_volume.glsl"

layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;
// Iris reads workGroups as literal text: VOXEL_SIZE / (8, 4, 8) for each range.
#if CL_VOLUME == 0
const ivec3 workGroups = ivec3(16, 16, 16);
#elif CL_VOLUME == 1
const ivec3 workGroups = ivec3(24, 24, 24);
#else
const ivec3 workGroups = ivec3(32, 32, 32);
#endif

layout(r16ui) uniform readonly uimage3D voxelImg;
#ifdef FLOOD_A_TO_B
layout(rgba8) uniform readonly image3D lightImgA;
layout(rgba8) uniform writeonly image3D lightImgB;
#define SRC lightImgA
#define DST lightImgB
#else
layout(rgba8) uniform readonly image3D lightImgB;
layout(rgba8) uniform writeonly image3D lightImgA;
#define SRC lightImgB
#define DST lightImgA
#endif

// World block represented by texel `t` for a volume whose min corner is `origin`.
ivec3 blockOf(ivec3 t, ivec3 origin) {
    return origin + (((t - origin) % VOXEL_SIZE) + VOXEL_SIZE) % VOXEL_SIZE;
}

void main() {
    #ifndef COLORED_LIGHTING
    return;
    #endif
    #ifndef FLOOD_ACTIVE
    return;
    #endif
    ivec3 t = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(t, VOXEL_SIZE))) return;
    ivec3 origin = ivec3(state.lightVolumeOrigin.xyz);
    ivec3 prevOrigin = ivec3(state.lightVolumePrevOrigin.xyz);
    ivec3 block = blockOf(t, origin);
    bool fresh = any(notEqual(block, blockOf(t, prevOrigin)));

    uint vox = imageLoad(voxelImg, t).r;
    int id = (vox & 0x8000u) != 0u ? int(vox & 255u) : 0;
    float ownLevel = float((vox >> 8u) & 15u);
    vec2 opacity = voxelOpacity(id);

    vec4 result = vec4(0.0);
    if (ownLevel > 0.5) result = vec4(emitterColor(id), ownLevel / 15.0);

    if (opacity.y < 0.5) {
        // Gather from the six neighbours that are inside the current window.
        const ivec3 dirs[6] = ivec3[6](ivec3(1, 0, 0), ivec3(-1, 0, 0), ivec3(0, 1, 0), ivec3(0, -1, 0), ivec3(0, 0, 1), ivec3(0, 0, -1));
        float best = 0.0;
        vec4 n[6];
        for (int i = 0; i < 6; i++) {
            ivec3 nb = block + dirs[i];
            n[i] = vec4(0.0);
            if (!insideVolume(nb, origin)) continue;
            ivec3 nt = voxelIndex(nb);
            // Neighbours that just wrapped in carry stale light from another place: ignore them.
            if (any(notEqual(nb, blockOf(nt, prevOrigin)))) continue;
            n[i] = imageLoad(SRC, nt);
            best = max(best, n[i].a);
        }
        float level = best - (1.0 + opacity.x) / 15.0;
        if (level > result.a) {
            vec3 col = vec3(0.0);
            float w = 0.0;
            for (int i = 0; i < 6; i++) {
                float wi = exp2((n[i].a - best) * 15.0 * 2.0) * step(1e-3, n[i].a);
                col += n[i].rgb * wi;
                w += wi;
            }
            col /= max(w, 1e-4);
            // Mix with own emission colour if this cell also emits.
            if (result.a > 0.0) col = mix(col, result.rgb, result.a / max(level, 1e-3) * 0.5);
            result = vec4(col / max(maxOf(col), 1e-4), level);
        }
    }
    if (fresh && ownLevel < 0.5 && result.a <= 0.0) result = vec4(0.0);
    imageStore(DST, t, result);
}

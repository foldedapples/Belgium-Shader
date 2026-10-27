// Shadow pass, geometry stage: routes each triangle into the cascades of the 2x2 shadow atlas
// that need it, and (terrain) writes the block into the coloured-light voxel volume.
//
// A triangle goes into cascade k if it overlaps that cascade's square, unless it lies well inside
// cascade k-1, whose finer map serves every receiver there (receivers pick the finest cascade
// whose inner 90 % contains them; casters are skipped only inside the inner 50 %, and receivers'
// filter reach is clamped to that band, so kernels near the switch never miss a caster - see
// tools/tests/test_shadow_stability.py).

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/state.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/lighting/shadow_proj.glsl"
#if defined SHADOW_TERRAIN && defined COLORED_LIGHTING
#include "/lib/lighting/light_volume.glsl"
layout(r16ui) uniform uimage3D voxelImg;
#endif

layout(triangles) in;
layout(triangle_strip, max_vertices = 12) out;

in vec2 gUv[];
in vec4 gColor[];
in vec3 gLightPos[];
in vec3 gPlayerPos[];
in vec3 gNormal[];
flat in int gId[];
flat in vec4 gMidBlock[];

out vec2 fUv;
out vec4 fColor;
out vec3 fNormal;
flat out int fId;
flat out int fCascade;

void main() {
    #if defined SHADOW_TERRAIN && defined COLORED_LIGHTING
    // Voxelise once per triangle: the block centre is shared by all vertices of a face.
    if (state.lightVolumeOrigin.w > 0.5 && gMidBlock[0].w >= 0.0) {
        vec3 c = gPlayerPos[0] + gMidBlock[0].xyz / 64.0 + cameraPositionFract;
        ivec3 block = ivec3(floor(c)) + cameraPositionInt;
        ivec3 origin = ivec3(state.lightVolumeOrigin.xyz);
        if (insideVolume(block, origin)) {
            imageStore(voxelImg, voxelIndex(block), uvec4(encodeVoxel(gId[0], gMidBlock[0].w)));
        }
    }
    #endif

    #ifndef WORLD_NETHER
    for (int k = 0; k < 4; k++) {
        float e = cascadeExtent(k);
        vec2 o = state.cascadeCenter[k].xy;
        vec2 p0 = (gLightPos[0].xy + o) / e;
        vec2 p1 = (gLightPos[1].xy + o) / e;
        vec2 p2 = (gLightPos[2].xy + o) / e;
        vec2 bbMin = min(p0, min(p1, p2));
        vec2 bbMax = max(p0, max(p1, p2));
        if (any(greaterThan(bbMin, vec2(1.0))) || any(lessThan(bbMax, vec2(-1.0)))) continue;
        if (k > 0) {
            float ei = cascadeExtent(k - 1);
            vec2 oi = state.cascadeCenter[k - 1].xy;
            vec2 q0 = abs((gLightPos[0].xy + oi) / ei);
            vec2 q1 = abs((gLightPos[1].xy + oi) / ei);
            vec2 q2 = abs((gLightPos[2].xy + oi) / ei);
            if (maxOf(max(q0, max(q1, q2))) < CASCADE_CASTER_SKIP) continue;
        }
        vec2 center = (cascadeOrigin(k) + 0.25) * 2.0 - 1.0;
        vec2 p[3] = vec2[3](p0, p1, p2);
        for (int i = 0; i < 3; i++) {
            gl_Position = vec4(p[i] * 0.5 + center, -gLightPos[i].z / SHADOW_Z_RANGE, 1.0);
            fUv = gUv[i];
            fColor = gColor[i];
            fNormal = gNormal[i];
            fId = gId[i];
            fCascade = k;
            EmitVertex();
        }
        EndPrimitive();
    }
    #endif
}

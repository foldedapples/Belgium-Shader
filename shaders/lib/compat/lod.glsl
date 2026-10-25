#ifndef COMPAT_LOD_GLSL
#define COMPAT_LOD_GLSL
#include "/lib/core/common.glsl"

// Level-of-detail terrain (ORIGINAL_ARCHITECTURE.md sec. 11).
// Distant Horizons (Iris defines DISTANT_HORIZONS) and Voxy (defines VOXY while it renders)
// draw far terrain into their own depth textures with their own projections. They do not
// share conventions, so each gets its own declarations; when both are present DH wins.
// Assumption to verify in game (Debug View "Linear Depth"): Voxy's depth textures use the
// conventional [0,1] range with vxProj, as both reference packs treat them.

#if defined DISTANT_HORIZONS
    #define LOD_ENABLED
    uniform sampler2D dhDepthTex0;
    uniform sampler2D dhDepthTex1;
    uniform mat4 dhProjection;
    uniform mat4 dhProjectionInverse;
    uniform mat4 dhPreviousProjection;
    uniform int dhRenderDistance;
    float lodDepth(ivec2 px, bool opaqueOnly) { return opaqueOnly ? texelFetch(dhDepthTex1, px, 0).r : texelFetch(dhDepthTex0, px, 0).r; }
    float lodDepthUv(vec2 uv, bool opaqueOnly) { return opaqueOnly ? texture(dhDepthTex1, uv).r : texture(dhDepthTex0, uv).r; }
    vec3 lodScreenToView(vec2 uv, float depth) { return projectAndDivide(dhProjectionInverse, vec3(uv, depth) * 2.0 - 1.0); }
    float lodRenderDistance() { return float(dhRenderDistance); }
#elif defined VOXY
    #define LOD_ENABLED
    uniform sampler2D vxDepthTexOpaque;
    uniform sampler2D vxDepthTexTrans;
    uniform mat4 vxProj;
    uniform mat4 vxProjInv;
    uniform int vxRenderDistance;
    float lodDepth(ivec2 px, bool opaqueOnly) { return opaqueOnly ? texelFetch(vxDepthTexOpaque, px, 0).r : texelFetch(vxDepthTexTrans, px, 0).r; }
    float lodDepthUv(vec2 uv, bool opaqueOnly) { return opaqueOnly ? texture(vxDepthTexOpaque, uv).r : texture(vxDepthTexTrans, uv).r; }
    vec3 lodScreenToView(vec2 uv, float depth) { return projectAndDivide(vxProjInv, vec3(uv, depth) * 2.0 - 1.0); }
    float lodRenderDistance() { return float(vxRenderDistance) * 16.0; }
#endif

// A pixel's surface, merging vanilla depth with LOD depth.
struct ScenePoint {
    bool  sky;
    bool  lod;
    float depth;   // in the projection that produced it
    vec3  view;
    vec3  scene;
    float dist;
};

ScenePoint scenePoint(vec2 uv, float vanillaDepth, ivec2 px, bool opaqueOnly) {
    ScenePoint p;
    p.lod = false;
    p.depth = vanillaDepth;
    p.view = screenToView(uv, vanillaDepth);
    #ifdef LOD_ENABLED
    if (vanillaDepth >= 1.0) {
        float d = lodDepth(px, opaqueOnly);
        if (d < 1.0) {
            p.lod = true;
            p.depth = d;
            p.view = lodScreenToView(uv, d);
        }
    }
    #endif
    p.sky = vanillaDepth >= 1.0 && !p.lod;
    p.scene = viewToScene(p.view);
    p.dist = length(p.view);
    return p;
}

// Distance at which terrain ends (for border fog): LOD range when present.
float terrainRenderDistance() {
    #ifdef LOD_ENABLED
        return max(lodRenderDistance(), far);
    #else
        return far;
    #endif
}

#endif

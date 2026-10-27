#ifndef MERIDIAN_DEPTH
#define MERIDIAN_DEPTH

// Scene depth across vanilla terrain and LOD terrain (Distant Horizons or Voxy). Each source has
// its own depth buffer and projection; this resolves a pixel to a view-space position.
// Requires transform.glsl.

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;
#endif
#ifdef VOXY
uniform sampler2D vxDepthTexOpaque;
uniform sampler2D vxDepthTexTrans;
#endif

struct SceneDepth {
    float depth;     // raw depth in its own buffer
    vec3 viewPos;
    bool sky;        // nothing at all
    bool lod;        // the hit is LOD terrain
};

SceneDepth resolveDepth(vec2 uv, bool opaqueOnly, bool hand) {
    SceneDepth s;
    s.depth = opaqueOnly ? texture(depthtex1, uv).r : texture(depthtex0, uv).r;
    s.lod = false;
    s.sky = false;
    if (s.depth < 1.0) {
        s.viewPos = hand ? screenToViewHand(uv, s.depth) : screenToView(uv, s.depth, gbufferProjectionInverse);
        return s;
    }
    #ifdef DISTANT_HORIZONS
    float dd = opaqueOnly ? texture(dhDepthTex1, uv).r : texture(dhDepthTex0, uv).r;
    if (dd < 1.0) {
        s.depth = dd;
        s.lod = true;
        s.viewPos = screenToView(uv, dd, dhProjectionInverse);
        return s;
    }
    #endif
    #ifdef VOXY
    float vd = opaqueOnly ? texture(vxDepthTexOpaque, uv).r : min(texture(vxDepthTexTrans, uv).r, texture(vxDepthTexOpaque, uv).r);
    if (vd < 1.0) {
        s.depth = vd;
        s.lod = true;
        s.viewPos = screenToView(uv, vd, vxProjInv);
        return s;
    }
    #endif
    s.sky = true;
    s.viewPos = screenToView(uv, 1.0, gbufferProjectionInverse);
    return s;
}

#endif

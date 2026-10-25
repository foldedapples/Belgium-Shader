// deferred1 - cloud reconstruction at full resolution into colortex9 (persistent history).
// 1. Depth-aware upsample of the reduced-resolution march: the four nearest low-res samples
//    are weighted by bilinear position and by how well their depth matches this pixel's
//    (sky vs terrain silhouettes stay sharp).
// 2. Reprojection of last frame's result using the cloud's own distance (sky pixels) or the
//    scene depth, clamped to the low-res neighbourhood's range, then blended.
#include "/lib/core/common.glsl"
#include "/lib/core/fullscreen.glsl"

#ifdef STAGE_FRAGMENT
#include "/lib/core/frame_state.glsl"
#include "/lib/clouds/clouds.glsl"
#include "/lib/compat/lod.glsl"

uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D depthtex0;

in vec2 texCoord;

/* RENDERTARGETS: 9 */
layout(location = 0) out vec4 outHistory;

void main() {
    vec2 lowSize = vec2(viewWidth, viewHeight) * CLOUD_RES;
    vec2 lp = texCoord * lowSize - 0.5;
    ivec2 base = ivec2(floor(lp));
    vec2 f = lp - vec2(base);
    ScenePoint here = scenePoint(texCoord, texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r, ivec2(gl_FragCoord.xy), true);
    float depth = here.sky ? 1.0 : 0.5;
    float linD = here.sky ? 1e6 : here.dist;

    vec4 sum = vec4(0.0);
    float wsum = 0.0;
    vec4 lo = vec4(1e9), hi = vec4(-1e9);
    for (int y = 0; y <= 1; y++) for (int x = 0; x <= 1; x++) {
        ivec2 q = clamp(base + ivec2(x, y), ivec2(0), ivec2(lowSize) - 1);
        vec4 s = texelFetch(colortex8, q, 0);
        vec2 fullPx = (vec2(q) + 0.5) / lowSize * vec2(viewWidth, viewHeight);
        ScenePoint qp = scenePoint((vec2(ivec2(fullPx)) + 0.5) / vec2(viewWidth, viewHeight), texelFetch(depthtex0, ivec2(fullPx), 0).r, ivec2(fullPx), true);
        float qLin = qp.sky ? 1e6 : qp.dist;
        float wb = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y);
        float wd = 1.0 / (1.0 + abs(qLin - linD) / max(min(qLin, linD), 1.0) * 20.0);
        float w = wb * wd + 1e-4;
        sum += s * w; wsum += w;
        lo = min(lo, s); hi = max(hi, s);
    }
    vec4 current = sum / wsum;

    // Reproject along the ray to where the cloud actually is.
    vec3 viewPos = here.sky ? screenToView(texCoord, 1.0) : here.view;
    vec3 dir = normalize(viewToSceneDir(normalize(viewPos)));
    float cloudDist;
    {
        float mid = 0.5 * (fsCloud.z + min(fsCloud.w, fsCloud.z + 1500.0));
        float t = abs(dir.y) > 1e-3 ? (mid - cameraPosition.y) / dir.y : -1.0;
        cloudDist = t > 0.0 ? min(t, CLOUD_MAX_DISTANCE) : 2000.0;
        if (depth < 1.0) cloudDist = min(cloudDist, length(viewPos));
    }
    vec3 prev = reprojectScene(dir * cloudDist);
    bool valid = all(greaterThan(prev.xy, vec2(0.0))) && all(lessThan(prev.xy, vec2(1.0)));
    // Inside the cloud layer the ray origin changes every frame: trust history less.
    float inside = step(fsCloud.z - 400.0, cameraPosition.y) * step(cameraPosition.y, fsCloud.w);
    vec4 history = texture(colortex9, prev.xy);
    // Widen the clamp box slightly: the march is noisy by design.
    vec4 margin = (hi - lo) * 0.25 + vec4(0.002);
    history = clamp(history, lo - margin, hi + margin);
    float blend = valid && frameStateValid() && fsHeader.y > 4 ? mix(0.1, 0.35, inside) : 1.0;
    vec4 result = mix(history, current, blend);
    if (!isFiniteVec(result)) result = vec4(0.0, 0.0, 0.0, 1.0);
    outHistory = vec4(max(result.rgb, 0.0), saturate(result.a));
}
#endif

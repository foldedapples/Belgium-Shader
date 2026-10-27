// deferred compute (deferred.csh): half-resolution ambient occlusion and indirect sunlight.
//
// AO: horizon-based (in the spirit of GTAO, Jimenez et al. 2016): two screen-space slice
// directions per pixel, rotated by interleaved gradient noise each frame; TAA integrates the
// noise. Radius in world units, so AO does not change with distance.
//
// Indirect sun: reflective shadow maps (Dachsbacher & Stamminger 2005). The shadow atlas stores
// each caster's albedo (shadowcolor0) and normal (shadowcolor1); every lit texel is a small area
// light reflecting sunlight. A receiver gathers RSM_SAMPLES texels around its own shadow-space
// position from the coarse cascade. Result is per unit sun illuminance (lighting multiplies).

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/state.glsl"
#include "/lib/common/transform.glsl"
#include "/lib/common/gbuffer.glsl"
#include "/lib/lighting/shadow_proj.glsl"

layout(local_size_x = 8, local_size_y = 8) in;
const vec2 workGroupsRender = vec2(0.5, 0.5);

uniform sampler2D depthtex1;
uniform sampler2D colortex2;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;
layout(rgba16f) uniform writeonly image2D aoGiImg;

float horizonAO(vec2 uv, vec3 viewPos, vec3 viewN, float noise) {
    const float RADIUS = 1.4;              // blocks
    const int STEPS = 6;
    float ao = 0.0;
    vec3 v = normalize(-viewPos);
    float projScale = gbufferProjection[1][1] * 0.5 / max(-viewPos.z, 0.1);
    float radiusPx = RADIUS * projScale;   // in uv units (y)
    for (int s = 0; s < 2; s++) {
        float ang = (noise + float(s) * 0.5) * PI;
        vec2 dir = vec2(cos(ang), sin(ang));
        vec2 dirUv = dir * vec2(1.0 / aspectRatio, 1.0) * radiusPx;
        float h0 = -1.0, h1 = -1.0;
        for (int i = 1; i <= STEPS; i++) {
            float t = (float(i) - noise * 0.5) / float(STEPS);
            t *= t;
            for (int side = 0; side < 2; side++) {
                vec2 suv = uv + dirUv * t * (side == 0 ? 1.0 : -1.0);
                if (any(lessThan(suv, vec2(0.0))) || any(greaterThan(suv, vec2(1.0)))) continue;
                float d = texture(depthtex1, suv).r;
                vec3 sp = sceneToView(suv, d);
                vec3 delta = sp - viewPos;
                float len = length(delta);
                float c = dot(delta / max(len, 1e-4), v);
                float fall = saturate(1.0 - len / RADIUS);
                c = mix(-1.0, c, fall);
                if (side == 0) h0 = max(h0, c); else h1 = max(h1, c);
            }
        }
        // Integrate the visible arc between the two horizons, projected onto the normal plane.
        vec3 axis = normalize(cross(vec3(dir, 0.0), v));
        vec3 pn = viewN - axis * dot(viewN, axis);
        float pl = length(pn);
        float cn = saturate(dot(pn / max(pl, 1e-4), v));
        float nAng = sign(dot(cross(axis, v), pn)) * acos(cn);
        float a0 = nAng + max(-acos(h0) - nAng, -HALF_PI);
        float a1 = nAng + min(acos(h1) - nAng, HALF_PI);
        float vis = 0.25 * (-cos(2.0 * a0 - nAng) + cn + 2.0 * a0 * sin(nAng))
                  + 0.25 * (-cos(2.0 * a1 - nAng) + cn + 2.0 * a1 * sin(nAng));
        ao += pl * vis;
    }
    return saturate(ao * 0.5);
}

vec3 indirectSun(vec3 playerPos, vec3 n, float noise) {
    mat3 Ls = shadowLightRotation();
    vec3 lp = Ls * (playerPos + n * 0.5);
    const int K = 2;   // gather from cascade 2 (a 64-block window at default distance)
    float e = cascadeExtent(K);
    vec2 c = (lp.xy + state.cascadeCenter[K].xy) / e;
    if (maxOf(abs(c)) > 0.95) return vec3(0.0);
    vec2 baseUv = cascadeOrigin(K) + (c * 0.5 + 0.5) * 0.5;
    vec3 lightDir = shadowLightDirPlayer();
    const float GATHER_RADIUS = 7.0;   // blocks
    vec3 sum = vec3(0.0);
    for (int i = 0; i < RSM_SAMPLES; i++) {
        float r = sqrt((float(i) + noise) / float(RSM_SAMPLES));
        float a = float(i) * GOLDEN_ANGLE + noise * TAU;
        vec2 off = vec2(cos(a), sin(a)) * r * GATHER_RADIUS;
        vec2 suv = baseUv + off / (2.0 * e) * 0.5;
        vec2 o = cascadeOrigin(K);
        if (any(lessThan(suv, o)) || any(greaterThan(suv, o + 0.5))) continue;
        vec4 nrm = texture(shadowcolor1, suv);
        if (nrm.w < 0.5) continue;
        float d = texture(shadowtex1, suv).r;
        // Light-space position of the reflecting texel, relative to the camera.
        vec3 sp = vec3(lp.xy + off, -((d * 2.0 - 1.0) * SHADOW_Z_RANGE));
        vec3 delta = transpose(Ls) * (sp - lp);
        float dist2 = dot(delta, delta);
        vec3 dirTo = delta * inversesqrt(max(dist2, 1e-4));
        vec3 sn = octDecode(nrm.xy);
        float emit = saturate(dot(sn, lightDir)) * saturate(dot(sn, -dirTo));
        float recv = saturate(dot(n, dirTo));
        vec3 albedo = srgbToLinear(texture(shadowcolor0, suv).rgb);
        // Each sample stands for an area of pi R^2 / N blocks^2.
        sum += albedo * emit * recv / max(dist2, 1.0);
    }
    return sum * (PI * GATHER_RADIUS * GATHER_RADIUS / float(RSM_SAMPLES)) * INV_PI * INV_PI;
}

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(aoGiImg);
    if (any(greaterThanEqual(px, size))) return;
    vec2 uv = (vec2(px) + 0.5) / vec2(size);
    float depth = texture(depthtex1, uv).r;
    if (depth >= 1.0) { imageStore(aoGiImg, px, vec4(0, 0, 0, 1)); return; }
    vec3 viewPos = sceneToView(uv, depth);
    vec4 g2 = texture(colortex2, uv);
    vec3 n = octDecode(unpack2x8(g2.z));
    vec3 viewN = mat3(gbufferModelView) * n;
    float noise = interleavedGradient(vec2(px) + float(frameCounter % 64) * 5.588238);
    float ao = 1.0;
    #ifdef AMBIENT_OCCLUSION
    ao = horizonAO(uv, viewPos, viewN, noise);
    #endif
    vec3 gi = vec3(0.0);
    #if defined INDIRECT_SUN && !defined WORLD_NETHER
    gi = indirectSun(viewToPlayer(viewPos), n, noise);
    #endif
    imageStore(aoGiImg, px, vec4(gi, ao));
}

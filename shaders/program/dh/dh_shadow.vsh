// Distant Horizons shadow casters: drawn straight into the coarsest cascade (DH terrain lies
// beyond the finer ones). No geometry stage; triangles leaving the quadrant are discarded.
#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/state.glsl"
#include "/lib/lighting/shadow_proj.glsl"

out vec4 vColor;

void main() {
    vColor = gl_Color;
    vec3 playerPos = (shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    vec3 lp = shadowLightRotation() * playerPos;
    const int K = 3;
    vec2 c = (lp.xy + state.cascadeCenter[K].xy) / cascadeExtent(K);
    vec2 center = (cascadeOrigin(K) + 0.25) * 2.0 - 1.0;
    gl_Position = vec4(c * 0.5 + center, -lp.z / SHADOW_Z_RANGE, 1.0);
}

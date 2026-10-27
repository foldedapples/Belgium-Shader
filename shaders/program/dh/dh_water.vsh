#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/jitter.glsl"

out vec4 vColor;
out vec2 vLightmap;
out vec3 vNormal;
out vec3 vPlayerPos;
flat out int vMaterial;

void main() {
    vColor = gl_Color;
    vLightmap = (gl_TextureMatrix[1] * gl_MultiTexCoord2).xy;
    vNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vPlayerPos = (gbufferModelViewInverse * viewPos).xyz;
    vMaterial = dhMaterialId;
    gl_Position = applyJitter(gl_ProjectionMatrix * viewPos);
}

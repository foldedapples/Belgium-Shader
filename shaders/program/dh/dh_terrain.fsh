#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/gbuffer.glsl"
#include "/lib/material/ids.glsl"
#include "/lib/material/fallback.glsl"

in vec4 vColor;
in vec2 vLightmap;
in vec3 vNormal;
in vec3 vPlayerPos;
flat in int vMaterial;

/* RENDERTARGETS: 1,2,3 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outMaterial;

int materialFromDh(int m) {
    if (m == DH_BLOCK_LEAVES) return MAT_LEAVES;
    if (m == DH_BLOCK_STONE) return MAT_STONE;
    if (m == DH_BLOCK_WOOD) return MAT_WOOD;
    if (m == DH_BLOCK_METAL) return MAT_IRON;
    if (m == DH_BLOCK_DIRT) return MAT_DIRT;
    if (m == DH_BLOCK_GRASS) return MAT_GRASS_BLOCK;
    if (m == DH_BLOCK_LAVA) return MAT_LAVA;
    if (m == DH_BLOCK_DEEPSLATE) return MAT_DEEPSLATE;
    if (m == DH_BLOCK_SNOW) return MAT_SNOW;
    if (m == DH_BLOCK_SAND) return MAT_SAND;
    if (m == DH_BLOCK_TERRACOTTA) return MAT_TERRACOTTA;
    if (m == DH_BLOCK_NETHER_STONE) return MAT_NETHERRACK;
    if (m == DH_BLOCK_ILLUMINATED) return MAT_GLOWSTONE;
    return MAT_DEFAULT;
}

void main() {
    // DH draws before vanilla terrain, which then overwrites the G-buffer wherever it exists.
    // Inside most of the vanilla range DH geometry is skipped so it cannot show through gaps.
    if (length(vPlayerPos.xz) < far * 0.8) discard;

    vec3 n = normalize(vNormal);
    int id = materialFromDh(vMaterial);
    vec3 worldPos = vPlayerPos + cameraPosition;
    // Block-scale variation anchored to the world (stable, no shimmer when moving).
    vec3 cell = floor(worldPos - n * 0.5);
    float v = hash1(ivec2(int(cell.x) * 73 + int(cell.y) * 19, int(cell.z))) * 0.12 - 0.06;
    vec3 albedo = saturate(vColor.rgb * (1.0 + v));
    vec4 spec = fallbackSpecular(id, albedo, id == MAT_GLOWSTONE || id == MAT_LAVA ? 15.0 : 0.0);
    int flags = FLAG_LOD;
    if (isFoliage(id)) flags |= FLAG_PLANT | FLAG_NO_PUDDLE;
    outAlbedo = encodeGB1(albedo, 1.0);
    outNormal = encodeGB2(n, n, normalizeLightmap(vLightmap));
    outMaterial = encodeGB3(spec, id, flags, 1.0);
}

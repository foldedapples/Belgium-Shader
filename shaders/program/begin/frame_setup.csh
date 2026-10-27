// begin: once per frame, before the shadow pass. Computes the snapped cascade centres in double
// precision, the coloured-light volume origin and the accumulated cloud wind offset.

#include "/lib/settings.glsl"
#include "/lib/common/uniforms.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/state.glsl"
#include "/lib/common/wind.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/sky/celestial.glsl"
#include "/lib/lighting/shadow_proj.glsl"
#include "/lib/lighting/light_volume.glsl"

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

void main() {
    // Sign of the sky's rotation axis (see celestialAxis); kept from earlier frames when the sun is
    // too close to the horizon to tell.
    float axisSign = celestialAxisSignFromSun(sunDirection());
    if (axisSign == 0.0) axisSign = state.lightBasis[0].w != 0.0 ? sign(state.lightBasis[0].w) : 1.0;
    state.lightBasis[0].w = axisSign;

    // Shadow-casting light: sun by day, our orbital moon by night, the black hole in the End.
    #ifdef WORLD_END
    vec3 toLight = END_LIGHT_DIR;
    #else
    vec3 toLight = skyLights().lightDir;
    #endif
    mat3 L = lightBasisFor(toLight, celestialAxis());
    mat3 Lt = transpose(L);
    state.lightBasis[0] = vec4(Lt[0], axisSign);
    state.lightBasis[1] = vec4(Lt[1], 0.0);
    state.lightBasis[2] = vec4(Lt[2], 0.0);

    // The texel grid is anchored at a world block near the player rather than at the world origin.
    // Any change of L (the sun moving every frame, or float noise in sunPosition, which Iris gives
    // in view space and so changes when the head turns) shifts the grid relative to nearby
    // geometry by |dL| times the distance to the pivot. Pivoting at the world origin made that
    // distance thousands of blocks: shadow edges got a new sub-texel phase every frame (shimmer)
    // and twitched with head movement. With a pivot within SHADOW_ANCHOR_RANGE blocks the shift is
    // ~1e-3 block per frame; re-anchoring (a single sub-texel step) happens once per 32 blocks.
    ivec3 camBlockNow = cameraPositionInt + ivec3(floor(cameraPositionFract));
    ivec4 anchor = state.shadowAnchor;
    #ifdef WORLD_END
    // The End's light never moves, so nothing needs a nearby pivot: the grid stays anchored at the
    // world origin. Re-anchoring every SHADOW_ANCHOR_RANGE blocks shifted the texel phase, so every
    // shadow edge on the island jumped by up to a texel whenever the player crossed that distance.
    anchor = ivec4(0, 0, 0, 1);
    state.shadowAnchor = anchor;
    #else
    if (anchor.w == 0 || any(greaterThan(abs(camBlockNow - anchor.xyz), ivec3(SHADOW_ANCHOR_RANGE)))) {
        anchor = ivec4(camBlockNow, 1);
        state.shadowAnchor = anchor;
    }
    #endif

    // Camera position relative to the anchor in light space, in double precision.
    dmat3 Ld = dmat3(L);
    dvec3 cam = dvec3(cameraPositionInt - anchor.xyz) + dvec3(cameraPositionFract);
    dvec3 c = Ld * cam;
    for (int k = 0; k < 4; k++) {
        double t = double(cascadeTexel(k));
        // Offset from the camera to the texel-snapped cascade centre (cascade-space = ls + offset).
        dvec2 snapped = floor(c.xy / t) * t;
        vec2 offset = vec2(c.xy - snapped);
        state.cascadeCenter[k] = vec4(offset, float(t), 0.0);
    }

    ivec3 camBlock = cameraPositionInt + ivec3(floor(cameraPositionFract));
    vec4 prevOrigin = state.lightVolumeOrigin;
    state.lightVolumePrevOrigin = prevOrigin;
    state.lightVolumeOrigin = vec4(vec3(voxelOriginFor(camBlock)), 1.0);

    // Cloud motion integrates the wind so changes in wind direction never make clouds jump.
    float dt = clamp(frameTime, 0.0, 0.1);
    vec2 wind = windDirection();
    float speed = (6.0 + 14.0 * windStrength()) * CLOUD_SPEED;     // m/s at cloud level
    vec4 co = state.cloudOffset;
    co.xy += wind * speed * dt;
    co.zw += wind * speed * 2.2 * dt;
    // Keep the offsets bounded to preserve float precision. Every cloud noise repeats a whole
    // number of times in 131072 m (lib/clouds/clouds_common.glsl, CLOUD_WRAP), so the wrap is
    // invisible.
    co = mod(co + 65536.0, 131072.0) - 65536.0;
    state.cloudOffset = co;
    // Cloud formations (the weather map) drift a little slower than the cloud elements, so
    // clouds form and dissolve across a cluster instead of the pattern sliding rigidly.
    vec2 wo = state.weatherOffset.xy + wind * speed * 0.8 * dt;
    // Daily regime: each Minecraft day gets its own sky-cover bias (-0.18 .. +0.18), so some days
    // are mostly clear and others cloudier, on top of the regional weather systems. Eased over
    // ~90 s so the change at the day boundary is a gradual build-up or clearing, never a jump;
    // the first frame starts at the target (w = valid).
    float dayBias = 0.0;
    #ifdef WEATHER_CLOUDS
    uint h = uint(worldDay) * 0x9e3779b9u + 0x7f4a7c15u;
    h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15; h *= 0x846ca68bu; h ^= h >> 16;
    float r = float(h & 0xffffu) / 65535.0 * 2.0 - 1.0;
    dayBias = 0.18 * r * abs(r) * 0.5 + 0.09 * r;     // most days near average, a few clear or cloudy
    #endif
    float bias = state.weatherOffset.w != 0.0 ? mix(state.weatherOffset.z, dayBias, 1.0 - exp(-dt / 90.0)) : dayBias;
    state.weatherOffset = vec4(mod(wo + 65536.0, 131072.0) - 65536.0, bias, 1.0);
}

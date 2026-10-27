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

    // Camera position in light space, in double precision: L * (cameraInt + cameraFract).
    dmat3 Ld = dmat3(L);
    dvec3 cam = dvec3(cameraPositionInt) + dvec3(cameraPositionFract);
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
    // Keep the offsets bounded (noise repeats far beyond this) to preserve float precision.
    co = mod(co + 65536.0, 131072.0) - 65536.0;
    state.cloudOffset = co;
}

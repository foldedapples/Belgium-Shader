// begin_a.csh - sky-view LUT for the current camera altitude, sun and moon (see sky_view.glsl).
#include "/lib/core/common.glsl"
#include "/lib/core/frame_state.glsl"
#define ATMOSPHERE_LUTS
#include "/lib/atmosphere/atmosphere.glsl"
#include "/lib/atmosphere/sky_view.glsl"

#ifdef STAGE_COMPUTE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const ivec3 workGroups = ivec3(24, 27, 1);

layout(rgba16f) uniform writeonly image2D skyViewLut;

const int STEPS = 30;

vec3 integrateSky(float r, vec3 rd, vec3 lightDir, vec3 irradiance, float lightRadius) {
    vec3 ro = vec3(0.0, r, 0.0);
    float mu = rd.y;
    bool ground = rayHitsGround(r, mu);
    float len = ground ? distanceToGround(r, mu) : distanceToTop(r, mu);
    len = min(len, 800.0); // beyond this the contribution is negligible but costs precision

    float cosTheta = dot(rd, lightDir);
    float pr = rayleighPhase(cosTheta);
    float pm = miePhase(cosTheta, MIE_G);

    vec3 radiance = vec3(0.0);
    vec3 throughput = vec3(1.0);
    float tPrev = 0.0;
    for (int i = 0; i < STEPS; i++) {
        // Quadratic step distribution: dense near the camera where density is highest.
        float x = (float(i) + 0.5) / float(STEPS);
        float t = len * x * x;
        float xn = (float(i) + 1.0) / float(STEPS);
        float tNext = len * xn * xn;
        float dt = tNext - tPrev;
        tPrev = tNext;

        vec3 p = ro + rd * t;
        float pr2 = length(p);
        vec3 up = p / pr2;
        AtmosphereSample a = sampleAtmosphere(pr2 - ATM_GROUND);
        float muL = dot(up, lightDir);
        vec3 lightT = sunTransmittance(pr2, muL, lightRadius);
        vec3 ms = multiScatter(pr2, muL);

        vec3 single = (a.rayleigh * pr + a.mie * pm) * lightT;
        vec3 multi = (a.rayleigh + a.mie) * ms;
        vec3 stepT = exp(-a.extinction * dt);
        vec3 integ = (1.0 - stepT) / max(a.extinction, vec3(1e-7));
        radiance += throughput * (single + multi) * integ;
        throughput *= stepT;
    }
    return radiance * irradiance;
}

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (px.x >= int(SKY_VIEW_PANEL.x) || px.y >= int(SKY_VIEW_PANEL.y) * 2) return;
    int panel = px.y >= int(SKY_VIEW_PANEL.y) ? 1 : 0;
    ivec2 local = ivec2(px.x, px.y - panel * int(SKY_VIEW_PANEL.y));
    vec2 uv = (vec2(local) + 0.5) / SKY_VIEW_PANEL;

    float az, el;
    skyViewUvToParams(uv, az, el);
    vec3 rd = skyViewLocalDir(az, el);

    vec3 lightWorld = panel == 0 ? fsSunDir.xyz : fsMoonDir.xyz;
    vec3 irradiance = panel == 0 ? fsSunIrradiance.rgb : fsMoonIrradiance.rgb;
    float lightRadius = panel == 0 ? fsCelestialAxis.w : fsMoonParams.x;
    // Local frame: light direction keeps its elevation, azimuth 0.
    float le = asin(clamp(lightWorld.y, -1.0, 1.0));
    vec3 lightLocal = vec3(cos(le), sin(le), 0.0);

    float r = ATM_GROUND + cameraAltitudeKm(cameraPosition.y);
    vec3 radiance = frameStateValid() ? integrateSky(r, rd, lightLocal, irradiance, lightRadius) : vec3(0.0);
    imageStore(skyViewLut, px, vec4(sanitizeRadiance(radiance), 1.0));
}
#endif

#ifndef WATER_RECORD_GLSL
#define WATER_RECORD_GLSL
// colortex6 water record: rg = octahedral surface normal, b = packed lightmap, a = coverage.
// b packs sky and block light quantised to 32 levels each (finer than vanilla's 16, so the
// interpolated lightmap does not band) as k/1024, exact in fp16, and
// its sign asks composite to add analytic waves (LOD water whose producer could not compute
// them, i.e. Voxy).

float packWaterLight(vec2 lightmap, bool needsWaves) {
    vec2 levels = floor(clamp(lightmap, 0.0, 1.0) * 31.0 + 0.5);
    float v = (levels.y * 32.0 + levels.x + 1.0) / 1024.0;
    return needsWaves ? -v : v;
}

void unpackWaterLight(float b, out vec2 lightmap, out bool needsWaves) {
    needsWaves = b < 0.0;
    float v = floor(abs(b) * 1024.0 + 0.5) - 1.0;
    float sky = floor(v / 32.0);
    float block = v - sky * 32.0;
    lightmap = clamp(vec2(block, sky) / 31.0, 0.0, 1.0);
}

#endif

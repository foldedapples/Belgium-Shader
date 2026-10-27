#ifndef MERIDIAN_BLOCKLIGHT
#define MERIDIAN_BLOCKLIGHT

// Block light: brightness from vanilla's own block light (which already respects every wall, so
// nothing can leak), colour from the voxel flood-fill volume when it has data at this point.
// Requires emitters.glsl, ambient.glsl; with COLORED_LIGHTING also light_volume.glsl and state.

#ifdef COLORED_LIGHTING
uniform sampler3D lightSamplerA;   // newest light volume (shadowcomp writes A last)

vec4 fetchLight(ivec3 block) {
    return texelFetch(lightSamplerA, voxelIndex(block), 0);
}

// Trilinear filtering by hand (the volume is toroidal, the image clamps). Takes a camera-relative
// position: the volume is voxelised in unshifted integer world blocks (cameraPositionInt), while
// cameraPosition is shifted by Iris in 30000-block steps, so world = cameraPosition + p put the
// lookup in the wrong place beyond +-30000.
vec4 sampleLightVolume(vec3 playerPos) {
    vec3 p = cameraPositionFract + playerPos - 0.5;
    ivec3 fl = ivec3(floor(p));
    ivec3 b = cameraPositionInt + fl;
    vec3 f = p - vec3(fl);
    vec4 c000 = fetchLight(b), c100 = fetchLight(b + ivec3(1, 0, 0));
    vec4 c010 = fetchLight(b + ivec3(0, 1, 0)), c110 = fetchLight(b + ivec3(1, 1, 0));
    vec4 c001 = fetchLight(b + ivec3(0, 0, 1)), c101 = fetchLight(b + ivec3(1, 0, 1));
    vec4 c011 = fetchLight(b + ivec3(0, 1, 1)), c111 = fetchLight(b + ivec3(1, 1, 1));
    // Weight colours by their light level so dark (solid) neighbours do not grey the colour.
    vec4 acc = vec4(0.0);
    float wsum = 0.0;
    vec4 cs[8] = vec4[8](c000, c100, c010, c110, c001, c101, c011, c111);
    for (int i = 0; i < 8; i++) {
        vec3 o = vec3(i & 1, (i >> 1) & 1, (i >> 2) & 1);
        vec3 w3 = mix(1.0 - f, f, o);
        float w = w3.x * w3.y * w3.z;
        acc += vec4(cs[i].rgb * cs[i].a, cs[i].a) * w;
        wsum += w;
    }
    return acc / max(wsum, 1e-5);
}
#endif

// Returns block-light irradiance / pi (multiply by albedo for diffuse).
vec3 blockLightAt(vec3 playerPos, vec3 normal, float blockLight) {
    vec3 defaultColor = blackbody(float(BLOCKLIGHT_TEMPERATURE));
    vec3 color = defaultColor;
    #ifdef COLORED_LIGHTING
    vec3 rel = playerPos + normal * 0.5;
    ivec3 block = cameraPositionInt + ivec3(floor(cameraPositionFract + rel));
    ivec3 origin = ivec3(state.lightVolumeOrigin.xyz);
    if (insideVolume(block, origin) && insideVolume(block + 1, origin)) {
        vec4 v = sampleLightVolume(rel);
        if (v.a > 1e-3) {
            vec3 c = v.rgb / max(v.a, 1e-4);
            c /= max(maxOf(c), 1e-4);
            // Trust the volume where it is lit; fall back to the warm default where it is dark
            // but vanilla light reaches (light through slabs, fences, doors).
            float trust = saturate(v.a * 15.0 / max(blockLight * 15.0, 1.0));
            color = mix(defaultColor, c, trust) * CL_BRIGHTNESS;
        }
    }
    #endif
    // Level 15 next to the source: irradiance / pi = 1.6 (with albedo 0.7, about half the radiance
    // of sunlit ground). It was 4.0, brighter than direct sun and 12x the End's disk light, so an
    // active End portal (level 15) or a lava sea washed everything around it to white.
    return color * blockLightFalloff(blockLight) * (1.6 * BLOCKLIGHT_STRENGTH);
}

// Light carried by the player (held emitters): a point light at the eye using vanilla's linear
// range (level - distance), shaped like block light, coloured by the held item.
vec3 handLight(vec3 playerPos, vec3 normal) {
    #ifdef HAND_LIGHT
    float level = float(max(heldBlockLightValue, heldBlockLightValue2));
    if (level <= 0.0) return vec3(0.0);
    int id = heldBlockLightValue >= heldBlockLightValue2 ? heldItemId : heldItemId2;
    vec3 toLight = -playerPos + vec3(0.0, -0.1, 0.0);
    float dist = length(toLight);
    float l = saturate((level - dist) / 15.0);
    float lambert = saturate(dot(normal, toLight / max(dist, 1e-3)) * 0.8 + 0.2);
    vec3 color = id > 0 ? emitterColor(id) : blackbody(float(BLOCKLIGHT_TEMPERATURE));
    return color * blockLightFalloff(l) * lambert * (4.0 * BLOCKLIGHT_STRENGTH);
    #else
    return vec3(0.0);
    #endif
}

#endif

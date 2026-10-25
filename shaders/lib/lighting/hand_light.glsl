#ifndef LIGHTING_HAND_LIGHT_GLSL
#define LIGHTING_HAND_LIGHT_GLSL
#include "/lib/lighting/block_light_falloff.glsl"
#include "/lib/core/common.glsl"
#include "/lib/material/material_ids.glsl"
#include "/lib/post/color_profile.glsl"

// Coloured held light. Iris reports the light level of the items in both hands
// (heldBlockLightValue/2) and their ids from item.properties (heldItemId/2); item ids reuse the
// block classes (10000 + class), so a held soul torch is cyan and a held torch amber. The light
// sits at the player's hand and falls off by one level per block like vanilla light, so it
// reaches exactly as far as a placed block of the same level would.
// Iris' own monochrome dynamic hand light is disabled (shaders.properties) to avoid doubling.

uniform int heldItemId;
uniform int heldItemId2;

// Irradiance-like intensity of a vanilla light level (0..15), shared with block light.
float lightLevelIntensity(float level) { return blockLightFalloff(level) * 2.2; }

vec3 handLightColor(int itemId) {
    int m = materialFromBlockId(itemId);
    return m == MAT_NONE ? blackbody(float(BLOCKLIGHT_TEMPERATURE)) : emitterColor(m);
}

// Wrapped cosine used for the hand light's diffuse response.
float handLightFacing(vec3 n, vec3 toLight) { return saturate(dot(n, toLight) * 0.7 + 0.3); }

// Returns irradiance at `scenePos` from the held light and writes its direction (toward the
// light) for specular shading.
vec3 handLightIrradiance(vec3 scenePos, vec3 n, out vec3 toLight) {
    toLight = vec3(0.0, 1.0, 0.0);
    #ifdef HAND_LIGHT
        int l1 = heldBlockLightValue, l2 = heldBlockLightValue2;
        int level = max(l1, l2);
        if (level <= 0) return vec3(0.0);
        int id = l1 >= l2 ? heldItemId : heldItemId2;
        // The hand: just below and in front of the player's eye.
        vec3 eye = -relativeEyePosition;
        vec3 lightPos = eye + vec3(0.0, -0.35, 0.0) + playerLookVector * 0.4;
        vec3 d = lightPos - scenePos;
        float dist = length(d);
        toLight = d / max(dist, 1e-3);
        float effective = float(level) - dist;
        if (effective <= 0.0) return vec3(0.0);
        float facing = handLightFacing(n, toLight);
        return handLightColor(id) * lightLevelIntensity(effective) * facing * BLOCKLIGHT_INTENSITY * CP_BLOCK_LIGHT;
    #else
        return vec3(0.0);
    #endif
}

#endif

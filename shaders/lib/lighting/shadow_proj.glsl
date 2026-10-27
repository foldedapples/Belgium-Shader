#ifndef MERIDIAN_SHADOW_PROJ
#define MERIDIAN_SHADOW_PROJ

// Stable cascaded shadow projection.
//
// The shadow map is a 2x2 atlas of four orthographic cascades. All cascades share the light
// rotation L (from shadowModelView, or a fixed direction in the End). For cascade k the region
// covered is a square of half-size CASCADE_EXTENT[k] blocks whose centre is the camera's
// light-space position snapped to whole texels of that cascade. Static geometry therefore maps
// to the same texels while the camera moves or turns; only real light motion (the sun) changes
// the projection. Iris's own snapping is disabled (shadowIntervalSize = 0).
//
// The snapped offsets are computed once per frame in double precision by begin.csh and stored
// in the state SSBO (cascadeCenter[k].xy), so every pass uses identical values.
//
// Snapping is done relative to a world anchor near the player (state.shadowAnchor), not the
// world origin, so that rotation of the light only moves the grid by |dL| * (distance to the
// anchor) instead of |dL| * (distance to 0,0,0).

const float shadowIntervalSize = 0.0;
// Light rotation pivots about a world block within this many blocks of the camera (begin.csh).
const int SHADOW_ANCHOR_RANGE = 32;
const bool  shadowHardwareFiltering = true;
const float SHADOW_Z_RANGE = 384.0;
// Receivers use cascade k inside CASCADE_SELECT of its square; the geometry stage leaves a
// triangle out of cascade k only when it lies inside CASCADE_CASTER_SKIP of cascade k-1.
const float CASCADE_SELECT = 0.9;
const float CASCADE_CASTER_SKIP = 0.5;

// Largest filter reach (blocks) a receiver in cascade k may use without leaving the band where
// cascade k still has every caster.
float cascadeFilterReach(int k) {
    return k == 0 ? 1e4 : (CASCADE_SELECT - CASCADE_CASTER_SKIP - 0.02) * shadowDistance / (k == 1 ? 16.0 : k == 2 ? 6.0 : 2.5);
}   // blocks in front of / behind the camera along the light
// With shadow.culling = reversed, Iris renders every chunk within this distance into the shadow
// pass regardless of the light frustum, which the coloured-light voxelisation needs.
const float voxelDistance = 128.0;

float cascadeExtent(int k) {
    // Fractions of shadowDistance: 1/16, 1/6, 1/2.5, 1 (e.g. 10, 27, 64, 160 blocks).
    return k == 0 ? shadowDistance / 16.0 : k == 1 ? shadowDistance / 6.0 : k == 2 ? shadowDistance / 2.5 : shadowDistance;
}

float cascadeResolution() { return float(shadowMapResolution) * 0.5; }
float cascadeTexel(int k) { return 2.0 * cascadeExtent(k) / cascadeResolution(); }

// Atlas quadrant origin in [0,1] texture space.
vec2 cascadeOrigin(int k) { return vec2(float(k & 1), float(k >> 1)) * 0.5; }

// Direction towards the black hole that lights the End (fixed, so End shadows never move).
const vec3 END_LIGHT_DIR = vec3(0.4472136, 0.4472136, -0.7745967);

// Light-space basis from a light direction: z towards the light, x along the sky's rotation
// axis cross z (well defined because the sun and moon move on circles around that axis).
mat3 lightBasisFor(vec3 toLight, vec3 axis) {
    vec3 z = normalize(toLight);
    vec3 x = cross(axis, z);
    x = dot(x, x) > 1e-6 ? normalize(x) : normalize(cross(vec3(0.0, 1.0, 0.0), z + vec3(1e-3, 0.0, 0.0)));
    vec3 y = cross(z, x);
    return transpose(mat3(x, y, z));
}

#ifdef MERIDIAN_STATE
// Rotation from player space into light space (rows = light-space axes), set by begin.csh.
mat3 shadowLightRotation() {
    return transpose(mat3(state.lightBasis[0].xyz, state.lightBasis[1].xyz, state.lightBasis[2].xyz));
}
// Player-space direction towards the shadow-casting light (sun, moon or the End's black hole).
vec3 shadowLightDirPlayer() { return state.lightBasis[2].xyz; }
#endif

#endif

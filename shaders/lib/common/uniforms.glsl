#ifndef MERIDIAN_UNIFORMS
#define MERIDIAN_UNIFORMS

// Every Iris uniform the pack reads. Unused declarations are removed by the GLSL compiler.

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

uniform vec3  cameraPosition;
uniform ivec3 cameraPositionInt;
uniform vec3  cameraPositionFract;
uniform vec3  previousCameraPosition;
uniform ivec3 previousCameraPositionInt;
uniform vec3  previousCameraPositionFract;
uniform vec3  eyePosition;
uniform vec3  relativeEyePosition;
uniform vec3  playerLookVector;
uniform float eyeAltitude;
uniform ivec2 eyeBrightnessSmooth;
uniform int   isEyeInWater;
uniform bool  firstPersonCamera;

uniform vec3  relativeVehiclePosition;
uniform vec3  vehicleLookVector;
uniform int   vehicleId;
uniform bool  vehicleInWater;
uniform bool  isRiding;
uniform bool  inSwimmingAnimation;
uniform bool  feetInWater;
uniform bool  is_on_ground;
uniform bool  is_sneaking;
uniform bool  is_sprinting;

uniform vec3  sunPosition;
uniform vec3  moonPosition;
uniform vec3  shadowLightPosition;
uniform vec3  upPosition;
uniform float sunAngle;
uniform float shadowAngle;
uniform int   moonPhase;
uniform int   worldTime;
uniform int   worldDay;
uniform float rainStrength;
uniform float wetness;
uniform float thunderStrength;
uniform vec4  lightningBoltPosition;
uniform vec3  endFlashPosition;
uniform float endFlashIntensity;
uniform int   biome_category;
uniform int   biome_precipitation;
uniform float temperature;
uniform float rainfall;
uniform bool  hasCeiling;
uniform bool  hasSkylight;
uniform int   heightLimit;
uniform int   bedrockLevel;

uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform int   frameCounter;
uniform float frameTime;
uniform float frameTimeCounter;
uniform float alphaTestRef;
uniform vec4  entityColor;
uniform int   entityId;
uniform int   blockEntityId;
uniform int   renderStage;
uniform ivec2 atlasSize;
uniform int   heldItemId;
uniform int   heldItemId2;
uniform int   heldBlockLightValue;
uniform int   heldBlockLightValue2;
uniform bool  isRightHanded;
uniform float blindness;
uniform float darknessFactor;
uniform float darknessLightFactor;
uniform float nightVision;
uniform float screenBrightness;
uniform vec3  fogColor;
uniform vec3  skyColor;

#ifdef DISTANT_HORIZONS
uniform float dhNearPlane;
uniform float dhFarPlane;
uniform int   dhRenderDistance;
uniform mat4  dhProjection;
uniform mat4  dhProjectionInverse;
uniform mat4  dhPreviousProjection;
#endif

#ifdef VOXY
uniform int  vxRenderDistance;
uniform mat4 vxProj;
uniform mat4 vxProjInv;
uniform mat4 vxProjPrev;
uniform mat4 vxModelView;
uniform mat4 vxModelViewInv;
#endif

// Custom uniforms from shaders.properties.
uniform float frameTimeSmooth;   // frame time with a short half-life, for adaptation rates
uniform float rainSmooth;        // rainStrength with a slower fade
uniform float thunderSmooth;
uniform float eyeSkylightSmooth; // 0..1 sky light at the eye, smoothed
uniform float caveFactor;        // 1 deep underground, 0 at the surface
uniform float biomeWet;          // 0..1: camera biome rains (not snow, not dry)
uniform float biomeSnowy;        // 0..1: camera biome snows
uniform float biomeOcean;        // 0..1 smoothed: camera is in an ocean biome
uniform float biomeRiver;        // 0..1 smoothed: camera is in a river biome
uniform float biomeSwamp;        // 0..1 smoothed

// Iris 1.10.8 computes sunPosition / moonPosition / shadowLightPosition as the POINT (0, 100, 0, 1)
// transformed by gbufferModelView, so they contain the view matrix's translation (view bobbing,
// hurt shake). Rotating them back with mat3(gbufferModelViewInverse) alone leaves that translation
// in and tilts the light by ~bob/100 radians with every step: distant shadows wobble with the
// player's head. Subtracting the translation column first gives the exact direction.
vec3 celestialDirection(vec3 viewSpacePosition) {
    return normalize(mat3(gbufferModelViewInverse) * (viewSpacePosition - gbufferModelView[3].xyz));
}

vec2 screenSize() { return vec2(viewWidth, viewHeight); }
vec2 texelSize()  { return 1.0 / vec2(viewWidth, viewHeight); }

#endif

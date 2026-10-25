#ifndef CORE_UNIFORMS_GLSL
#define CORE_UNIFORMS_GLSL
// Non-sampler uniforms provided by Iris (or defined in shaders.properties). Samplers are
// declared by each program that reads them, so a pass never accidentally appears to read a
// target it writes.

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;

uniform vec3  cameraPosition;
uniform vec3  previousCameraPosition;
// Split camera position (exact integer block + fraction) exists from Iris 1.7. Iris 1.6.x
// (Minecraft 1.20.2) does not provide it: derive it from the float position, which loses
// precision far from the world origin (documented in COMPATIBILITY.md).
#if IRIS_VERSION >= 10700
    uniform ivec3 cameraPositionInt;
    uniform vec3  cameraPositionFract;
    uniform ivec3 previousCameraPositionInt;
    uniform vec3  previousCameraPositionFract;
#else
    #define cameraPositionInt ivec3(floor(cameraPosition))
    #define cameraPositionFract (cameraPosition - floor(cameraPosition))
    #define previousCameraPositionInt ivec3(floor(previousCameraPosition))
    #define previousCameraPositionFract (previousCameraPosition - floor(previousCameraPosition))
#endif
uniform vec3  relativeEyePosition;
uniform vec3  eyePosition;
uniform vec3  playerLookVector;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform vec3 upPosition;
uniform float sunAngle;

uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float near;
uniform float far;

uniform int   frameCounter;
uniform float frameTime;
uniform float frameTimeCounter;
uniform int   worldTime;
uniform int   worldDay;
uniform int   moonPhase;

uniform float rainStrength;
uniform float wetness;
uniform float thunderStrength;
uniform vec4  lightningBoltPosition;

uniform int   isEyeInWater;
uniform float nightVision;
uniform float blindness;
uniform float darknessFactor;
uniform float darknessLightFactor;
uniform float screenBrightness;
uniform float eyeAltitude;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform int   heldBlockLightValue;
uniform int   heldBlockLightValue2;
uniform bool  firstPersonCamera;

uniform vec3 fogColor;
uniform vec3 skyColor;
uniform float fogStart;
uniform float fogEnd;

uniform vec4 entityColor;
uniform int  entityId;
uniform int  blockEntityId;
uniform int  renderStage;
uniform int  seaLevel;

// Iris-exclusive (Iris >= 1.10.4); zero on older versions.
uniform bool  feetInWater;
uniform bool  inSwimmingAnimation;
uniform bool  isRiding;
uniform bool  vehicleInWater;
uniform int   vehicleId;
uniform vec3  vehicleLookVector;
uniform vec3  relativeVehiclePosition;

// Custom uniforms defined in shaders.properties.
uniform float biomeOceanSmooth;
uniform float biomeRiverSmooth;
uniform float biomePrecipSmooth;
uniform float biomeSnowSmooth;
uniform float caveFactorSmooth;
uniform vec2  viewSize;
uniform vec2  texelSize;

#endif

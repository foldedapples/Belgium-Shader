// god rays but UNDERWATER. the fancy light beams you see when you swim. very pretty, very slow
#ifndef UNDERWATER_SHAFTS_GLSL
#define UNDERWATER_SHAFTS_GLSL

// only march 40 blocks out, past that we fake it with math because I'm not raymarching the whole ocean
#define UW_SHAFT_RANGE 40.0

// the function. returns how much glowy light the water scatters toward your eyeballs
vec3 underwaterSunShafts(vec3 viewPos, float jitter) {
  float rayLength = length(viewPos);
  if (rayLength < 0.01) return vec3(0.0);
  vec3 viewDirection = viewPos / rayLength;
  vec3 worldDirection = mat3(gbufferModelViewInverse) * viewDirection;

  // how fast water eats light. clamp to 1e-6 so we don't divide by zero later and turn the screen into NaN soup
  vec3 ext = max(uwExtinction(), 1e-6);
  vec3 scattering = uwScattering() * UNDERWATER_FOG;
  float camDepth = uwCameraDepth();
  // the sunlight bends when it enters the water (snell's law again, my old friend)
  vec3 waterLight = waterRefractedLightDir(worldLightDir);
  float cosL = waterLight.y;

  // how much sun actually makes it into the water. if it's night this is basically nothing
  vec3 surfaceLight = weatherSunlightColor * sunVisibilitySmooth *
    waterSunTransmission(worldLightDir.y);
  // clouds block the sun too. obviously. took me a while to remember that
  #if defined CLOUDS && defined CLOUD_SHADOWS
  surfaceLight *= getCloudShadow(vec3(0.0));
  #endif
  if (maxVec3(surfaceLight) <= 0.0 || worldLightDir.y <= 0.0) return vec3(0.0);

  // henyey-greenstein with 0.65, which means light mostly scatters forward. no idea who those two are but they're carrying this file
  float phase = henyeyGreenstein(0.65, dot(worldDirection, waterLight));
  // proceduralCaustics multiplies back by max(lightDir.y, 0.2) so we undo it here. this bug took me 4 hours, I wanna cry
  float causticPathScale = rcp(max(worldLightDir.y, 0.2));

  float marchLength = min(rayLength, UW_SHAFT_RANGE);
  float stepLength = marchLength / float(UW_SHAFT_SAMPLES);
  vec3 result = vec3(0.0);

  // the actual raymarch. step along the view ray and add up light at each step. classic
  for (int i = 0; i < UW_SHAFT_SAMPLES; i++) {
    // jitter so the steps don't make ugly stripes. noise fixes everything
    float t = (float(i) + jitter) * stepLength;
    vec3 feetPos = worldDirection * t;
    float depth = max(camDepth - feetPos.y, 0.0);

    float visibility = 1.0;
    // is this spot in shadow? check the shadow map. this is the expensive part
    #ifdef SHADOWS
    vec3 shadowScreen = getShadowScreenPos(getShadowClipPos(feetPos));
    if (clamp01(shadowScreen) == shadowScreen) {
      visibility = texture(shadowtex1HW, shadowScreen);
    }
    #endif

    float focus = 1.0;
    // caustics in the light beams!!! mix 0.6 so it's not TOO much. I wanted 1.0 but it made people dizzy
    #if defined CAUSTICS && CAUSTICS_MODE == 2
    focus = mix(1.0, proceduralCaustics(feetPos + cameraPosition, worldLightDir, depth * causticPathScale, t), 0.6);
    #endif

    // beer's law. light dies exponentially in water. the beer part makes me feel like I understand it, I don't
    vec3 lightHere = surfaceLight * exp(-ext * depth / cosL);
    vec3 toCamera = exp(-ext * t);
    result += lightHere * visibility * focus * toCamera;
  }
  // multiply by step length because it's an integral or whatever. riemann sum. I remember that word
  result *= scattering * phase * stepLength;

  // past 40 blocks we use the closed-form formula instead of marching. someone on discord gave me this and I've never questioned it
  if (rayLength > marchLength) {
    vec3 lightFar = surfaceLight * exp(-ext * camDepth / cosL);
    result += lightFar * phase * (scattering / ext) *
      (exp(-ext * marchLength) - exp(-ext * rayLength));
  }
  return result * UW_SHAFT_STRENGTH * WATER_INSCATTER_GAIN;
}

#endif // UNDERWATER_SHAFTS_GLSL

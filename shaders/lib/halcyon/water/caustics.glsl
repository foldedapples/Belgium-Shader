// caustics!!! the wobbly light squiggles on the bottom of the pool. took me a WEEK. do not ask me how they work
#ifndef CAUSTICS_GLSL
#define CAUSTICS_GLSL

#include "/lib/water/waveNormals.glsl"

// how hard the light gets focused. 3.5 because 3 looked boring and 4 looked like the ocean floor was on fire
#define CAUSTICS_FOCUS 3.5

// 7 waves. 6 looked fake and 8 made my gpu sound like a jet engine. 7 it is
const int CAUSTIC_WAVES = 7;
// wavelengths I typed in by vibes, they all go down so it looks "natural" or whatever
const float causticWavelength[CAUSTIC_WAVES] =
  float[CAUSTIC_WAVES](3.1, 2.3, 1.9, 1.45, 1.2, 0.95, 0.8);
const float causticAngle[CAUSTIC_WAVES] =
  float[CAUSTIC_WAVES](0.0, 2.15, -2.05, 1.05, -1.0, 3.0, 0.5);
// steepness numbers. if you make these bigger the floor turns into a disco, ask me how I know
const float causticSteepness[CAUSTIC_WAVES] =
  float[CAUSTIC_WAVES](0.09, 0.08, 0.075, 0.065, 0.06, 0.05, 0.045);

// "hessian" is a fancy math word for the second derivative of the waves. I copied it from a paper and nodded a lot
vec3 causticHessian(vec2 xz, float openness) {
  // wind blows this way. 0.8 0.6 is a unit vector, I checked on a calculator like a caveman
  const vec2 windDir = vec2(0.8, 0.6);
  float t = waveTime();
  vec3 H = vec3(0.0);
  for (int i = 0; i < CAUSTIC_WAVES; i++) {
    float L = causticWavelength[i] * WAVE_SCALE;
    // 2 pi over wavelength, the one physics thing I actually remember from school
    float k = 2.0 * PI / L;
    // 9.81 is gravity. yes, actual earth gravity, in a block game. we are being REALISTIC here
    float omega = sqrt(9.81 * k);
    vec2 D = rotate(windDir, causticAngle[i]);
    float A = causticSteepness[i] / k;
    // 2.399 is the golden angle or some shit, a reddit guy said it stops the waves lining up and it fucking worked
    float theta = k * dot(D, xz) - omega * t + float(i) * 2.399;
    // negative sine because the curvature is upside down from the height. or something. it works, leave it
    float c = -A * k * k * sin(theta);
    H += c * vec3(D.x * D.x, D.x * D.y, D.y * D.y);
  }
  // swells = the big slow lazy ocean waves. same loop copy-pasted again because I'm not writing a function for this
  #ifdef WATER_SWELLS
  for (int i = 0; i < SWELL_COUNT; i++) {
    float L = swellWavelength[i] * WAVE_SCALE;
    float k = 2.0 * PI / L;
    float omega = sqrt(9.81 * k);
    vec2 D = rotate(windDir, swellAngle[i]);
    // this line is a monster. mix(0.12, 1.0) makes swells weaker in shallow areas, I think. I wrote it at 3am
    float A = swellSteepness[i] * WAVE_SWELL * waterSwellMul() * mix(0.12, 1.0, openness) / k;
    A *= swellGroup(i, k, dot(D, xz), omega, t);
    // 1.7 instead of 2.399 because using the same magic number twice felt like cheating
    float theta = k * dot(D, xz) - omega * t + float(i) * 1.7;
    float c = -A * k * k * sin(theta);
    H += c * vec3(D.x * D.x, D.x * D.y, D.y * D.y);
  }
  #endif
  // divide by 0.3 because the default depth is 0.3. normalizing! look at me go
  return H * (WAVE_DEPTH / 0.3);
}

// the actual caustics function. returns a brightness multiplier, 1.0 means "nothing happens, go home"
float proceduralCaustics(
  vec3 worldPos,
  vec3 lightDir,
  float lightPathInWater,
  float camDist
) {
  // if the light barely went through water there's no caustics, early bail, free fps baby
  if (lightPathInWater <= 0.01) return 1.0;

  // clamp to 0.2 so the sun at the horizon doesn't divide by like zero and nuke everything
  float cosL = max(lightDir.y, 0.2);
  float d = lightPathInWater * cosL;
  // snell's law!!! 1.33 is water's refractive index. I googled it. this is the most science I've ever done
  float cosW = sqrt(1.0 - (1.0 - pow2(clamp01(lightDir.y))) / (1.33 * 1.33));
  vec2 surfaceXZ = worldPos.xz + lightDir.xz / (1.33 * cosW) * d;

  // k is how much the light bends. 1 - 1/1.33. don't ask me why it's this and not the other way around
  const float k = 1.0 - 1.0 / 1.33;
  float openness = smoothstep(0.3, 10.0, d);
  vec3 H = causticHessian(surfaceXZ, openness);

  // cap depth at 8 or the caustics get way too intense in deep water and look like static
  float kd = k * min(d, 8.0) * CAUSTICS_FOCUS;
  // jacobian matrix. it measures how much the light rays squish together. squish = bright. that's literally all I know
  float j00 = 1.0 - kd * H.x;
  float j01 = -kd * H.y;
  float j11 = 1.0 - kd * H.z;
  // determinant. small det = rays piling up = SUPER bright. I learned this from a youtube video at 2x speed
  float det = abs(j00 * j11 - j01 * j01);

  // 0.08 floor so we don't divide by zero and blind the whole server
  float raw = 1.0 / max(det, 0.08);
  // soft clamp so bright spots don't go to infinity. this took like 40 tries to stop looking like a nuclear blast
  float over = max(raw - 3.0, 0.0);
  float intensity = min(raw, 3.0) + over / (1.0 + over / 3.0);

  // fade caustics out in deep water and far from the camera, because nobody's looking that hard anyway
  float strength =
    (1.0 - smoothstep(6.0, 16.0, d)) * (1.0 - smoothstep(32.0, 96.0, camDist));
  // rain makes the water surface messy so caustics go away. I think that's realistic. probably
  strength *= CAUSTICS_STRENGTH * (1.0 - 0.7 * wetness);
  return mix(1.0, intensity * 0.8, clamp01(strength));
}

#endif // CAUSTICS_GLSL (if you're reading this, I'm sorry)

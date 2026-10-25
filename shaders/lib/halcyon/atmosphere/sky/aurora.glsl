#ifndef AURORA_GLSL
#define AURORA_GLSL

// perlin noise but with the contrast turned up to 4 so it's spicy. divide by 16 because the texture tiles and I got tired of seeing it repeat
float auroraNoise(vec2 p) {
  float n = texture(perlinNoiseTex, fract(p / 16.0)).r;
  return clamp01((n - 0.5) * 4.0 + 0.5);
}

// random number generator. these huge numbers are from some hash function on the internet (PCG I think??)
// I have no idea wtf this bit shifting does but if I change ANY digit every night has an aurora. DO NOT FUCKING TOUCH
float auroraHash(uint day, uint stream) {
  uint v = day * 747796405u + stream * 2891336453u + 12345u; // 12345u is the only number here I came up with myself and I'm proud of it
  v = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
  v = (v >> 22u) ^ v;
  return float(v >> 8u) / 16777216.0; // 16777216 = 2^24. turns the uint into 0..1. took me 40 minutes and a calculator
}

// decides IF there's an aurora tonight and how strong. basically a slot machine that runs once per minecraft day
float auroraActivity() {
  #ifndef AURORA
  return 0.0;
  #else
  // the frequency setting. chance per night. 1.0 = every night = you're a filthy cheater and I respect it
  #if AURORA_FREQUENCY == 0
  const float chance = 0.05;
  #elif AURORA_FREQUENCY == 1
  const float chance = 0.08;
  #elif AURORA_FREQUENCY == 2
  const float chance = 0.15;
  #elif AURORA_FREQUENCY == 3
  const float chance = 0.3;
  #else
  const float chance = 1.0;
  #endif

  uint day = uint(worldDay);
  float roll = auroraHash(day, 0u);
  if (roll > chance) return 0.0; // rolled a nat 1, no lights for you

  // more dice rolls with different "streams" so they aren't all the same number. I figured this out by accident
  float strength = auroraHash(day, 1u);
  float startRoll = auroraHash(day, 2u);
  float lengthRoll = auroraHash(day, 3u);

  // 12500 is roughly sunset in ticks, +24000 so mod doesn't go negative and ruin my whole night
  float t = mod(float(worldTime) - 12500.0 + 24000.0, 24000.0);
  float eventStart = mix(500.0, 5000.0, startRoll);
  float eventLength = mix(2500.0, 6000.0, lengthRoll);
  // fade in over 900 ticks, fade out over 1200. fading out slower felt sadder and more emotional
  float envelope =
    smoothstep(eventStart, eventStart + 900.0, t) *
    (1.0 - smoothstep(eventStart + eventLength - 1200.0, eventStart + eventLength, t));
  #if AURORA_FREQUENCY >= 4
  envelope = 1.0;
  #endif

  float level = mix(0.4, 1.0, strength);
  // two sines multiplied together = fake "solar wind surge". sounds smart, is just wobble
  float surge =
    0.8 + 0.2 * sin(frameTimeCounter * 0.07) * sin(frameTimeCounter * 0.023 + 1.0);

  float darkness = 1.0 - smoothstep(-0.18, 0.02, worldSunDir.y); // no aurora while the sun is up, duh
  float clear = 1.0 - smoothstep(0.0, 0.6, rainStrength); // or when it's raining. clouds block it. probably. I'm not an astronaut
  return envelope * level * surge * darkness * clear;
  #endif
}

// 16 steps of raymarching. more = prettier, also more = your laptop becomes a space heater
#ifndef AURORA_QUALITY
#define AURORA_QUALITY 16
#endif

// the actual pretty curtains. marches up through a fake slab of sky and adds up glowy noise
vec3 getAurora(vec3 rayDir, float activity) {
  if (activity <= 0.0 || rayDir.y <= 0.02) return vec3(0.0);

  float t = frameTimeCounter * 0.02;
  // altitudes in completely made up units. 1.0 to 2.6 of... something. bananas maybe
  const float lowerAlt = 1.0;
  const float upperAlt = 2.6;

  // jitter so you don't see 16 stacked layers like a cheap lasagna
  float jitter = 0.5;
  #ifdef fsh
  jitter = interleavedGradientNoise(floor(gl_FragCoord.xy), frameCounter);
  #endif

  vec3 sum = vec3(0.0);
  for (int i = 0; i < AURORA_QUALITY; i++) {
    float u = (float(i) + jitter) / float(AURORA_QUALITY);
    float alt = mix(lowerAlt, upperAlt, u);
    vec2 p = rayDir.xz / rayDir.y * alt * 1.6; // project onto a flat plane. 1.6 is a vibes number

    // warp the coordinates with noise so the curtains wiggle. t * 0.7, t * 0.6... I just kept typing decimals until it looked alive
    vec2 w = vec2(
      auroraNoise(p * 0.22 + vec2(t, -t * 0.7)),
      auroraNoise(p * 0.22 + vec2(5.2 - t * 0.6, 1.3 + t))
    );
    vec2 q = p + (w - 0.5) * 3.5;

    // sin wave = curtain stripes. 1 - abs(sin) raised to a power = thin bright lines. I discovered this on a napkin
    float band = sin(q.x * 0.45 + 4.0 * auroraNoise(q * 0.12 + t * 0.5) + q.y * 0.12);
    float farness = smoothstep(4.0, 18.0, length(p));
    float sheet = pow(1.0 - abs(band), mix(7.0, 2.0, farness)); // far away = blurrier because otherwise it shimmered like hell

    // the vertical streaky "rays" in the curtain
    float rays = 0.35 + 0.65 * mix(auroraNoise(vec2(q.x * 1.1 + q.y * 0.15, t * 2.0)), 0.5, farness);

    // brightest at the bottom and fades going up. exp(-2.6) because real auroras do that I think
    float profile = smoothstep(0.0, 0.07, u) * exp(-u * 2.6);

    float density = sheet * rays * profile;
    if (density <= 1e-4) continue; // nothing here, skip, save like 0.0001 fps

    // the color palette. green at the bottom, violet up top, red only when it's going absolutely feral
    vec3 green = vec3(0.25, 1.00, 0.50);
    vec3 cyan = vec3(0.25, 0.85, 0.80);
    vec3 violet = vec3(0.60, 0.40, 0.90);
    vec3 red = vec3(0.90, 0.35, 0.40);
    vec3 col = mix(green, cyan, smoothstep(0.25, 0.55, u));
    col = mix(col, violet, smoothstep(0.55, 0.85, u));
    col = mix(col, red, smoothstep(0.65, 1.0, u) * smoothstep(0.7, 1.0, activity));

    sum += col * density;
  }
  sum /= float(AURORA_QUALITY);

  sum *= smoothstep(0.01, 0.16, rayDir.y); // hide it near the horizon where it stretches into spaghetti

  // auroras are up north. -z is north in minecraft?? I think?? if it's wrong nobody has told me yet
  float north = smoothstep(-0.6, 0.4, -rayDir.z + 0.5 * rayDir.y);
  sum *= mix(north, 1.0, smoothstep(0.75, 1.0, activity) * 0.5);

  return sum * activity * AURORA_BRIGHTNESS * 0.3;
}

#endif // AURORA_GLSL

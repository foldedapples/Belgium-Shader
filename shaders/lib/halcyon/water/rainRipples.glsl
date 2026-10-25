// rain ripples. little rings that pop up when raindrops hit puddles. cost me my sanity
#ifndef RAIN_RIPPLES_GLSL
#define RAIN_RIPPLES_GLSL

#define RIPPLE_MAX_RADIUS 0.85 // in cell units (whatever the hell a cell unit is, I made it up)
#define RIPPLE_FREQ 34.0 // how wiggly the ring is
#define RIPPLE_WIDTH 55.0 // how thin the ring is. bigger = thinner. yes that's backwards, no I won't fix it

// one layer of ripples. we chop the world into a grid and each cell might have a raindrop in it
vec2 rippleLayer(vec2 p, float t, float rate, float density, float seed) {
  vec2 cell = floor(p);
  vec2 f = fract(p);
  vec2 slope = vec2(0.0);

  // check the 3x3 cells around us because ripples spill into neighbor cells and otherwise you get ugly cut-off rings
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 c = cell + vec2(x, y);
      // random phase per cell so all the drops don't hit at the exact same time like a synchronized swim team
      float phase = hash12(c + seed);
      float cycleT = t * rate + phase;
      float life = fract(cycleT);
      float cycle = floor(cycleT);

      // 7.13, 1.37, 17.31... these are just me smashing the number row until the pattern stopped looking repeated
      if (hash12(c * 1.37 + cycle * 7.13 + seed) > density) continue;
      // keep the drop center away from the cell edge (0.1 to 0.9). learned that one the hard way
      vec2 center = vec2(x, y) + 0.1 + 0.8 * hash22(c + cycle * 17.31 + seed);

      vec2 d = f - center;
      float r = length(d);
      if (r < 1e-4) continue;
      vec2 dir = d / r;

      // ring grows outward over its life. this part I actually understand
      float radius = life * RIPPLE_MAX_RADIUS;
      float xr = r - radius;
      // envelope = the ring fades out as it ages AND only exists near the radius. gaussian shit. I think
      float envelope = pow2(1.0 - life) * exp(-xr * xr * RIPPLE_WIDTH);
      // the derivative of a sine wave is a cosine but I used sine and it looks fine so whatever, don't @ me
      float dhdr = -RIPPLE_FREQ * sin(xr * RIPPLE_FREQ) * envelope;

      // tiny splash right when the drop lands. 220 is how pointy it is. 220 because 200 felt soft
      float splash = max0(1.0 - life * 10.0);
      dhdr += -2.0 * 220.0 * r * exp(-r * r * 220.0) * splash * 0.6;

      slope += dir * dhdr;
    }
  }
  return slope;
}

// adds up ripple layers into one slope. returns how tilted the water is
vec2 rainRippleSlope(vec2 worldXZ, float intensity, float dist) {
  #ifndef RAIN_RIPPLES
  return vec2(0.0);
  #else
  if (intensity <= 1e-3) return vec2(0.0);
  // ripples fade out past 56 blocks because you can't see them anyway and they're expensive as fuck
  float fade = 1.0 - smoothstep(12.0, 56.0, dist);
  if (fade <= 0.0) return vec2(0.0);

  float t = frameTimeCounter;
  float density = mix(0.25, 0.85, intensity);

  // two layers at different sizes so it doesn't look like a grid of identical drops. 0.55 and 0.83 are vibes
  vec2 slope = rippleLayer(worldXZ / 0.55, t, 1.15, density, 0.0) / 0.55;
  slope += rippleLayer(worldXZ / 0.83 + 13.7, t, 0.85, density, 41.0) / 0.83 * 0.6;

  // 0.006 is a tiny number to stop the ripples from looking like a trampoline
  return slope * 0.006 * RAIN_RIPPLE_STRENGTH * intensity * fade;
  #endif
}

// how hard is it raining here. thunderstorm makes it rain harder, obviously
float rainRippleIntensity(float skyLightmap) {
  float rain = rainStrength * biomeCanRainSmooth;
  rain *= mix(0.7, 1.0, thunderStrength);
  return rain * smoothstep(13.5 / 15.0, 14.5 / 15.0, skyLightmap);
}

#endif // RAIN_RIPPLES_GLSL

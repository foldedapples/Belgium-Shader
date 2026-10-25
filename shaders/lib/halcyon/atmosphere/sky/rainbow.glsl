#ifndef RAINBOW_GLSL
#define RAINBOW_GLSL

// turns a wavelength in nanometers into a color. 400 = purple, 700 = red. this is NOT physically accurate, it's smoothstep soup
vec3 spectralColor(float nm) {
  float t = clamp01((nm - 400.0) / 300.0);
  vec3 c = vec3(
    smoothstep(0.45, 0.75, t) + 0.35 * smoothstep(0.15, 0.0, t), // red, plus a little red at the violet end so it looks purple and not just blue. science!!
    smoothstep(0.15, 0.45, t) * (1.0 - smoothstep(0.6, 0.85, t)), // green, a bump in the middle
    1.0 - smoothstep(0.2, 0.45, t) // blue fades out. bye blue
  );
  return c * 0.85 + 0.15; // desaturate a bit or it looks like a 2007 windows screensaver
}

// should there be a rainbow right now? needs wet ground, NOT rain, and the sun up but not too high
float rainbowVisibility() {
  #ifndef RAINBOWS
  return 0.0; // rainbows off. sad
  #else
  float drops = smoothstep(0.15, 0.6, surfaceWetness) * (1.0 - smoothstep(0.05, 0.3, rainStrength));
  float sunUp = smoothstep(0.0, 0.08, worldSunDir.y) * (1.0 - smoothstep(0.55, 0.7, worldSunDir.y)); // sun too high = rainbow goes underground. real thing btw, I looked it up
  return drops * sunUp * biomeCanRainSmooth; // no rainbows in deserts, sorry desert people
  #endif
}

// THE RAINBOW. double rainbow all the way across the sky. what does it mean
vec4 rainbow(vec3 rayDir) {
  float vis = rainbowVisibility();
  if (vis <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);

  // angle away from the anti-sun point, in degrees because radians make my head hurt
  float angle = degrees(acos(clamp(dot(rayDir, -worldSunDir), -1.0, 1.0)));

  vec3 bow = vec3(0.0);
  // primary bow starts at ~40.6 degrees and is ~1.8 degrees wide. wikipedia said 42 but 40.6 looked better, fight me
  float p = (angle - 40.6) / 1.8;
  if (p > -0.4 && p < 1.4) {
    float band = smoothstep(-0.4, 0.1, p) * (1.0 - smoothstep(0.9, 1.4, p));
    bow += spectralColor(mix(400.0, 700.0, clamp01(p))) * band;
  }
  // secondary bow at ~50 degrees, colors flipped and dimmer (0.43). nature is extra
  float s = (angle - 50.3) / 3.3;
  if (s > -0.3 && s < 1.3) {
    float band = smoothstep(-0.3, 0.1, s) * (1.0 - smoothstep(0.9, 1.3, s));
    bow += spectralColor(mix(700.0, 400.0, clamp01(s))) * band * 0.43;
  }
  float inside = (1.0 - smoothstep(30.0, 41.0, angle)) * 0.12; // sky inside the bow is brighter. I have no idea why but it IS, I checked photos
  float darkBand = smoothstep(42.4, 44.0, angle) * (1.0 - smoothstep(48.5, 50.3, angle)); // the dark gap between the bows has a NAME, alexander's band. sounds like a ska group

  float k = 0.45 * RAINBOW_BRIGHTNESS * vis;
  return vec4((bow + inside) * k, 1.0 - 0.07 * darkBand * vis); // alpha darkens the sky, it's not transparency. yes this is confusing. yes it's my fault
}

#endif // RAINBOW_GLSL

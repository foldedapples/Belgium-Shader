#ifndef CIRRUS_GLSL
#define CIRRUS_GLSL

#define CIRRUS_ALTITUDE 3200.0 // how high the wispy clouds float above the camera, in blocks. very high. too high for you

// fake flat cloud layer, returns how thick the wisps are along this ray. "optical depth" is a fancy word I learned last week
float cirrusOpticalDepth(vec3 rayDir, out float dist) {
  dist = 0.0;
  if (rayDir.y < 0.02) return 0.0; // looking sideways or down = no cirrus, otherwise we divide by ~zero and the screen explodes
  dist = CIRRUS_ALTITUDE / rayDir.y;
  vec2 p = (cameraPosition.xz + rayDir.xz * dist) / 250000.0; // 250000 is the "make the noise huge" number. smaller = clouds look like cottage cheese

  float t = worldTimeCounter * 0.00002 * VC_WIND_SPEED;
  const vec2 windDir = vec2(0.8, 0.6); // 0.8,0.6 has length 1, the 3-4-5 triangle from school finally paid off
  p += windDir * t;
  // rotate everything so the clouds stretch along the wind. it's a rotation matrix, I think. it rotates. good enough
  mat2 toWind = mat2(windDir.x, -windDir.y, windDir.y, windDir.x);
  vec2 q = toWind * p;
  q.x *= 0.3; // squish = streaky wisps. this one line turned blobs into cirrus and I screamed

  // domain warping, aka "use noise to wiggle the coordinates for the other noise". it's noise all the way down
  vec2 warp = vec2(
    texture(perlinNoiseTex, fract(q * 2.0 + 0.13)).r,
    texture(perlinNoiseTex, fract(q * 2.0 + 0.57)).r
  ) - 0.5;
  q += clamp(warp * 7.0, -1.0, 1.0) * 0.03;

  // 3 octaves of noise, weights add up to 1.0 (0.55+0.3+0.15) which I only noticed after an hour of it being too bright
  float n = texture(perlinNoiseTex, fract(q)).r * 0.55
          + texture(perlinNoiseTex, fract(q * vec2(2.3, 4.1) + 0.31)).r * 0.3
          + texture(perlinNoiseTex, fract(q * vec2(5.1, 9.7) + 0.77)).r * 0.15;
  n = clamp01((n - 0.5) * 7.0 + 0.5); // contrast cranked to 7. subtle? never heard of her

  float coverage = clamp01(CIRRUS_COVERAGE + 0.25 * wetness); // more clouds when it's wet, makes sense right?? right??
  float d = smoothstep(1.0 - coverage, 1.0 - coverage + 0.5, n);
  d *= smoothstep(0.03, 0.22, rayDir.y); // fade near the horizon so you don't see the ugly stretched edge. out of sight out of mind
  return d * 0.35;
}

// paints the wispy clouds on top of the sky. also fake ice halos because I saw a cool photo once
vec3 applyCirrus(vec3 background, vec3 rayDir, vec3 viewTransmittance, out float layerTrans) {
  layerTrans = 1.0;
  #ifndef CIRRUS_CLOUDS
  return background;
  #else
  float dist;
  float tau = cirrusOpticalDepth(rayDir, dist);
  if (tau <= 0.0) return background;
  layerTrans = exp(-tau); // beer's law. no not that beer. well, also that beer, after writing this

  float costh = dot(rayDir, worldLightDir);
  // two henyey-greenstein lobes, one forward one back. no clue who these guys are but they carry this whole shader
  float forward = henyeyGreenstein(0.75, costh) * 0.7 + henyeyGreenstein(-0.2, costh) * 0.3;
  // 22 degree halo!! ice crystals make a ring around the sun at 22 degrees. nature has magic numbers too, I'm not the only one
  float haloAngle = degrees(acos(clamp(costh, -1.0, 1.0)));
  float halo = exp(-pow2((haloAngle - 22.0) / 0.8)) * 0.6 + exp(-pow2((haloAngle - 21.5) / 0.4)) * 0.2;
  vec3 haloTint = mix(vec3(1.0, 0.8, 0.7), vec3(0.85, 0.9, 1.0), smoothstep(21.0, 23.0, haloAngle)); // reddish inside, bluish outside. like a tiny sad rainbow

  // 4.0 * PI * 0.25 is literally just PI. I know. I KNOW. leaving it because it works
  vec3 light = sunlightColor * (forward * 4.0 * PI * 0.25 + halo * 0.05 * haloTint) + skylightColor * 0.6;
  vec3 scatter = light * (1.0 - layerTrans) * viewTransmittance;
  return background * layerTrans + scatter;
  #endif
}

#endif // CIRRUS_GLSL

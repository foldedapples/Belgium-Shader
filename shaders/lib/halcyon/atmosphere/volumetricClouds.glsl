#ifndef VOLUMETRIC_CLOUDS_GLSL
#define VOLUMETRIC_CLOUDS_GLSL

/*
    volumetric cumulus clouds, after Guerrilla's Nubis (Schneider & Vos,
    SIGGRAPH 2015 / 2017). energy-conserving integration from Hillaire 2016.

    ^ real AAA game devs made these clouds for horizon zero dawn. I watched the talk at 1.5x speed
      and understood maybe the first 4 slides. the rest is me poking numbers until it stopped looking like cauliflower.
*/

#define VC_THICKNESS 620.0 // how tall a normal cumulus is in blocks. storm clouds get taller. like my stack of unfinished projects

// how much sky has clouds. rain pushes it toward 0.95, thunder all the way to 1.0 = "the sky is just a ceiling now"
float vcCoverage() {
  float c = CLOUD_COVERAGE;
  c = mix(c, 0.95, wetness * 0.8);
  c = mix(c, 1.0, thunderStrength * 0.8);
  return clamp01(c);
}

// linear remap. the famous nubis remap. the max(..., 1e-4) is there because I divided by zero once and the whole sky went NaN-black. never again
float vcRemap(float v, float lo, float hi, float nlo, float nhi) {
  return nlo + (v - lo) * (nhi - nlo) / max(hi - lo, 1e-4);
}

const vec3 vcWindDir = vec3(0.94, 0.0, 0.33); // wind blows mostly east-ish. it's not normalized exactly. it's close enough. everything is close enough

// time that loops so floats don't lose precision after 100 in-game days and make the clouds jitter like they drank 4 energy drinks.
// the 1024 split thing is to dodge float precision on worldDay. I don't fully get it. it works. DO NOT FUCKING TOUCH
float vcWrapTime(float rate, float period) {
  float q = rate * 1200.0 / period; // 1200 = seconds per minecraft day. 24000 ticks / 20. look at me doing unit conversions
  int hi = worldDay / 1024;
  int lo = worldDay - hi * 1024;
  float dayPart = fract(float(hi) * fract(1024.0 * q) + float(lo) * q);
  return mod(dayPart * period + rate * float(worldTime) / 20.0, period);
}

// wind offset for a given noise tile size. different layers move at different speeds so it doesn't look like a scrolling wallpaper
vec3 vcWindOffset(float period, float mul) {
  float rate = VC_WIND_SPEED * 6.0 * mul;
  return vec3(
    vcWrapTime(rate * vcWindDir.x, period),
    0.0,
    vcWrapTime(rate * vcWindDir.z, period)
  );
}

// cloud bottoms get bumped up by up to this many blocks depending on the region (see vcWeather). flat-bottomed clouds everywhere looked fake as hell
#define VC_BASE_LIFT 90.0

// bottom and top of the whole cloud layer. thunder drops the base 120 blocks and makes towers 2.3x taller. storms are dramatic, I made them dramatic
vec2 vcLayer() {
  float base = VC_ALTITUDE - thunderStrength * 120.0;
  float maxType = 0.62 + 0.38 * thunderStrength;
  float tallest = VC_THICKNESS * mix(1.0, 2.3, smoothstep(0.5, 1.0, maxType));
  float top = base + VC_BASE_LIFT * (1.0 - thunderStrength) + tallest + 20.0; // +20 safety margin because the tops were getting chopped off. flat-top clouds. like a haircut gone wrong
  return vec2(base, top);
}

// global variables that get filled once per pixel by vcPrepare(). globals in a shader. my CS teacher is somewhere crying and doesn't know why
vec2 vcF_layer;
float vcF_coverage;
vec2 vcF_windWeather;
vec2 vcF_windWeather2;
vec3 vcF_windBase;
vec3 vcF_evolve;

// precompute all the wind and layer stuff ONCE instead of 500 times per pixel. this one function gave me like 15 fps back and I danced
void vcPrepare() {
  vcF_layer = vcLayer();
  vcF_coverage = vcCoverage();
  vcF_windWeather = vcWindOffset(9000.0, 1.5).xz;
  vcF_windWeather2 = vcWindOffset(9000.0 / 0.31, 1.5).xz;
  vcF_windBase = vcWindOffset(1700.0, 1.0);
  vcF_evolve = vcWindOffset(380.0, 1.6) + vec3(0.0, vcWrapTime(VC_WIND_SPEED * 1.5, 380.0), 0.0); // the y part makes the detail noise boil upward so clouds look alive and not like frozen popcorn
}

// weather map sample: coverage, cloud type (0 = flat puffy, 1 = big storm tower), base lift, and a warp offset
struct VcWeather {
  float cov;
  float type;
  float lift;
  vec2 warp;
};

// samples the big 9000-block weather map. this decides where clouds are and what kind. basically the cloud god function
VcWeather vcWeather(vec2 xz) {
  vec2 wuv = (xz + vcF_windWeather) / 9000.0;
  vec4 w = texture(perlinNoiseTex, fract(wuv));
  vec2 wuv2 = (xz + vcF_windWeather2) * (0.31 / 9000.0) + 0.53; // second map at a weird scale (0.31) so the two never line up. 0.53 offset because 0.5 felt too round
  vec4 w2 = texture(perlinNoiseTex, fract(wuv2));
  float cov = clamp01((w.r - 0.5) * 3.0 + 0.5);
  float type = clamp01((w2.g - 0.5) * 3.0 + 0.5);
  type = mix(0.08, 0.62, type);
  type = mix(type, 0.05, wetness * (1.0 - thunderStrength) * 0.85); // plain rain = flat grey stratus. no towers. just sadness
  float cell = smoothstep(0.55, 0.85, clamp01((w.b - 0.5) * 3.0 + 0.5)); // storm cells, where the big thunderheads go
  type = mix(type, max(type, 0.55 + 0.45 * cell), thunderStrength);
  cov = mix(cov, max(cov, cell), thunderStrength * 0.7);
  VcWeather wx;
  wx.cov = cov;
  wx.type = type;
  wx.lift = VC_BASE_LIFT * smoothstep(0.2, 0.8, w2.r) * (1.0 - thunderStrength);
  wx.warp = (vec2(w.g, w.a) - 0.5) * 360.0; // shove the noise around by up to 180 blocks so you don't see the same cloud twice. you will anyway
  return wx;
}

// how tall a cloud of this type gets. 190 blocks for tiny puffs, up to 620 * 2.3 = 1426 for storm towers. I did that math in my head. jk calculator
float vcTypeTop(float type) {
  return type < 0.5
    ? mix(190.0, VC_THICKNESS, smoothstep(0.0, 0.5, type))
    : mix(VC_THICKNESS, VC_THICKNESS * 2.3, smoothstep(0.5, 1.0, type));
}

// THE density function. given a point, how much cloud is there. this is the heart of everything. the heart is full of magic numbers
float vcDensityW(vec3 worldPos, VcWeather weather, float detailAmount, out bool cheapEmpty) {
  cheapEmpty = true;
  float above = worldPos.y - vcF_layer.x - weather.lift;
  if (above <= 0.0 || worldPos.y >= vcF_layer.y) return 0.0;

  float type = weather.type;
  float top = vcTypeTop(type);
  float hn = above / top; // normalized height inside the cloud, 0 = bottom, 1 = top
  if (hn >= 1.0) return 0.0;

  // height profile: soft bottom, rounded top. 0.55 vs 0.3 makes storm tops more cauliflower-y. it's always cauliflower with clouds
  float bottom = smoothstep(0.0, mix(25.0, 70.0, type), above);
  float roundTop = mix(0.55, 0.3, smoothstep(0.0, 0.6, type));
  float profile = bottom * (1.0 - smoothstep(roundTop, 1.0, hn));
  // the ANVIL. big storm clouds flatten out at the top like an anvil. I learned this from a weather youtuber at 4am
  float anvil = smoothstep(0.75, 1.0, type) * smoothstep(0.7, 0.88, hn) * (1.0 - smoothstep(0.93, 1.0, hn));
  profile = max(profile, anvil);

  vec3 p = worldPos + vcF_windBase;
  p.xz += vcWindDir.xz * above * 0.35 + weather.warp; // the tops lean downwind. "wind shear". I know words now

  float coverage = vcF_coverage * mix(0.55, 1.35, weather.cov);
  coverage = min(coverage + anvil * 0.35, 1.0);

  // base shape noise. 0.625 + 0.25 + 0.125 = 1. the classic halving weights. nubis said so
  vec4 n = texture(cloudNoiseTex, fract(p / 1700.0));
  float lowFreqFBM = n.g * 0.625 + n.b * 0.25 + n.a * 0.125;
  float base = vcRemap(n.r, -(1.0 - lowFreqFBM), 1.0, 0.0, 1.0); // remapping perlin-worley by fbm. straight from the slides. I don't know what it does. it looks like clouds
  base *= profile;
  base = vcRemap(base, 1.0 - coverage, 1.0, 0.0, 1.0) * coverage;
  if (base <= 0.0) return 0.0;
  cheapEmpty = false;

  // erode the edges with small detail noise so they're wispy at the bottom and billowy at the top. or the other way around. one of those
  if (detailAmount > 0.0) {
    vec3 dp = (worldPos + vcF_evolve + vec3(weather.warp.x, 0.0, weather.warp.y) * 0.5) / 380.0 + vec3(0.0, -hn * 0.4, 0.0);
    vec4 d = texture(cloudNoiseTex, fract(dp));
    float detailFBM = d.g * 0.625 + d.b * 0.25 + d.a * 0.125;
    float erosion = mix(detailFBM, 1.0 - detailFBM, clamp01(hn * 4.0));
    base = vcRemap(base, erosion * mix(0.3, 0.45, type) * detailAmount, 1.0, 0.0, 1.0);
  }

  float densityMul = mix(1.0, 1.6, wetness) * mix(1.0, 1.5, smoothstep(0.6, 1.0, type)); // rain clouds and storm clouds are denser = darker. makes sense to me, a meteorologist (I am not a meteorologist)
  return max0(base) * CLOUD_DENSITY * densityMul;
}

// wrapper that also looks up the weather. three overloads of vcDensity because I couldn't decide on one and now I live like this
float vcDensity(vec3 worldPos, float detailAmount, out bool cheapEmpty, out VcWeather weather) {
  cheapEmpty = true;
  weather = VcWeather(0.0, 0.0, 0.0, vec2(0.0));
  if (worldPos.y <= vcF_layer.x || worldPos.y >= vcF_layer.y) return 0.0;
  weather = vcWeather(worldPos.xz);
  return vcDensityW(worldPos, weather, detailAmount, cheapEmpty);
}

float vcDensity(vec3 worldPos, float detailAmount, out bool cheapEmpty) {
  VcWeather weather;
  return vcDensity(worldPos, detailAmount, cheapEmpty, weather);
}

float vcDensity(vec3 worldPos, bool detail) {
  bool cheapEmpty;
  return vcDensity(worldPos, detail ? 1.0 : 0.0, cheapEmpty);
}

// march toward the sun to see how much cloud is blocking light. steps grow by 1.9x each time so a few samples reach far. cheap trick, works great, no regrets
float vcLightOpticalDepth(vec3 worldPos, float extinction, float detailAmount, VcWeather weather, int lightSteps) {
  float od = 0.0;
  float stepLen = 18.0;
  vec3 p = worldPos;
  bool unused; // a variable literally named unused. peak code quality right here
  for (int i = 0; i < lightSteps; i++) {
    p += worldLightDir * stepLen;
    float dd = detailAmount * float(i < 2); // only the first 2 steps get detail noise. the rest are blurry. like my vision without glasses
    od += (i < 3 ? vcDensityW(p, weather, dd, unused) : vcDensity(p, dd, unused)) * stepLen; // reuse the weather for the first 3 steps since we haven't moved far. saves a texture lookup. every lookup counts
    stepLen *= 1.9;
  }
  return od * extinction;
}

// four phase values for four scattering octaves, each half as directional and half as strong. it's the multiple scattering trick again
struct VcPhase { float p0, p1, p2, p3; };

// precomputed once per pixel instead of every step. 0.8, 0.4, 0.2, 0.1. I see a pattern. I'm basically a mathematician
VcPhase vcPhase(float costh) {
  return VcPhase(
    dualHenyeyGreenstein(0.8, -0.3, costh, 0.7),
    dualHenyeyGreenstein(0.4, -0.15, costh, 0.7) * 0.5,
    dualHenyeyGreenstein(0.2, -0.075, costh, 0.7) * 0.25,
    dualHenyeyGreenstein(0.1, -0.0375, costh, 0.7) * 0.125
  );
}

// one exp() instead of four by squaring repeatedly. e3 squared = e2, squared = e1, squared = e0. stackoverflow didn't teach me this one, I figured it out myself and I'm STILL proud
vec3 vcMultipleScattering(float lightOD, VcPhase ph) {
  vec3 e3 = exp(-lightOD * CLOUD_EXTINCTION_COLOR * 0.125);
  vec3 e2 = e3 * e3;
  vec3 e1 = e2 * e2;
  vec3 e0 = e1 * e1;
  return ph.p0 * e0 + ph.p1 * e1 + ph.p2 * e2 + ph.p3 * e3;
}

// where the ray enters and exits the cloud slab. if the ray is perfectly flat, special case so we don't divide by zero. dividing by zero is my nemesis
vec2 vcSlab(vec3 ro, vec3 rd, vec2 layer) {
  if (abs(rd.y) < 1e-5) {
    if (ro.y > layer.x && ro.y < layer.y) return vec2(0.0, 1e5);
    return vec2(0.0, -1.0);
  }
  float t0 = (layer.x - ro.y) / rd.y;
  float t1 = (layer.y - ro.y) / rd.y;
  float tn = max(min(t0, t1), 0.0);
  float tf = max(t0, t1);
  return vec2(tn, tf);
}

// THE MAIN RAYMARCHER. 130 lines of pain. if the clouds look wrong, the bug is in here. it is always in here
vec3 getVolumetricClouds(
  vec3 origin,
  vec3 worldDir,
  int steps,
  float jitter,
  float maxDist,
  out vec3 transmittance,
  out float cloudDepth
) {
  transmittance = vec3(1.0);
  cloudDepth = -1.0;
  #ifndef WORLD_OVERWORLD
  return vec3(0.0);
  #endif

  vcPrepare();
  vec3 ro = origin + cameraPosition;
  vec2 layer = vcF_layer;
  vec2 t = vcSlab(ro, worldDir, layer);
  const float maxRange = 24000.0; // 24 km max. past that you can't see shit anyway
  if (t.x > maxRange) return vec3(0.0);
  float tEnd = min(min(t.y, maxDist), t.x + maxRange);
  if (tEnd <= t.x) return vec3(0.0);

  float extinction = 0.045; // 0.045. the number that decides if clouds are fluffy or concrete. I spent a whole evening on this one number
  int marchSteps = int(float(steps) * clamp(0.25 / max(abs(worldDir.y), 1e-3), 1.0, 1.5)); // more steps near the horizon since the ray goes through more cloud
  float evenStep = (tEnd - t.x) / float(marchSteps);
  float quality = 32.0 / float(max(steps, 1));
  float nearStep = 6.0 * quality;
  float growth = 0.05 * quality; // steps get bigger the farther away. far clouds don't need detail, they're far. that's the whole point of far
  VcPhase phase = vcPhase(dot(worldDir, worldLightDir));

  float costh = dot(worldDir, worldLightDir);
  bool day = lightDir == sunDir;

  // sun is 7.5x brighter on clouds. ambient is brighter on top (sky) than bottom (ground bounce). picked by staring at clouds out my window
  vec3 lightColor = sunlightColor * (day ? 7.5 : 1.0);
  vec3 ambientTop = skylightColor * 1.6;
  vec3 ambientBottom = skylightColor * 0.45 + sunlightColor * 0.02;

  float T = 1.0;
  vec3 scatter = vec3(0.0);
  float firstHit = -1.0;
  float depthSum = 0.0;
  float depthWeight = 0.0;

  // two-speed marching: big coarse steps through empty air, then back up and go fine when we hit cloud. like speed walking until you see a cop
  const float coarseMul = 2.0;
  float stepLen = min(evenStep, nearStep + growth * t.x);
  float tCur = t.x + stepLen * jitter;
  bool fine = false;
  int emptyFine = 0;
  float lockUntil = t.x;
  int maxIterations = marchSteps * 4 + 16; // safety cap so a bad loop can't freeze the GPU. I froze my GPU. twice. had to hard reboot
  for (int i = 0; i < maxIterations; i++) {
    if (tCur >= tEnd) break;
    stepLen = min(evenStep, nearStep + growth * tCur);
    vec3 p = ro + worldDir * tCur;

    // coarse mode: found something? step BACK and switch to fine mode so we don't skip the cloud edge
    if (!fine) {
      if (vcDensity(p, false) > 1e-4) {
        fine = true;
        emptyFine = 0;
        lockUntil = tCur;
        tCur = max(tCur - stepLen * coarseMul, t.x + stepLen * jitter);
      } else {
        tCur += stepLen * coarseMul;
      }
      continue;
    }

    float segLen = min(stepLen, tEnd - tCur);

    float detailAmount = 1.0 - smoothstep(6000.0, 10000.0, tCur); // no detail noise past 10 km. nobody can see it. I tested on myself, I couldn't see it
    bool cheapEmpty;
    VcWeather weather;
    float d = vcDensity(p, detailAmount, cheapEmpty, weather);
    if (d > 1e-4) {
      emptyFine = 0;
      if (firstHit < 0.0) firstHit = tCur;
      float sigma = d * extinction;

      int lightSteps = tCur > 4000.0 ? max(VC_LIGHT_STEPS_Q - 2, 3) : VC_LIGHT_STEPS_Q;
      float lightOD = vcLightOpticalDepth(p, extinction, detailAmount, weather, lightSteps);
      float h = clamp01((p.y - layer.x - weather.lift) / VC_THICKNESS);

      vec3 ms = vcMultipleScattering(lightOD, phase);
      ms = max(ms, vec3(0.06 / (1.0 + 0.11 * lightOD))); // floor on the light so the insides of thick clouds aren't pitch black. 0.06 and 0.11, pulled from the ether
      // powder effect again. dark edges when looking away from the sun. powdered sugar. I'm hungry now
      float powder = 1.0 - exp(-d * extinction * 24.0);
      powder = mix(powder * 2.0, 1.0, costh * 0.5 + 0.5);

      vec3 S = lightColor * ms * powder + mix(ambientBottom, ambientTop, h) * 0.7;
      S *= sigma;

      // the hillaire energy-conserving integration. (S - S*T) / sigma. it stops the clouds from getting brighter when you add more steps. black magic. it's from the paper. it works
      float stepT = exp(-sigma * segLen);
      scatter += T * (S - S * stepT) / max(sigma, 1e-6);
      float absorbed = T * (1.0 - stepT);
      depthSum += absorbed * tCur;
      depthWeight += absorbed;
      T *= stepT;
      // basically opaque now, stop marching. 1% left. nobody will notice. NOBODY
      if (T < 0.01) {
        T = 0.0;
        break;
      }
    } else if (tCur > lockUntil && cheapEmpty) {
      if (++emptyFine >= 2) fine = false; // two empty samples in a row = go back to coarse mode. two strikes, you're out
    } else {
      emptyFine = 0;
    }
    tCur += stepLen;
  }
  if (depthWeight > 1e-3) cloudDepth = depthSum / depthWeight; // average depth weighted by how much light got eaten there. used for the upscaler. I think. it's used somewhere

  // lightning flash lights up clouds within 600 blocks. bluish white. KABOOM
  if (lightningBoltPosition.w > 0.5 && firstHit > 0.0) {
    vec3 hitPos = ro + worldDir * firstHit;
    float flash = clamp01(
      1.0 - distance(hitPos.xz - cameraPosition.xz, lightningBoltPosition.xz) / 600.0
    );
    scatter += vec3(0.6, 0.65, 1.0) * pow3(flash) * (1.0 - T) * 0.5;
  }

  // far clouds fade into the sky. 0.00011 = fade over ~9 km. without this the horizon looked like a cardboard cutout
  float dist = firstHit > 0.0 ? firstHit : t.x;
  float fade = exp(-dist * 0.00011);
  scatter *= fade;
  T = mix(1.0, T, fade);
  float horizon = smoothstep(0.0, 0.06, worldDir.y);
  if (ro.y < layer.x) {
    scatter *= horizon;
    T = mix(1.0, T, horizon);
  }

  transmittance = vec3(T);
  return scatter * skyMultiplier;
}

// lazy overloads so callers can skip arguments. overloading: the only OOP thing GLSL lets me do
vec3 getVolumetricClouds(vec3 origin, vec3 worldDir, int steps, float jitter, float maxDist, out vec3 transmittance) {
  float cloudDepth;
  return getVolumetricClouds(origin, worldDir, steps, jitter, maxDist, transmittance, cloudDepth);
}

vec3 getVolumetricClouds(vec3 origin, vec3 worldDir, int steps, float jitter, out vec3 transmittance) {
  float cloudDepth;
  return getVolumetricClouds(origin, worldDir, steps, jitter, 1e9, transmittance, cloudDepth); // 1e9 = "no max distance". a billion blocks. good luck walking that
}

// cloud shadows on the ground. march toward the sun through the slab, add up density, exp it. a mini raymarcher. the little brother
vec3 getVolumetricCloudShadow(vec3 feetPlayerPos, int n) {
  vcPrepare();
  vec3 ro = feetPlayerPos + cameraPosition;
  vec2 layer = vcF_layer;
  vec2 t = vcSlab(ro, worldLightDir, layer);
  if (t.y <= t.x) return vec3(1.0);
  float len = min(t.y - t.x, 3000.0);
  float stepLen = len / float(n);
  float od = 0.0;
  for (int i = 0; i < n; i++) {
    vec3 p = ro + worldLightDir * (t.x + stepLen * (float(i) + 0.5)); // + 0.5 = sample the middle of each step. midpoint rule. calculus strikes again
    od += vcDensity(p, false) * stepLen;
  }
  // 0.045 * 0.6, shadows a bit lighter than the clouds look, or the ground gets way too dark. artistic license. I have one, I printed it myself
  vec3 T = exp(-od * 0.045 * 0.6 * CLOUD_EXTINCTION_COLOR);
  return clamp01(mix(T, vec3(1.0), 1.0 - smoothstep(0.1, 0.2, worldLightDir.y)));
}

// default 4 shadow steps. 4. for a whole cloud layer. it's fine. it's FINE
vec3 getVolumetricCloudShadow(vec3 feetPlayerPos) {
  return getVolumetricCloudShadow(feetPlayerPos, 4);
}

#endif // VOLUMETRIC_CLOUDS_GLSL

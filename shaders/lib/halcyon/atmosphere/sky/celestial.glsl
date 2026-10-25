#ifndef CELESTIAL_GLSL
#define CELESTIAL_GLSL

/*
    moon texture: NASA SVS 4720 near-side disk built by tools/nasa_moon.py
    eclipses: orbital model driven by world time (getEclipseState), sun/moon
    ^ yes I downloaded the actual moon from NASA. for a block game. my mom would be so proud
*/

#define SUN_ANGULAR_RADIUS (0.2665 * PI / 180.0 * SUN_SIZE)
#define MOON_ANGULAR_RADIUS (0.26 * PI / 180.0 * MOON_SIZE)

// the famous sin-fract hash. 12.9898, 78.233, 43758.5453. every shader on earth has these numbers and NOBODY knows where they came from
float celestialHash(float x) {
  return fract(sin(x * 12.9898 + 78.233) * 43758.5453);
}

// a bag of numbers describing how fucked the sun and moon currently are
struct EclipseState {
  float solarCoverage;
  vec2 solarOffset;
  float occluderRadius;
  float lunarUmbra;
  float lunarPenumbra;
  vec2 lunarOffset;
};

// how much of circle 1 is covered by circle 2, as a fraction. two circles. how hard can it be. (very. it's very hard.)
float circleOverlapFraction(float r1, float r2, float d) {
  if (d >= r1 + r2) return 0.0; // not touching. easy. the last easy line in this function
  if (d <= abs(r2 - r1)) return r2 >= r1 ? 1.0 : pow2(r2 / r1); // one is fully inside the other
  // law of cosines twice and then a heron's formula looking thing. I copied this off a math forum and checked it with 2 coins on my desk
  float a1 = acos(clamp((d * d + r1 * r1 - r2 * r2) / (2.0 * d * r1), -1.0, 1.0));
  float a2 = acos(clamp((d * d + r2 * r2 - r1 * r1) / (2.0 * d * r2), -1.0, 1.0));
  float k = 0.5 * sqrt(max(0.0, (-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2)));
  return (r1 * r1 * a1 + r2 * r2 * a2 - k) / (PI * r1 * r1);
}

#define ECLIPSE_HALF_DURATION 1500.0

// works out if there's an eclipse right now. this is an ORBITAL MODEL. in MINECRAFT. what am I doing with my life
EclipseState getEclipseState() {
  EclipseState e;
  // defaults = "no eclipse, everything far away". 100.0 offset means "somewhere in narnia"
  e.solarCoverage = 0.0;
  e.solarOffset = vec2(100.0);
  e.occluderRadius = 1.12; // moon is 12% bigger than the sun here so total eclipses actually happen. cheating? yes. cool? also yes
  e.lunarUmbra = 0.0;
  e.lunarPenumbra = 0.0;
  e.lunarOffset = vec2(100.0);

  // an empty #ifdef. it does nothing. it's been here forever. I think it's load bearing. leave it alone
  #ifdef ECLIPSES
  #endif
  #if defined ECLIPSES && defined WORLD_OVERWORLD
  float day = float(worldDay);
  float tick = float(worldTime);
  int phase = int(mod(day, 8.0)); // minecraft moon has 8 phases. 4 = new moon, 0 = full moon. learned that today actually

  // real moon: synodic month 29.531 days, draconic 27.212. scaled to minecraft's 8 day month. I googled "draconic" expecting dragons. disappointed
  const float synodic = 8.0;
  const float draconic = synodic * 27.212 / 29.531;
  float p = clamp(8.0 / float(ECLIPSE_FREQUENCY), 0.02, 0.95);
  float spread = sin(p * PI * 0.5);

  float timeDays = day + tick / 24000.0;
  float F = 2.0 * PI * fract(timeDays / draconic + 0.37); // 0.37 is a random offset so day 0 isn't an eclipse. pure superstition
  float latitude = sin(F);

  // solar eclipse can only happen on new moon days. that's real science and I'm weirdly proud of it
  bool solarDay = phase == 4;
  #if ECLIPSE_PREVIEW == 1
  solarDay = true;
  #endif
  if (solarDay) {
    float t = (tick - 6000.0) / ECLIPSE_HALF_DURATION; // 6000 = noon. eclipse peaks at noon. very dramatic. very convenient
    float rOcc = e.occluderRadius;
    float inclination = (1.0 + rOcc) / spread;
    float b = latitude * inclination;
    #if ECLIPSE_PREVIEW == 1
    b = 0.02;
    #endif
    if (abs(b) < 1.0 + rOcc) {
      float reach = sqrt(max(pow2(1.0 + rOcc) - b * b, 1e-3)); // pythagoras again. that guy is everywhere
      e.solarOffset = vec2(t * reach, b);
      e.solarCoverage = circleOverlapFraction(1.0, rOcc, length(e.solarOffset));
    }
  }

  // lunar eclipse = full moon night. blood moon time baby
  bool lunarNight = phase == 0;
  #if ECLIPSE_PREVIEW == 2
  lunarNight = true;
  #endif
  if (lunarNight) {
    // earth's shadow sizes in moon-radii. 2.6 and 4.6. I measured these by squinting at a wikipedia diagram
    float umbraR = 2.6;
    float penumbraR = 4.6;
    float t = (tick - 18000.0) / (ECLIPSE_HALF_DURATION * 1.4); // 18000 = midnight. lunar eclipses last longer, hence the 1.4
    float inclination = (1.0 + umbraR) / spread;
    float b = latitude * inclination;
    #if ECLIPSE_PREVIEW == 2
    b = 0.3;
    #endif
    if (abs(b) < 1.0 + penumbraR) {
      float reach = sqrt(max(pow2(1.0 + penumbraR) - b * b, 1e-3));
      e.lunarOffset = vec2(t * reach, b);
      float d = length(e.lunarOffset);
      e.lunarUmbra = circleOverlapFraction(1.0, umbraR, d);
      e.lunarPenumbra = circleOverlapFraction(1.0, penumbraR, d);
    }
  }
  #endif

  return e;
}

// sunlight gets blocked by however much moon is in the way. the one function in this file I fully understand
float eclipseSunlightFactor(EclipseState e) {
  return 1.0 - e.solarCoverage;
}

// moonlight turns dark red during a lunar eclipse. 0.28, 0.10 = blood orange. spooky
vec3 eclipseMoonlightFactor(EclipseState e) {
  vec3 umbraTint = vec3(1.0, 0.28, 0.10) * 0.05;
  float penumbraOnly = max0(e.lunarPenumbra - e.lunarUmbra);
  return mix(vec3(1.0), umbraTint, e.lunarUmbra) * (1.0 - 0.45 * penumbraOnly);
}

// sky goes dark during totality. pow 3 so it stays bright until the very end, like real life. 0.004 because 0 looked like a bug
float eclipseSkyFactor(EclipseState e) {
  float c = e.solarCoverage;
  return mix(1.0, 0.004, pow(c, 3.0));
}

// the edge of the sun is darker than the middle. "limb darkening". the sun has limbs. wtf
vec3 solarLimbDarkening(float mu) {
  const vec3 u = vec3(0.397, 0.503, 0.652); // per-channel coefficients from some astronomy table. blue darkens more. don't ask me why, ask the sun
  return 1.0 - u * (1.0 - pow(mu, 0.8));
}

// draws the sun as an actual disk with soft edges, limb darkening, and a CORONA during eclipses. overkill is my middle name
vec3 sunDiskRadiance(vec3 rayDir, EclipseState e) {
  float radius = SUN_ANGULAR_RADIUS;
  float cosTheta = dot(rayDir, worldSunDir);
  float theta = acos(clamp(cosTheta, -1.0, 1.0));

  // build a little coordinate system pointing at the sun. the + 1e-5 stops cross() from returning zero when the sun is straight up. found that one at 2am
  vec3 fwd = worldSunDir;
  vec3 right = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)) + vec3(1e-5, 0.0, 0.0));
  vec3 up = cross(right, fwd);
  vec2 p = vec2(dot(rayDir, right), dot(rayDir, up)) / tan(radius); // p is in "sun radii" now. r = 1 is the edge of the sun
  float r = length(p);
  #ifdef fsh
  float aa = max(fwidth(r), 1e-3); // antialiasing using fwidth, which is magic that only works in fragment shaders
  #else
  float aa = 0.02;
  #endif

  if (theta > radius * 10.0) return vec3(0.0); // too far from the sun, don't bother

  // keep total brightness the same no matter what SUN_SIZE is. energy conservation or whatever. physics nerds rejoice
  const float originalSunRadius = 0.2 * PI / 180.0;
  vec3 baseRadiance = sunIrradiance * originalSunRadius / (radius * radius);
  float diskMask = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);

  float mu = sqrt(max(0.0, 1.0 - min(r * r, 1.0)));
  vec3 disk = baseRadiance * solarLimbDarkening(mu) * diskMask * SUN_BRIGHTNESS;

  if (e.solarCoverage > 0.0) {
    float dOcc = length(p - e.solarOffset);
    float occMask = 1.0 - smoothstep(e.occluderRadius - aa, e.occluderRadius + aa, dOcc);
    disk *= 1.0 - occMask;

    float totality = smoothstep(0.985, 1.0, e.solarCoverage);
    if (totality > 0.0 && r > 1.0) {
      // corona streamers: three sines at 3, 7 and 13 times the angle. primes because primes feel scientific
      float ang = atan(p.y, p.x);
      float streamers =
        0.6 + 0.4 * sin(ang * 3.0 + 1.3) * sin(ang * 7.0 + 0.4) +
        0.25 * sin(ang * 13.0);
      float corona = pow(r, -4.5) * max(streamers, 0.15); // r to the -4.5. drops off FAST. like my motivation
      vec3 coronaColor = vec3(0.95, 0.97, 1.0);
      disk += coronaColor * baseRadiance * 2e-5 * corona * totality;
    }
    disk *= 1.0 - occMask; // multiplying by the mask AGAIN. yes twice. the corona was leaking through the moon. this fixed it. moving on
  }

  return disk;
}

// forward declaration because GLSL can't look ahead. it's 2024 (or whatever year you're reading this) and we still do this
vec3 moonGlow(vec3 rayDir, EclipseState e);

// phase 0..8 turned into an angle 0..PI. it goes up then comes back down. like a sad roller coaster
float moonPhaseAngle() {
  float ph = float(moonPhase);
  return (ph <= 4.0 ? ph : 8.0 - ph) * (PI / 4.0);
}

// waxing or waning. which side is lit. I got this backwards 3 times
float moonWaxingSign() {
  return moonPhase > 4 ? 1.0 : -1.0;
}

// (magnitude curve from Allen's Astrophysical Quantities)
// ^ a real book. I did not read it. astronomers use "magnitude" where bigger = dimmer, which is psychotic, hence the -0.4
float moonPhaseBrightness() {
  float phi = degrees(moonPhaseAngle());
  float mag = 0.026 * phi + 4e-9 * pow(phi, 4.0);
  return pow(10.0, -0.4 * mag);
}

// the custom moon. with a real NASA texture, phases, bumps, earthshine, and blood moons. it took 3 weekends and a piece of my soul
vec3 moonDiskRadiance(vec3 rayDir, EclipseState e, out float coverage) {
  coverage = 0.0;
  #ifndef CUSTOM_MOON
  return vec3(0.0);
  #else
  vec3 moonDir = -worldSunDir; // moon is opposite the sun. always. minecraft doesn't do orbits. thank god
  float radius = MOON_ANGULAR_RADIUS;
  float cosTheta = dot(rayDir, moonDir);

  // same coordinate system trick as the sun. copy paste is a design pattern
  vec3 fwd = moonDir;
  vec3 right = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)) + vec3(1e-5, 0.0, 0.0));
  vec3 up = cross(right, fwd);
  vec2 p = vec2(dot(rayDir, right), dot(rayDir, up)) / tan(radius);
  float r2 = dot(p, p);

  vec2 uv = clamp(p * 0.5 + 0.5, vec2(0.001), vec2(0.999));
  #ifdef fsh
  vec2 du = dFdx(uv);
  vec2 dv = dFdy(uv);
  #else
  vec2 du = vec2(0.0);
  vec2 dv = vec2(0.0);
  #endif

  if (cosTheta < cos(radius * 1.05)) return vec3(0.0);

  // iris doesn't give custom textures mipmaps so the moon sparkled like a disco ball when small. so I average 4 samples by hand. ugh
  vec4 tex = texture(moonTex, uv);
  #ifdef fsh
  {
    vec2 texSize = vec2(textureSize(moonTex, 0));
    float footprint = max(length(du * texSize), length(dv * texSize));
    if (footprint > 1.5) {
      // the 0.375 / 0.125 offsets are a rotated grid pattern. stackoverflow said so and stackoverflow is my god
      tex = 0.25 * (
        texture(moonTex, uv + du * 0.375 + dv * 0.125) +
        texture(moonTex, uv - du * 0.375 - dv * 0.125) +
        texture(moonTex, uv + du * 0.125 - dv * 0.375) +
        texture(moonTex, uv - du * 0.125 + dv * 0.375)
      );
    }
  }
  #endif
  float edgeWidth = max(2.0 * max(length(du), length(dv)), 1e-3);
  coverage = 1.0 - smoothstep(1.0 - edgeWidth, 1.0 + edgeWidth, sqrt(r2));
  if (coverage <= 0.0) return vec3(0.0);

  // make a fake sphere normal from the 2D disk. z = sqrt(1 - x^2 - y^2). the moon is a ball. the ball is math
  vec2 pc = p * min(1.0, 0.995 / max(sqrt(r2), 1e-4));
  vec3 n = vec3(pc, sqrt(max(0.0, 1.0 - dot(pc, pc))));

  // crater bumps using the height map in alpha. finite differences, which is a fancy way of saying "subtract neighbors"
  #ifdef MOON_BUMP
  {
    vec2 texel = 1.0 / vec2(textureSize(moonTex, 0));
    vec2 stepUV = max(texel, abs(du) + abs(dv));
    float hx = texture(moonTex, uv + vec2(stepUV.x, 0.0)).a - texture(moonTex, uv - vec2(stepUV.x, 0.0)).a;
    float hy = texture(moonTex, uv + vec2(0.0, stepUV.y)).a - texture(moonTex, uv - vec2(0.0, stepUV.y)).a;
    vec2 grad = vec2(hx / (2.0 * stepUV.x), hy / (2.0 * stepUV.y)) * 0.004; // 0.004 because 0.01 made the moon look like a golf ball
    grad *= 1.0 - smoothstep(0.88, 0.97, sqrt(r2)); // fade bumps at the edge or it gets crunchy
    n = normalize(n - vec3(grad, 0.0));
  }
  #endif

  float phi = moonPhaseAngle();
  vec3 L = vec3(moonWaxingSign() * sin(phi), 0.0, cos(phi)); // fake sun direction for the moon phase

  // lommel-seeliger lighting, which is a moon-specific lighting model. yes those exist. this is why the full moon looks flat
  float mu0 = max(dot(n, L), 0.0);
  float mu = max(n.z, 0.05);
  float ls = 2.0 * mu0 / (mu0 + mu);

  // texture RGB is sRGB colour albedo (NASA LROC colour mosaic), A is height
  // ^ pow 2.2 to un-sRGB it. colour with a u because NASA's british now apparently
  vec3 albedo = pow(tex.rgb, vec3(2.2));
  vec3 baseRadiance = vec3(0.32 * MOON_BRIGHTNESS);
  baseRadiance *= pow2(3.0 / MOON_SIZE); // bigger moon = dimmer per pixel so it doesn't blind you. 3.0 is the "default size", I think

  vec3 lit = albedo * ls;
  // earthshine: the dark part of the moon glows a tiny bit from light bouncing off EARTH. the earth is a lamp. nature is wild
  float earthshine = 0.0025 * smoothstep(PI * 0.4, PI, phi);
  lit += albedo * earthshine * n.z;

  // blood moon shading. 2.45 / 2.75 / 2.6 / 4.6. these don't quite match umbraR up there and I refuse to find out why
  if (e.lunarPenumbra > 0.0) {
    float d = length(p - e.lunarOffset);
    float umbra = 1.0 - smoothstep(2.45, 2.75, d);
    float penumbra = 1.0 - smoothstep(2.6, 4.6, d);
    vec3 shade = mix(vec3(1.0), vec3(1.0, 0.28, 0.10) * 0.05, umbra);
    shade *= 1.0 - 0.55 * penumbra * (1.0 - umbra);
    lit *= shade;
  }

  return lit * baseRadiance * coverage;
  #endif
}

// soft glow around the moon. extra glowy when it's wet because humidity. I've seen this in real life, I go outside sometimes
vec3 moonGlow(vec3 rayDir, EclipseState e) {
  #ifndef CUSTOM_MOON
  return vec3(0.0);
  #else
  vec3 moonDir = -worldSunDir;
  float angle = acos(clamp(dot(rayDir, moonDir), -1.0, 1.0));
  float r = MOON_ANGULAR_RADIUS;
  if (angle < r || angle > r * 12.0) return vec3(0.0); // only glow in a ring out to 12 moon radii. beyond that it's just sky, bro
  float falloff = exp(-(angle - r) / (r * 1.6));
  float haze = mix(1.0, 3.0, wetness);
  vec3 tint = eclipseMoonlightFactor(e);
  return vec3(0.9, 0.93, 1.0) * falloff * haze * 0.004 * pow2(3.0 / MOON_SIZE) * moonPhaseBrightness() *
         MOON_BRIGHTNESS * tint;
  #endif
}

#endif // CELESTIAL_GLSL

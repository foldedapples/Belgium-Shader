#ifndef STARS_GLSL
#define STARS_GLSL

/*
    stars: Hipparcos Main Catalogue (ESA 1997) to V = 8.0 plus 33 naked-eye
      stars from the Yale Bright Star Catalogue (starCatalogTex)
    milky way: NASA SVS 4851 "Deep Star Maps 2020" (Gaia DR2), galactic
    both built by tools/nasa_night_sky.py

    yes these are the REAL stars. I put a hundred thousand real stars in a block game.
    you will never notice. I will never stop telling people about it.
*/

// these numbers HAVE to match tools/nasa_night_sky.py or the stars turn into confetti. I learned this the hard way. twice. DO NOT FUCKING TOUCH
#define STAR_ROW 1024
#define STAR_LUT_SIZE 256
#define STAR_CELLS 128
#define STAR_T_MIN 2000.0
#define STAR_T_MAX 50000.0
#define STAR_INSERT_RADIUS (0.35 * PI / 180.0)
#define MW_L_MAX 4670.68
#define MW_GAMMA 2.4
#define MW_B0 (20.0 * PI / 180.0)
#define MW_ASINH90 2.20934 // it's asinh(90 / 20). precomputed because GLSL constants hate me

// exposure knobs. 8.5e-7. tiny. the stars were brighter than the sun before I added this
#define STAR_E0 8.5e-7
#define MW_EXPOSURE 8.0e-7
#define MW_PIVOT 1000.0

// which way the sky spins around. sunPathRotation tilts it, then we pick whichever axis the sun is actually orbiting. I think. it picks one
vec3 celestialAxis() {
  float r = radians(sunPathRotation);
  vec3 a1 = vec3(0.0, sin(r), cos(r));
  vec3 a2 = vec3(0.0, -sin(r), cos(r));
  return abs(dot(a1, worldSunDir)) <= abs(dot(a2, worldSunDir)) + 1e-3 ? a1 : a2;
}

// "right ascension" is astronomy for "sky longitude". picks which season's stars you see at midnight. option 4 = actually cycles over a 365 day year, for the 3 people who play that long
float sunRightAscension() {
  #if NIGHT_SKY_SEASON == 1
  float midnightRA = 0.0;
  #elif NIGHT_SKY_SEASON == 2
  float midnightRA = 0.5 * PI;
  #elif NIGHT_SKY_SEASON == 3
  float midnightRA = PI;
  #elif NIGHT_SKY_SEASON == 4
  float yearDay = float(worldDay % 365) + float(worldTime) / 24000.0;
  float midnightRA = 1.5 * PI + 2.0 * PI * yearDay / 365.0;
  #else
  float midnightRA = 1.5 * PI;
  #endif
  return midnightRA - PI;
}

// turns minecraft world directions into real-sky coordinates. it builds a basis and transposes it. transpose = inverse for rotations, a stranger on discord told me and it worked
mat3 worldToEquatorial() {
  vec3 pole = -celestialAxis();
  vec3 s = normalize(worldSunDir - pole * dot(worldSunDir, pole));
  vec3 t = cross(pole, s);
  vec2 cs = sincos(sunRightAscension()).yx; // .yx because sincos gives them in the wrong order for what I wanted. or I wanted the wrong order. whatever
  vec3 xEq = cs.x * s - cs.y * t;
  vec3 yEq = cs.y * s + cs.x * t;
  return transpose(mat3(xEq, yEq, pole));
}

// ICRS -> galactic (Hipparcos Vol. 1); written column by column
// ^ copied digit by digit out of an actual ESA document. ten decimal places. if one is wrong the milky way ends up in the ground
const mat3 equatorialToGalactic = mat3(
  -0.0548755604, 0.4941094279, -0.8676661490,
  -0.8734370902, -0.4448296300, -0.1980763734,
  -0.4838350155, 0.7469822445, 0.4559837762
);

// galactic direction -> uv on the milky way texture. it's warped with asinh so the band in the middle gets more pixels. the python script does the opposite warp, they gotta match
vec2 milkyWayUV(vec3 g, out float b) {
  b = asin(clamp(g.z, -1.0, 1.0));
  float l = atan(g.y, g.x);
  return vec2(fract(0.5 - l / (2.0 * PI)), 0.5 + 0.5 * asinh(b / MW_B0) / MW_ASINH90);
}

// one texture fetch, but clamped so the top and bottom don't bleed. a function this short shouldn't have caused me this much pain
vec3 milkyWayFetch(vec2 uv, float vMin) {
  uv.y = clamp(uv.y, vMin, 1.0 - vMin);
  return textureLod(milkyWayTex, uv, 0.0).rgb;
}

// catmull-rom bicubic filtering in 5 taps instead of 16. it's a famous trick, I copy-pasted it, the weights are cubic polynomials from hell
vec3 milkyWayCatmullRom(vec2 uv, vec2 size, float vMin) {
  vec2 p = uv * size;
  vec2 p1 = floor(p - 0.5) + 0.5;
  vec2 f = p - p1;
  // the four weights. -0.5, 1.5, -2.5. if you change any of them the sky gets a weird grid on it. DO NOT
  vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
  vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
  vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
  vec2 w3 = f * f * (-0.5 + 0.5 * f);
  vec2 w12 = w1 + w2;
  vec2 t0 = (p1 - 1.0) / size;
  vec2 t3 = (p1 + 2.0) / size;
  vec2 t12 = (p1 + w2 / w12) / size;
  // a plus shape of samples. the corners got skipped because they barely matter. corner cutting, literally
  vec3 c =
    milkyWayFetch(vec2(t12.x, t0.y), vMin) * (w12.x * w0.y) +
    milkyWayFetch(vec2(t0.x, t12.y), vMin) * (w0.x * w12.y) +
    milkyWayFetch(t12, vMin) * (w12.x * w12.y) +
    milkyWayFetch(vec2(t3.x, t12.y), vMin) * (w3.x * w12.y) +
    milkyWayFetch(vec2(t12.x, t3.y), vMin) * (w12.x * w3.y);
  float wsum = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
  return max(c / wsum, 0.0); // max 0 because bicubic can overshoot negative and negative light is not a thing. I hope
}

// samples the milky way and picks a filter depending on how zoomed in you are. spyglass users this one's for you
vec3 milkyWayTexture(vec3 g, float pixelAngle) {
  float b;
  vec2 uv = milkyWayUV(g, b);
  vec2 size = vec2(textureSize(milkyWayTex, 0));
  float vMin = 0.5 / size.y;

  // how many texels fit in one pixel. footprint > 1 = zoomed out = shimmer city. < 1 = zoomed in = blurry city
  float stretch = sqrt(1.0 + pow2(b / MW_B0)); // derivative of asinh. I had to look up what a derivative of asinh was. I'm still not sure
  float texelAngle = 2.0 * MW_ASINH90 * MW_B0 * stretch / size.y;
  float footprint = pixelAngle / texelAngle;

  #if MILKY_WAY_FILTER >= 2
  vec3 enc = footprint < 1.25 ? milkyWayCatmullRom(uv, size, vMin) : milkyWayFetch(uv, vMin);
  #else
  vec3 enc = milkyWayFetch(uv, vMin);
  #endif

  // homemade box blur for when the texture is too small or too big. it's the same 4-tap pattern as the moon. I only know one trick
  #if MILKY_WAY_FILTER >= 1
  float minified = smoothstep(1.0, 1.5, footprint);
  float magnified = 1.0 - smoothstep(0.3, 0.7, footprint);
  if (minified + magnified > 0.0) {
    float radius = max(footprint, 1.0) * texelAngle;
    vec2 du = vec2(radius / (2.0 * PI * max(cos(b), 0.05)), 0.0); // divide by cos(latitude) because the texture stretches near the poles. like greenland on a map
    vec2 dv = vec2(0.0, radius * 0.5 / (MW_ASINH90 * MW_B0 * stretch));
    vec3 box = 0.25 * (
      milkyWayFetch(uv + du * 0.375 + dv * 0.125, vMin) +
      milkyWayFetch(uv - du * 0.375 - dv * 0.125, vMin) +
      milkyWayFetch(uv + du * 0.125 - dv * 0.375, vMin) +
      milkyWayFetch(uv - du * 0.125 + dv * 0.375, vMin)
    );
    enc = mix(enc, box, max(minified, magnified));
  }
  #endif
  return pow(enc, vec3(MW_GAMMA)) * MW_L_MAX; // undo the texture's gamma 2.4 and scale back up to real brightness. 4670.68 is from the python script, which got it from the void
}

// color grading for the milky way. three styles: default, "punchy", and "instagram filter"
vec3 milkyWayGrade(vec3 L) {
  float y = max(luminance(L), 1e-6);
  float contrast = MILKY_WAY_CONTRAST;
  float saturation = 1.0;
  #if MILKY_WAY_STYLE == 1
  contrast *= 1.2;
  saturation = 1.25;
  float yb = y * y / (y + 40.0);
  #elif MILKY_WAY_STYLE == 2
  contrast *= 1.12;
  saturation = 1.35;
  float yb = y * y / (y + 20.0);
  #else
  // soft black point, y^2 / (y + 15). the NASA image lifts the super faint stars into a grey fog so this squashes them back down. 15 was the least ugly number
  float yb = y * y / (y + 15.0);
  #endif
  float yc = MW_PIVOT * pow(yb / MW_PIVOT, contrast); // contrast around a pivot point. photoshop does this. I am photoshop now
  #if MILKY_WAY_STYLE == 2
  yc /= 1.0 + yc / (10.0 * MW_PIVOT);
  #endif
  vec3 c = L * (yc / y);
  c = max(mix(vec3(luminance(c)), c, saturation), 0.0);
  // style 2 makes the bright core warm and the dim parts cool. teal and orange. hollywood would be proud
  #if MILKY_WAY_STYLE == 2
  float warm = smoothstep(0.2 * MW_PIVOT, 3.0 * MW_PIVOT, yc);
  c *= mix(vec3(0.94, 0.98, 1.08), vec3(1.06, 1.0, 0.92), warm);
  #endif
  return c;
}

// reads star number i out of the catalog texture. the texture is just a big spreadsheet of stars wearing a texture costume
vec4 starTexel(int i) {
  return texelFetch(starCatalogTex, ivec2(i % STAR_ROW, i / STAR_ROW), 0);
}

// which bucket of the sky this direction lands in. cube map + atan to even out the cells. the 4/PI makes atan go -1..1. trust the math, I don't
int starCell(vec3 d) {
  vec3 a = abs(d);
  int axis = a.x > a.y ? (a.x > a.z ? 0 : 2) : (a.y > a.z ? 1 : 2);
  float major = axis == 0 ? d.x : axis == 1 ? d.y : d.z;
  vec2 uv = vec2(axis == 0 ? d.y : d.x, axis == 2 ? d.y : d.z) / abs(major);
  uv = atan(uv) * (4.0 / PI);
  int face = axis * 2 + (major > 0.0 ? 1 : 0);
  ivec2 cell = clamp(ivec2(floor((uv * 0.5 + 0.5) * float(STAR_CELLS))), ivec2(0), ivec2(STAR_CELLS - 1));
  return (face * STAR_CELLS + cell.y) * STAR_CELLS + cell.x;
}

// twinkle twinkle little star, how I wonder wtf these frequencies are. 3 sine waves per star at random speeds. 1.72 rescales it so it peaks near 1. ish
float scintillation(vec3 h, float t) {
  vec3 freq = mix(vec3(2.1, 3.3, 4.6), vec3(3.1, 5.2, 7.0), h);
  vec3 phase = fract(h.zxy * 7.31 + h.yzx * 3.17) * (2.0 * PI);
  vec3 s = sin(2.0 * PI * freq * t + phase);
  return (0.6 * s.x + 0.45 * s.y + 0.35 * s.z) * 1.72;
}

// draws the real catalog stars as tiny gaussian dots plus a little halo on the bright ones. the main event
vec3 catalogStars(vec3 eq, float pixelAngle, float limitMag, float airmass) {
  // star size is about half a pixel so they stay sharp. the 3.5 and 3.0 keep them inside the lookup radius so they don't get chopped in half
  float sigma = min(0.5 * pixelAngle, STAR_INSERT_RADIUS / 3.5);
  float sigmaHalo = min(1.8 * pixelAngle, STAR_INSERT_RADIUS / 3.0);
  float cutoff = 3.5 * sigma;
  float cutoffHalo = 3.0 * sigmaHalo;
  float norm = 1.0 / (2.0 * PI * sigma * sigma); // gaussian normalization. 1 / (2 pi sigma^2). this one I actually remember from stats class, the only thing I remember from stats class
  float normHalo = 1.0 / (2.0 * PI * sigmaHalo * sigmaHalo);

  #if MILKY_WAY_STYLE == 1
  const float colourSaturation = 0.95;
  #elif MILKY_WAY_STYLE == 2
  const float colourSaturation = 1.0;
  #else
  const float colourSaturation = 0.8;
  #endif

  // stars twinkle more near the horizon because you're looking through more air. airmass^1.5. capped at 0.45 so they don't strobe like a rave
  float twinkle = 0.0;
  float chroma = 0.0;
  #ifdef STAR_TWINKLE
  twinkle = clamp(0.025 * pow(airmass, 1.5), 0.0, 0.45) * STAR_TWINKLE_STRENGTH;
  chroma = smoothstep(4.0, 12.0, airmass);
  #endif

  // look up this cell's list of stars. capped at 64 so a dense cell can't nuke the GPU
  vec4 header = starTexel(STAR_LUT_SIZE + starCell(eq));
  int first = int(header.x);
  int count = min(int(header.y), 64);
  vec3 result = vec3(0.0);
  for (int k = 0; k < count; k++) {
    vec4 s = starTexel(first + k);
    uint bits = uint(s.w);
    float mag = float(bits >> 8u) / 256.0 - 2.0; // magnitude is smuggled in the top bits of a float. bit packing. I feel like a hacker in a movie
    if (mag > limitMag + 0.75) break; // stars are sorted brightest first so once they get too dim we can bail. sorting: it's actually useful??

    float d = length(eq - s.xyz);
    if (d > max(cutoff, cutoffHalo)) continue;

    // magnitude to energy. 1.328771 = log2(100) / 5. because 5 magnitudes = 100x dimmer. astronomers chose this in like 150 BC and we're stuck with it
    float energy = STAR_E0 * exp2(-1.328771 * mag);
    energy *= (1.0 - smoothstep(limitMag - 0.75, limitMag + 0.75, mag));
    if (STAR_DENSITY > 1.0) {
      energy *= pow(STAR_DENSITY, clamp((mag - 4.0) / 4.0, 0.0, 1.0));
    }

    float profile = d < cutoff ? norm * exp(-0.5 * pow2(d / sigma)) : 0.0;
    float haloWeight = 0.05 * STAR_BLOOM * (1.0 - smoothstep(-1.0, 2.0, mag));
    profile += haloWeight * normHalo * exp(-0.5 * pow2(d / sigmaHalo));

    vec3 colour = starTexel(int(bits & 255u)).rgb; // bottom 8 bits = which temperature color. the first 256 texels are a color lookup. it's spreadsheets all the way down
    colour = mix(vec3(luminance(colour)), colour, colourSaturation);

    vec3 tw = vec3(1.0);
    #ifdef STAR_TWINKLE
    vec3 h = hash33(s.xyz * 4096.0);
    float n = scintillation(h, frameTimeCounter);
    float m = scintillation(h.yzx, frameTimeCounter * 1.3);
    tw = max(vec3(1.0) + twinkle * (n + chroma * vec3(m, 0.0, -m)), 0.0); // red and blue twinkle opposite each other near the horizon. real stars do this. I watched sirius for 20 minutes to confirm
    #endif

    result += colour * energy * profile * tw;
  }
  return min(result, vec3(1.5e4)); // clamp because sirius at 1 pixel was producing fireflies. 1.5e4, big but not infinity
}

// the whole night sky. figures out how many stars you can see given the sun, moon, aurora and eclipses, then draws stars + milky way
vec3 nightSky(vec3 worldDir, float aurora, float eclipseTotality, out vec3 stars) {
  stars = vec3(0.0);
  if (worldDir.y < -0.01) return vec3(0.0); // no stars underground. obviously

  // limiting magnitude = dimmest star you can see. -3 in daylight, 8.5 in perfect darkness. -18 degrees = astronomical twilight, a real term I didn't make up
  float sunAltitude = degrees(asin(clamp(worldSunDir.y, -1.0, 1.0)));
  float limitMag = mix(-3.0, 8.5, 1.0 - smoothstep(-18.0, 2.0, sunAltitude));
  limitMag = max(limitMag, mix(-3.0, 2.5, eclipseTotality)); // during a total eclipse you can see bright stars in the DAY. sick
  float moonUp = smoothstep(-0.05, 0.15, -worldSunDir.y);
  float moonlight = moonUp * moonPhaseBrightness();
  limitMag -= 1.8 * moonlight + 1.0 * aurora; // full moon and auroras drown out the dim stars. light pollution but make it nature
  limitMag = min(limitMag, 4.5 + 4.0 * min(STAR_DENSITY, 1.0));
  bool starsVisible = limitMag >= -2.5;

  float milkyWayVisibility = (1.0 - smoothstep(-17.0, -8.0, sunAltitude)) * (1.0 - 0.7 * moonlight) * (1.0 - 0.3 * aurora);

  if (!starsVisible && milkyWayVisibility <= 0.0) return vec3(0.0);

  vec3 eq = worldToEquatorial() * worldDir;
  float pixelAngle = clamp(2.0 / (gbufferProjection[1][1] * viewHeight), 3e-5, 1e-2);
  float airmass = 1.0 / max(worldDir.y + 0.025, 0.025); // how much atmosphere you're looking through. 1/height-ish. the 0.025 stops it going to infinity at the horizon and setting my pc on fire
  float horizon = smoothstep(-0.01, 0.035, worldDir.y);

  #ifdef REALISTIC_STARS
  if (starsVisible) {
    stars = catalogStars(eq, pixelAngle, limitMag, airmass) * (STAR_BRIGHTNESS * horizon);
  }
  #endif

  vec3 milkyWay = vec3(0.0);
  #ifdef MILKY_WAY
  if (milkyWayVisibility > 0.0) {
    vec3 g = equatorialToGalactic * eq;
    milkyWay = milkyWayGrade(milkyWayTexture(g, pixelAngle)) * (MW_EXPOSURE * MILKY_WAY_INTENSITY * milkyWayVisibility * horizon);
  }
  #endif
  return milkyWay;
}

// ---- below here is the FAKE procedural star stuff, used by the End sky. the budget version ----

const vec3 galacticNormal = vec3(0.42, 0.57, 0.705); // fake galaxy tilt. not real. not even close. nobody in the End is checking

// gaussian band around the fake galaxy plane. 0.018 = thickness. tuned by staring
float galacticBand(vec3 c) {
  float b = dot(c, galacticNormal);
  return exp(-b * b / 0.018);
}

// fake star colors: red -> yellow -> white -> blue. like real stars but without the 10-digit blackbody nonsense
vec3 starColor(float t) {
  vec3 red = vec3(1.0, 0.72, 0.55);
  vec3 yellow = vec3(1.0, 0.93, 0.82);
  vec3 white = vec3(1.0, 1.0, 1.0);
  vec3 blue = vec3(0.78, 0.86, 1.0);
  return t < 0.3
    ? mix(red, yellow, t / 0.3)
    : t < 0.7
      ? mix(yellow, white, (t - 0.3) / 0.4)
      : mix(white, blue, (t - 0.7) / 0.3);
}

// one layer of random stars: grid the sky, maybe put a star in each cell, check the 3x3 neighbors so stars near cell edges don't get cut off
vec3 starLayer(
  vec3 c,
  float cells,
  float probability,
  float brightness,
  float pixelAngle,
  float twinkleAmount
) {
  // cube face picking. again. this is the third time in this folder. I should make a function. I won't
  vec3 a = abs(c);
  int axis = a.x > a.y ? (a.x > a.z ? 0 : 2) : (a.y > a.z ? 1 : 2);
  float major = axis == 0 ? c.x : axis == 1 ? c.y : c.z;
  vec2 uv = (axis == 0 ? c.yz : axis == 1 ? c.xz : c.xy) / abs(major);
  float faceId = float(axis) * 2.0 + (major > 0.0 ? 1.0 : 0.0);

  vec2 g = (uv * 0.5 + 0.5) * cells;
  vec2 base = floor(g);
  float radius = pixelAngle * 0.75;
  float cutoff = radius * 2.6;
  vec3 result = vec3(0.0);

  // 3x3 neighbor loop. 9 cells. every pixel. for tiny dots. worth it
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = base + vec2(i, j);
      if (any(lessThan(cell, vec2(0.0))) || any(greaterThanEqual(cell, vec2(cells)))) continue;
      // 37 and 91 are random primes I picked so the hashes don't collide. are they doing anything? emotionally, yes
      vec3 h = hash33(vec3(cell, faceId * 37.0 + cells));
      vec2 spot = (cell + 0.1 + 0.8 * hash33(vec3(cell, faceId + 91.0)).xy) / cells * 2.0 - 1.0;
      vec3 sp = axis == 0 ? vec3(sign(major), spot) : axis == 1 ? vec3(spot.x, sign(major), spot.y) : vec3(spot, sign(major));
      vec3 starPos = normalize(sp);
      float bandBoost = 1.0 + 1.5 * galacticBand(starPos);
      if (h.x > probability * bandBoost) continue;

      float angle = acos(clamp(dot(c, starPos), -1.0, 1.0));
      if (angle > cutoff) continue;
      float gauss = exp(-pow2(angle / radius));

      float mag = pow(h.y, 6.0); // pow 6 = most stars dim, a few bright ones. like a youtube comment section
      float twinkle = 1.0;
      if (twinkleAmount > 0.0) {
        float phase = h.z * 100.0;
        // three sines added together = fake twinkle. 7.3, 11.9, 3.1. random-ish so it doesn't look like a metronome
        float n =
          sin(frameTimeCounter * 7.3 + phase) * 0.5 +
          sin(frameTimeCounter * 11.9 + phase * 1.7) * 0.3 +
          sin(frameTimeCounter * 3.1 + phase * 2.3) * 0.2;
        twinkle = 1.0 + n * twinkleAmount * (0.6 + 0.4 * mag);
      }
      result += starColor(h.z) * gauss * mag * brightness * twinkle;
    }
  }
  return result;
}

#endif // STARS_GLSL

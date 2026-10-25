// interactive water sim. boats make wakes, you make splashes. this file is held together with duct tape and prayers
#ifndef WATER_SIM_GLSL
#define WATER_SIM_GLSL

// quality presets. CPB = cells per block. N = grid size. HZ = how many sim steps per second
#if WATER_SIM_QUALITY == 1 // Balanced: ~43 blocks across, 30 Hz, for the potato gang
  #define WS_CPB 6
  #define WS_N 256
  #define WS_HZ 30.0
#elif WATER_SIM_QUALITY == 3 // Ultra: ~102 blocks, finer grid, rip your fps
  #define WS_CPB 10
  #define WS_N 1024
  #define WS_HZ 60.0
#elif WATER_SIM_QUALITY == 4 // Cinematic: ~170 blocks (whole boat trails), finest grid. this one made my laptop scream
  #define WS_CPB 12
  #define WS_N 2048
  #define WS_HZ 60.0
#else // High (default): 64 blocks. the "normal" one
  #define WS_CPB 8
  #define WS_N 512
  #define WS_HZ 60.0
#endif

// max 3 sim steps per frame so a lag spike doesn't make the water explode into the sky
#define WS_MAX_STEPS 3
#define WS_MAGIC 0x48414C43 // spells "HALC" in hex, means the SSBO got initialized. yes I spent 20 minutes on an ascii table for this

// physics constants. I tweaked these for like 3 days. if you touch them the water turns into jello
const float WS_WAVE_SPEED = 2.7;
// spring pulls the water back flat. 11 because 10 felt floppy
const float WS_SPRING = 11.0;
const float WS_DAMPING = 0.15;
// viscosity makes it gooey. 0.004. any higher and it's honey
const float WS_VISCOSITY = 0.004;
// sponge = soaks up waves at the edges so they don't bounce off an invisible wall
const float WS_SPONGE = 0.12;
// hard limits on height and speed because without these the sim goes to infinity in about 2 seconds. ask me how I know
const float WS_H_LIMIT = 0.35;
const float WS_V_LIMIT = 4.0;
const float WS_IDLE_TIME = 20.0;

// boat size in blocks. I measured an actual minecraft boat with F3. dedication
const float BOAT_HALF_LENGTH = 0.80;
const float BOAT_HALF_WIDTH = 0.42;

#define WS_BOAT_ENTITY_ID 2 // the boat's id from entity.properties. if you change it there and not here, no wakes for you

// what's disturbing the water: nothing, swimming, a boat hull, or a big splash
#define WS_SRC_OFF 0
#define WS_SRC_SWIM 1
#define WS_SRC_HULL 2
#define WS_SRC_IMPULSE 3

// the SSBO. shared memory between the compute shader and everything else. binding 3 because 0-2 were taken I guess
layout(std430, binding = 3) buffer waterSimData {
  ivec4 wsCenter;
  ivec4 wsStep; // x: image read by this frame's first step, y: steps this frame, z: clear on the first step, w: active. FOUR jobs in one ivec4, I'm a genius or an idiot
  ivec4 wsPrevWindow;
  ivec4 wsPlayerI;
  vec4 wsPlayerF;
  ivec4 wsBoatI;
  vec4 wsBoatF;
  vec4 wsSrcPos[3];
  vec4 wsSrcDir[3];
  vec4 wsMisc;
  vec4 wsSplash;
  ivec4 wsSplashCell;
};

// wrap the cell into the texture with a bitmask. only works because N is a power of 2. learned this from a 2009 forum post
ivec2 wsTexel(ivec2 cell) {
  return cell & ivec2(WS_N - 1);
}

// is this cell inside the sim window? returns yes/no. one of the few functions here I understand completely
bool wsInWindow(ivec2 cell, ivec2 center) {
  ivec2 r = cell - center;
  return all(greaterThanEqual(r, ivec2(-WS_N / 2))) && all(lessThan(r, ivec2(WS_N / 2)));
}

// smoothstep but I wrote it myself, because... I don't remember why. pride?
float wsSmooth(float a, float b, float x) {
  float t = clamp((x - a) / (b - a), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

// everything below is for non-compute shaders. compute shaders don't get to read these. sorry compute shaders
#ifndef csh
uniform sampler2D waterSimTexA;
uniform sampler2D waterSimTexB;

// read the water height at a cell, blending last frame and this frame so it doesn't stutter at 30hz
float wsHeightAt(ivec2 rel) {
  if (any(lessThan(rel, ivec2(-WS_N / 2))) || any(greaterThanEqual(rel, ivec2(WS_N / 2)))) return 0.0;
  ivec2 cell = wsCenter.xy + rel;
  ivec2 t = wsTexel(cell);
  // ping-pong textures. A and B take turns. it's like a seesaw but for data
  float latest = wsCenter.z == 0 ? texelFetch(waterSimTexA, t, 0).r : texelFetch(waterSimTexB, t, 0).r;
  float older = latest;
  // wsMisc.w >= 2.0 means... something. there's a reason. it was a good reason. I was there
  if (wsMisc.w >= 2.0 || (wsMisc.w > 0.5 && wsInWindow(cell, wsPrevWindow.xy))) {
    older = wsCenter.z == 0 ? texelFetch(waterSimTexB, t, 0).r : texelFetch(waterSimTexA, t, 0).r;
  }
  return mix(older, latest, wsMisc.z);
}

// cubic b-spline interpolation, 16 samples. gives height AND slope at once. these weights came from wikipedia and I did NOT derive them
vec3 wsBSpline(vec2 p) {
  p -= 0.5;
  vec2 i = floor(p);
  vec2 f = p - i;
  vec2 f2 = f * f;
  vec2 f3 = f2 * f;
  vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
  vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
  vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
  vec2 w3 = f3 / 6.0;
  // derivative weights for the slope. calculus I last saw in high school, now living in my shader
  vec2 d0 = (-1.0 + 2.0 * f - f2) * 0.5;
  vec2 d1 = (-4.0 * f + 3.0 * f2) * 0.5;
  vec2 d2 = (1.0 + 2.0 * f - 3.0 * f2) * 0.5;
  vec2 d3 = f2 * 0.5;
  float wx[4] = float[4](w0.x, w1.x, w2.x, w3.x);
  float wy[4] = float[4](w0.y, w1.y, w2.y, w3.y);
  float dx[4] = float[4](d0.x, d1.x, d2.x, d3.x);
  float dy[4] = float[4](d0.y, d1.y, d2.y, d3.y);
  ivec2 c = ivec2(i) - 1;
  vec3 result = vec3(0.0);
  // 4x4 loop. 16 texture reads per pixel. my gpu hates me
  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      float h = wsHeightAt(c + ivec2(x, y));
      result += h * vec3(wx[x] * wy[y], dx[x] * wy[y], wx[x] * dy[y]);
    }
  }
  return result;
}

// cheap bilinear version for when we just need height and not the slope. budget mode
float wsHeightBilinear(vec2 p) {
  p -= 0.5;
  vec2 i = floor(p);
  vec2 f = p - i;
  ivec2 c = ivec2(i);
  float h00 = wsHeightAt(c);
  float h10 = wsHeightAt(c + ivec2(1, 0));
  float h01 = wsHeightAt(c + ivec2(0, 1));
  float h11 = wsHeightAt(c + ivec2(1, 1));
  return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
}

// the slope of the sim water at a world position. this is what actually makes the ripples show up
vec2 waterSimSlope(vec3 feetPlayerPos) {
  float weight = wsMisc.y * WATER_SIM_STRENGTH;
  // if the magic number isn't there the SSBO is garbage so we bail. this saved me from SO many black screens
  if (wsCenter.w != WS_MAGIC || weight <= 0.0) return vec2(0.0);
  ivec2 base = cameraPositionInt.xz * WS_CPB - wsCenter.xy;
  vec2 p = vec2(base) + (cameraPositionFract.xz + feetPlayerPos.xz) * float(WS_CPB);
  // fade out near the edge of the sim window (0.70 to 0.86) so there's no hard line in the water
  float edge = max(abs(p.x), abs(p.y)) / float(WS_N / 2);
  weight *= 1.0 - wsSmooth(0.70, 0.86, edge);
  if (weight <= 0.0) return vec2(0.0);
  vec2 slope = wsBSpline(p).yz * float(WS_CPB) * weight;
  float len = length(slope);
  // cap the slope at 0.8 or the normals flip and the water looks like broken glass
  return len > 0.8 ? slope * (0.8 / len) : slope;
}

// sim water height for vertex displacement or whatever wants it
float waterSimHeight(vec3 feetPlayerPos) {
  if (wsCenter.w != WS_MAGIC || wsMisc.y <= 0.0) return 0.0;
  ivec2 base = cameraPositionInt.xz * WS_CPB - wsCenter.xy;
  vec2 p = vec2(base) + (cameraPositionFract.xz + feetPlayerPos.xz) * float(WS_CPB);
  return wsHeightBilinear(p);
}
#endif

#endif // WATER_SIM_GLSL

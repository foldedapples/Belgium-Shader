
// INTERACTIVE WATER. ripples when you swim, splashes when you jump in, wakes behind boats. this is the most ambitious thing in the pack and I barely survived it
#include "/lib/common.glsl"
#include "/lib/water/waterSim.glsl"

// uniforms that only this file cares about. vehicleLookVector is for the boat. yes the boat gets its own uniforms. the boat is important
uniform bool feetInWater;
uniform bool isRiding;
uniform bool vehicleInWater;
uniform int vehicleId;
uniform vec3 vehicleLookVector;
uniform vec3 relativeVehiclePosition;

// CONTROL pass: one single thread that does the bookkeeping. where's the player, are they wet, did they jump in, is there a boat. basically a babysitter for the simulation
#ifdef WATER_SIM_CONTROL

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

// split a position into an integer block part and a fractional part so we don't lose precision 30 million blocks from spawn. floats get wobbly far out. farlands flashbacks
void wsSplit(vec3 relToCamera, out ivec3 i, out vec3 f) {
  vec3 p = cameraPositionFract + relToCamera;
  vec3 fl = floor(p);
  i = cameraPositionInt + ivec3(fl);
  f = p - fl;
}

vec3 wsDelta(ivec3 i, vec3 f, ivec3 pi, vec3 pf) { // how far something moved, int part and fraction part separately. precision paranoia
  return vec3(i - pi) + (f - pf);
}

vec2 wsSourcePos(ivec3 i, vec3 f, ivec2 center) { // world position -> sim grid cell coords. WS_CPB = cells per block, I think. the naming in this file is a word search puzzle
  return vec2(i.xz * WS_CPB - center) + f.xz * float(WS_CPB);
}

void main() {
  // WS_MAGIC: a secret number we write when the sim is set up. if it's not there, this is the first frame. it's like a "you were here" carved into a tree
  bool init = wsCenter.w != WS_MAGIC;
  float ft = clamp(frameTime, 1e-4, 0.25); // clamp frame time so a lag spike doesn't launch the water into space. 0.25 max. it launched. once

  ivec3 pI;
  vec3 pF;
  wsSplit(-relativeEyePosition, pI, pF);
  vec3 pDelta = init ? vec3(0.0) : wsDelta(pI, pF, wsPlayerI.xyz, wsPlayerF.xyz);
  bool teleport = length(pDelta) > 12.0; // moved more than 12 blocks in one frame = teleported (or ender pearl). reset everything
  vec3 pVel = teleport ? vec3(0.0) : pDelta / ft;

  bool playerIn = feetInWater && !isRiding;
  bool playerWet = (feetInWater || isEyeInWater == 1) && !isRiding; // isEyeInWater == 1 means head underwater. 2 is lava. 3 is powder snow. magic numbers from mojang, as usual
  bool wasIn = !init && wsPlayerI.w != 0;

  // boat detection. riding + boat entity ID + in water. if you ride a pig into the ocean it doesn't count. pigs don't make wakes, sorry
  bool boat = isRiding && vehicleId == WS_BOAT_ENTITY_ID && (vehicleInWater || feetInWater);
  ivec3 bI;
  vec3 bF;
  wsSplit(-relativeVehiclePosition, bI, bF);
  bool hadBoat = !init && wsBoatI.w != 0;
  vec3 bVel = vec3(0.0);
  if (boat && hadBoat) {
    vec3 d = wsDelta(bI, bF, wsBoatI.xyz, wsBoatF.xyz);
    if (length(d) < 12.0) bVel = d / ft;
  }

  // idle timer: nobody touching the water for a while? put the sim to sleep and save fps. water naps. the water is just like me
  bool contact = playerWet || boat;
  float idle = init ? WS_IDLE_TIME : wsBoatF.w;
  idle = contact ? 0.0 : min(idle + ft, 1e4);
  bool simAwake = idle < WS_IDLE_TIME;
  bool wasAwake = !init && wsStep.w != 0;
  bool clear = init || teleport || (simAwake && !wasAwake);

  // fixed timestep with an accumulator. the sim runs at WS_HZ no matter what your framerate is. I read "fix your timestep" like 4 times and it finally clicked on the 5th
  const float dt = 1.0 / WS_HZ;
  float acc = (init || !simAwake) ? 0.0 : wsPlayerF.w;
  int steps = 0;
  if (simAwake) {
    acc += ft;
    steps = min(int(acc / dt), WS_MAX_STEPS); // cap steps per frame so a lag spike doesn't trigger a spiral of death. that's the real name. "spiral of death". graphics programmers are dramatic
    acc -= float(steps) * dt;
    acc = min(acc, dt);
    if (clear) steps = max(steps, 1);
  }

  ivec2 center = pI.xz * WS_CPB + ivec2(floor(pF.xz * float(WS_CPB))); // the window center follows the player. the sim only exists around you. the rest of the ocean is a lie

  // shift the window, flip the ping-pong buffer, advance the sim clock (wraps at 600 so the float doesn't get huge and shitty)
  if (steps > 0) {
    wsPrevWindow.xy = init ? center : wsCenter.xy;
    wsStep.x = init ? 0 : wsCenter.z;
    wsCenter.xy = center;
    wsCenter.z = (wsStep.x + steps) & 1;
    wsMisc.x = mod((init ? 0.0 : wsMisc.x) + float(steps) * dt, 600.0);
    wsMisc.w = clear ? -1.0 : float(steps);
  }
  wsMisc.z = clamp(acc / dt, 0.0, 1.0);
  wsStep.y = steps;
  wsStep.z = clear ? 1 : 0;
  wsStep.w = simAwake ? 1 : 0;

  // sources = things that poke the water. 0 = swimming player, 1 = splash impulse, 2 = boat hull. three slots. three!! if you add a 4th everything explodes
  ivec2 srcCenter = steps > 0 ? center : wsCenter.xy;
  bool impulseUsed = !init && wsSrcDir[1].w > 0.5;
  float impulseStrength = (init || impulseUsed || teleport) ? 0.0 : wsSrcPos[1].w;
  float impulseRadius = wsSrcPos[1].z;
  bool impulseFixed = !impulseUsed && !init && wsSrcDir[1].x > 0.5;
  vec2 impulsePos = wsSrcPos[1].xy;
  for (int s = 0; s < 3; s++) {
    wsSrcPos[s] = vec4(0.0);
    wsSrcDir[s] = vec4(0.0);
  }

  if (playerIn && !teleport) { // swimming: a little disc of force where you are. 0.38 radius. tuned by swimming in circles for half an hour
    float speed = length(pVel.xz);
    wsSrcPos[0] = vec4(wsSourcePos(pI, pF, srcCenter), 0.38, PLAYER_RIPPLE_STRENGTH);
    wsSrcDir[0] = vec4(0.0, 0.0, float(WS_SRC_SWIM), speed);
  }

  if (init || teleport) {
    wsSplash = vec4(0.0);
    wsSplashCell = ivec4(0);
    impulseFixed = false;
  }
  // splash logic. falling into water fast (velocity y below -1.5) = big splash. strength = sqrt of falling speed because linear looked ridiculous at high speeds. 30 cap so falling from build limit doesn't nuke the ocean
  if (!teleport && !init) {
    if (playerWet && !wasIn && pVel.y < -1.5) {
      float s = 1.15 * sqrt(min(-pVel.y, 30.0)) * PLAYER_RIPPLE_STRENGTH;
      float a = min(s, 3.6);
      impulseStrength = max(impulseStrength, a);
      impulseRadius = 0.42 * clamp(sqrt(s / max(a, 1e-3)), 1.0, 1.6);
      impulseFixed = false;
      // delayed splash: the water rebounds a moment later. 0.35, 0.35, 0.25 are timing and size numbers from pure trial and error, mostly error
      wsSplash = vec4(0.35 * a, 0.35, 0.25, 0.0);
      wsSplashCell = ivec4(pI.xz * WS_CPB + ivec2(floor(pF.xz * float(WS_CPB))), 0, 0);
    } else if (!playerWet && wasIn && !isRiding && pVel.y > 0.5) { // jumping OUT of water makes a small plop too
      impulseStrength = max(impulseStrength, 1.0 * PLAYER_RIPPLE_STRENGTH);
      impulseRadius = 0.42;
      impulseFixed = false;
    }
    // after the delay runs out, fire the rebound splash at the saved spot. took me 3 days to realize splashes need a memory
    if (wsSplash.x > 0.0) {
      wsSplash.y -= ft;
      if (wsSplash.y <= 0.0 && impulseStrength <= 0.0) {
        impulseStrength = wsSplash.x;
        impulseRadius = wsSplash.z;
        impulseFixed = true;
        impulsePos = vec2(wsSplashCell.xy - srcCenter) + 0.5;
        wsSplash.x = 0.0;
      }
    }
  }
  if (impulseStrength > 0.0) {
    vec2 pos = impulseFixed ? impulsePos : wsSourcePos(pI, pF, srcCenter);
    wsSrcPos[1] = vec4(pos, impulseRadius, impulseStrength);
    wsSrcDir[1] = vec4(impulseFixed ? 1.0 : 0.0, 0.0, float(WS_SRC_IMPULSE), steps > 0 ? 1.0 : 0.0);
  }

  if (boat) {
    // boat wake. find the forward direction, flip it if we're going backwards (dot < -0.5), cap speed at 12. if you go faster than 12 in a boat you're on ice and should stop
    vec2 fwd = vehicleLookVector.xz;
    fwd = dot(fwd, fwd) > 1e-6 ? normalize(fwd) : vec2(1.0, 0.0);
    float speed = length(bVel.xz);
    if (dot(bVel.xz, fwd) < -0.5) fwd = -fwd;
    wsSrcPos[2] = vec4(wsSourcePos(bI, bF, srcCenter), 0.0, BOAT_WAKE_STRENGTH);
    wsSrcDir[2] = vec4(fwd, float(WS_SRC_HULL), min(speed, 12.0));
  }

  wsMisc.y = simAwake ? 1.0 - wsSmooth(WS_IDLE_TIME * 0.6, WS_IDLE_TIME, idle) : 0.0; // fade the sim out smoothly as it falls asleep instead of the ripples vanishing instantly. that looked like a glitch. because it was

  // save everything for next frame. the fourth components get crammed with random unrelated stuff (wet flag, accumulator, boat flag, idle timer) because we ran out of room. it's a junk drawer
  wsPlayerI = ivec4(pI, playerWet ? 1 : 0);
  wsPlayerF = vec4(pF, acc);
  wsBoatI = ivec4(bI, boat ? 1 : 0);
  wsBoatF = vec4(bF, idle);
  wsCenter.w = WS_MAGIC;
}

#endif // WATER_SIM_CONTROL is over. the babysitter clocks out

// STEP pass: the actual wave simulation. one thread per water cell. this is where the physics lives. physics I don't understand but physics nonetheless
#ifdef WATER_SIM_STEP

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
// bigger quality = bigger grid. 16, 32, 64, 128 groups of 16x16. quality 4 = 2048x2048 cells, rest in peace your GPU
#if WATER_SIM_QUALITY == 1
const ivec3 workGroups = ivec3(16, 16, 1);
#elif WATER_SIM_QUALITY == 3
const ivec3 workGroups = ivec3(64, 64, 1);
#elif WATER_SIM_QUALITY == 4
const ivec3 workGroups = ivec3(128, 128, 1);
#else
const ivec3 workGroups = ivec3(32, 32, 1);
#endif

// two buffers, ping pong. read one, write the other. rg = height and velocity
layout(rg16f) uniform image2D waterSimA;
layout(rg16f) uniform image2D waterSimB;

bool readA;
bool firstStep;
ivec2 winCenter;

// read a cell. outside the window = calm water (0). first step after the window moved = don't read stale garbage from the old spot
vec2 wsLoad(ivec2 cell) {
  if (!wsInWindow(cell, winCenter)) return vec2(0.0);
  if (firstStep && (wsStep.z != 0 || !wsInWindow(cell, wsPrevWindow.xy))) return vec2(0.0);
  ivec2 t = wsTexel(cell);
  return readA ? imageLoad(waterSimA, t).rg : imageLoad(waterSimB, t).rg;
}

float wsDisc(vec2 d, float radius) { // a soft round blob, gaussian falloff. cuts off at r2 > 4 so we don't compute tiny useless numbers
  float r2 = dot(d, d) / (radius * radius);
  return r2 < 4.0 ? exp(-2.0 * r2) : 0.0;
}

// splash shape: a dip in the middle with a little ring around it at r = 1.3. 0.241 makes the ring balance out the dip so water isn't created or destroyed. conservation of mass, baby. I googled that
float wsSplashShape(vec2 d, float radius) {
  float r = length(d) / radius;
  if (r > 3.0) return 0.0;
  return -exp(-2.0 * r * r) + 0.241 * exp(-pow2((r - 1.3) / 0.45));
}

// add up all the forces from every source on this cell
void wsSources(vec2 cellPos, out float force, out float impulse) {
  force = 0.0;
  impulse = 0.0;
  for (int s = 0; s < 3; s++) {
    int type = int(wsSrcDir[s].z + 0.5);
    if (type == WS_SRC_OFF) continue;
    vec2 d = (cellPos - wsSrcPos[s].xy) / float(WS_CPB); // skip far away sources, 3 blocks out (9 = 3 squared). optimization! I know one!
    if (dot(d, d) > 9.0) continue;
    float speed = wsSrcDir[s].w;
    if (type == WS_SRC_SWIM) {
      // swim stroke: force pulses with a sin wave at 3.1 Hz so it feels like arms paddling. 6.2831853 is 2*PI typed out by hand because I didn't trust the PI define for some reason
      float moving = wsSmooth(0.25, 1.2, speed) * min(speed, 6.0) / 6.0;
      float stroke = 0.55 + 0.45 * sin(wsMisc.x * 6.2831853 * 3.1);
      force -= wsDisc(d, wsSrcPos[s].z) * moving * stroke * 26.0 * wsSrcPos[s].w;
    // boat hull: a squashed blob in the boat's local coords (a = along, b = sideways). the hull pushes water down, the bow pushes it up into a wave at 0.85 along. all the numbers here were tuned in a boat at 2am
    } else if (type == WS_SRC_HULL) {
      vec2 fwd = wsSrcDir[s].xy;
      float a = dot(d, fwd) / BOAT_HALF_LENGTH;
      float b = (-d.x * fwd.y + d.y * fwd.x) / BOAT_HALF_WIDTH;
      float hull = clamp(1.0 - a * a, 0.0, 1.0) * exp(-b * b * 1.6);
      float bow = exp(-pow2(a - 0.85) * 9.0 - b * b * 2.2);
      float sp = clamp(speed / 8.0, 0.0, 1.0);
      force += wsSmooth(0.15, 1.2, speed) * wsSrcPos[s].w * (-hull * (0.55 + 1.1 * sp) + bow * 1.6 * sp * sp) * 9.0; // the giant boat formula. it works. I'm scared of it. DO NOT FUCKING TOUCH
    } else if (type == WS_SRC_IMPULSE && firstStep) {
      impulse += wsSplashShape(d, wsSrcPos[s].z) * wsSrcPos[s].w;
    }
  }
}

// main: do one sim step. bail if this step number isn't needed this frame
void main() {
  if (WATER_SIM_STEP >= wsStep.y) return;
  ivec2 t = ivec2(gl_GlobalInvocationID.xy);
  if (any(greaterThanEqual(t, ivec2(WS_N)))) return;

  firstStep = WATER_SIM_STEP == 0;
  readA = ((wsStep.x + WATER_SIM_STEP) & 1) == 0;
  winCenter = wsCenter.xy;

  ivec2 lo = winCenter - WS_N / 2; // the grid wraps around (toroidal, fancy word), wsTexel does the wrapping. so the sim can scroll without copying anything. stole this idea and I'd do it again
  ivec2 cell = lo + wsTexel(t - lo);
  ivec2 r = cell - winCenter;

  // read the cell and all 8 neighbors. compass directions. this is the most organized I've ever been about anything
  vec2 c = wsLoad(cell);
  vec2 e = wsLoad(cell + ivec2(1, 0));
  vec2 w = wsLoad(cell - ivec2(1, 0));
  vec2 n = wsLoad(cell + ivec2(0, 1));
  vec2 s = wsLoad(cell - ivec2(0, 1));
  vec2 ne = wsLoad(cell + ivec2(1, 1));
  vec2 nw = wsLoad(cell + ivec2(-1, 1));
  vec2 se = wsLoad(cell + ivec2(1, -1));
  vec2 sw = wsLoad(cell + ivec2(-1, -1));

  // the constants: dt, wave speed squared (scaled to grid units), viscosity. c2 is c squared not "c, but the second one". took me an embarrassingly long time
  const float dt = 1.0 / WS_HZ;
  const float c2 = WS_WAVE_SPEED * WS_WAVE_SPEED * float(WS_CPB * WS_CPB);
  const float nu = WS_VISCOSITY * float(WS_CPB * WS_CPB);
  // isotropic 9-point laplacian (Patra & Karttunen 2006), 5-point makes... makes what?? the sentence just ends. past me got distracted. I think 5-point makes the ripples come out square. square ripples. horrifying
  vec2 orth = e + w + n + s;
  vec2 diag = ne + nw + se + sw;
  vec2 lap = (4.0 * orth + diag - 20.0 * c) / 6.0; // 4 * orthogonal + diagonal - 20 * center, over 6. the magic laplacian recipe. a laplacian measures how different you are from your neighbors. relatable
  float lapH = lap.x;
  float lapV = lap.y;

  float force, impulse;
  wsSources(vec2(r) + 0.5, force, impulse); // +0.5 = cell center

  // sponge layer near the edges of the window soaks up waves so they don't bounce off the invisible wall and come back to haunt you
  float edge = (max(abs(float(r.x) + 0.5), abs(float(r.y) + 0.5))) / float(WS_N / 2);
  float sponge = wsSmooth(1.0 - WS_SPONGE, 1.0, edge);

  float h = c.x;
  float v = c.y;
  // THE WAVE EQUATION. velocity += (wave pull + spring back to flat + viscosity + forces) * dt. then height += velocity * dt. "semi-implicit euler" is what reddit called it
  v += dt * (c2 * lapH - WS_SPRING * WS_SPRING * h + nu * lapV + force) + impulse;
  v *= exp(-(WS_DAMPING + 15.0 * sponge) * dt); // damping, plus heavy extra damping in the sponge. 15.0 and 5.0 are "make it stop" constants
  h += dt * v;
  h *= exp(-5.0 * sponge * dt);

  // clamp so things can't blow up, and if they blew up anyway (NaN), reset to calm. the water has exploded before. I've seen things
  h = clamp(h, -WS_H_LIMIT, WS_H_LIMIT);
  v = clamp(v, -WS_V_LIMIT, WS_V_LIMIT);
  if (isnan(h) || isinf(h) || isnan(v) || isinf(v)) {
    h = 0.0;
    v = 0.0;
  }

  if (readA) imageStore(waterSimB, t, vec4(h, v, 0.0, 0.0)); // write to whichever buffer we're NOT reading. ping pong!
  else imageStore(waterSimA, t, vec4(h, v, 0.0, 0.0));
}

#endif // WATER_SIM_STEP over. the water lives to ripple another day

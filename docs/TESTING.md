# In-Game Test Plan

These tests need a machine with Minecraft + Iris. None have been run yet. Record results
(pass / fail + screenshot + `logs/latest.log` excerpt) per milestone.

## 0. Load

1. Install Iris (≥ 1.10.4 recommended). Copy `Belgium Shaders` (folder or release ZIP) into
   `.minecraft/shaderpacks`.
2. Select it. Expected: no error screen. If Iris reports a compile error, copy the log lines
   and run `python tools/validate.py` to locate the source line.
3. Check `logs/latest.log` for `Failed`, `error`, or `Unknown` lines from Iris.

## 1. Foundation and materials (Phase 1–2)

* Debug views 1–5 on plain terrain: textures correct, normals stable, metals only on
  metal blocks.
* With a LabPBR pack: polished stone vs rough stone, gold and iron blocks (should tint
  reflections), glass, emissive blocks (lamps glow, torch sticks do not).
* Day cycle (`/time set 0, 6000, 12000, 13000, 18000, 23000`): shadows follow the sun, switch
  to the moon at night, no flashing at the switch, exposure adapts smoothly.
* Shadow acne / peter-panning on slopes and stairs at noon and at sunset; shadows do not
  swim while walking (texel snapping).
* Stained glass casts coloured light.

## 2. Sky (Phase 3)

* Sunrise/sunset colours, twilight, night sky. Stars stable while turning (no shimmer).
* Moon phases over 8 days (`/time add 24000`). Moon texture orientation: maria on the left
  half near full moon.
* Eclipse preview 1–4. Solar total: daylight drops, stars appear, corona visible.
* Natural eclipses: with default settings the first solar eclipse in the simulated calendar
  falls on day 76 (`/time set` to day 76 noon: `/time set 1830000`) — see
  `tools/tests/test_celestial.py` output.

## 3. Water (Phase 4)

* Ocean vs river vs small pond: waves calmer away from the ocean.
* Walk/swim in water: ripples follow; jump in from height: splash ring + rebound; leave the
  water: small ripple. Stand still in a boat: bobbing; drive the boat: V-wake.
* Debug views 12/13 while doing the above. Teleport (`/tp ~1000 ~ ~`): no leftover ripples.
* Underwater: fog colour, Snell's window looking up, light shafts, caustics on the floor.
* Reflections of terrain on calm water; no black reflections at screen edges.

## 4. Clouds (Phase 5)

* Clear, `/weather rain`, `/weather thunder`: coverage and towers change over ~30 s.
* Fly up through the cloud base (y ≈ 900): no flat ceiling, clouds surround the camera.
* Cloud shadows moving over terrain. Sunset light through clouds.
* Debug 10/11 while turning quickly: no long ghost trails.

## 5. Weather and atmospherics (Phase 6)

* Rain: wet darkening, puddles on flat ground, ripples, rainbow opposite a low sun.
* Thunder: lightning flashes light terrain and clouds.
* Sunrise mist in a forest; light shafts through trees and under water.
* Aurora: set Aurora Frequency to 1 and check the northern sky at night.

## 6. Dimensions (Phase 7)

* Nether: haze colour per biome, smoke structure, heat shimmer, lava glow.
* End: black hole lensing (stars bend around it), disk brighter on one side (Doppler),
  photon ring, terrain lit and shadowed from the black hole's direction. Try all three
  Black Hole Quality settings.
* End planets: phases match the black hole's side, the ring passes in front of and behind the
  gas giant, terrain hides planets. Black Hole Drift: shadows move smoothly, no popping.

## 7. Reflections and light (Phase 8)

* Polished/wet/metal surfaces reflect nearby blocks; rough ones blur.
* Coloured light: soul torches (cyan), redstone (red), lava (orange), amethyst (purple);
  check no colour or light leaks through walls.
* SSAO in corners; contact shadows under small objects.

## 8. Compatibility (Phase 9)

* Distant Horizons: no seam between vanilla and LOD terrain, fog consistent, water OK.
* Voxy: same; check Debug View 17/18 for LOD alignment.
* Each preset loads; record frame times (PERFORMANCE.md protocol).

## 8b. Expansion: versions, LOD, colour

Run on at least one row per Iris branch from COMPATIBILITY.md (e.g. 1.20.1, 1.20.2, 1.21.1,
1.21.8, 1.21.11, 26.x) and record the result in that table:

* Iris + Sodium alone; Iris + DH; Iris + Voxy (1.21.6+ only); each with a LabPBR resource pack.
* Pack loads without errors in `logs/latest.log`; no black or magenta screen in all three
  dimensions.
* LOD terrain (DH and Voxy separately) at noon, sunrise, sunset, night and in rain: no glow at
  night, no black LODs, same hue as nearby vanilla terrain (Debug View 17 to locate the seam),
  water continues past the hand-off with waves and no hard edge.
* LOD Shadows on (DH only): LOD shadows inside the shadow distance, no acne.
* Iris 1.20.2 (1.6.14): water ripples follow the player; coloured light from torches present.
* Iris < 1.10.4: water reacts when the head goes under; no boat wake (expected).
* SSGI: coloured bounce from a red wool wall onto the floor in sunlight; no ghosting when
  turning (Debug View 21); torch-lit cave stays dark where no light reaches.
* Hand light: torch, soul torch, glowstone, lantern in either hand light nearby blocks in the
  right colour, also with SSGI off.
* Colour profiles: switch all five; Custom options change the image one at a time; no clipped
  highlights on Fantasy; Natural close to the pre-expansion look.

## 9. Post (Phase 10)

* Bloom on lava/glowstone is soft, not a white haze. DOF autofocus, motion blur, vignette
  toggles work. Sharpening 0–4.

# Testing

## Automated (run before every commit)

```
python -I tools/validate.py --variants base dh voxy --profiles   # glslang, every program
python -I tools/check_options.py                                 # settings menu consistency
python -P tools/tests/test_shadow_stability.py                   # cascade grid maths
python -P tools/tests/test_sun_glare.py                          # bloom of the sun disk
python -P tools/tests/test_ripple_precision.py                   # rain-ripple coordinates
python -P tools/tests/test_wave_filter.py                        # water footprint prefilter
python -P tools/tests/test_wave_speed.py                         # wave speed independent of position
python -P tools/tests/test_water_sim_frames.py                   # ripple-sim inputs and frames
python -P tools/tests/test_water_sim_events.py                   # ripple-sim sleeping, splashes, third person
python -P tools/tests/test_water_propagation.py                  # ripple solver: speed, range, edge, stability (~3 min)
python -P tools/tests/test_cloud_weather.py                      # cloud weather map: coverage, variety, tiling, wrap
python -P tools/tests/test_cloud_density.py                      # cloud density: equalised shape, sky cover, separate clouds, storms
python -P tools/tests/test_tonemap.py                            # tone mapper and grading: contrast, hue, chroma, emitters
python -P tools/tests/test_end_lighting.py                       # End flash on terrain, shadow anchor
python -P tools/tests/test_star_twinkle.py                       # star twinkling: mean, elevation, independence, frames
python -P tools/tests/test_exposure_balance.py                   # End / Nether exposure and emission
python -P tools/tests/test_rainbow.py                            # rainbow angles from water dispersion
```

To find where an over-bright area comes from in game, use debug views 21 (direct light),
22 (ambient + block light) and 23 (emission). Each shows that contribution at the current
exposure.

`validate.py` also fails if a dimension's Voxy shader copy differs from `program/voxy/` (Voxy
compiles those files itself and cannot `#include`; they are not compiled by glslang here).

`validate.py` inlines `#include`s the way Iris does and injects Iris' built-in macros (and the DH
`dhMaterialId` attribute). It then compiles each program in `world0`, `world-1` and `world1` with
Khronos glslang, for the base, Distant Horizons and Voxy variants, at the defaults and at each
quality profile in `shaders.properties`. Last result (2026-10-26): 18 configurations, 0 failures
(265 programs per base/Voxy configuration, 283 with DH).

glslang is a reference front end, not the GPU driver. Driver-specific errors, Iris' own
preprocessing (option rewriting, custom uniforms) and link-time interface mismatches between
stages are **not** covered.

## In game

First run (2026-10-27, by the user): Minecraft 1.21.11, Iris 1.10.8, Sodium 0.8.12, Voxy 0.2.16,
RTX 5070 Ti, near-Ultra settings. The pack loaded with no shader errors in `latest.log`.
Screenshots showed:
* wave speed changing with the player's position
* no player ripples
* a black End portal
* a fade-in from black on load
* a beige veil and banding in the End
* repetitive rings
* bright cyan shorelines
* (reported) flickering shadows

All except the shadow flicker are addressed in the 2026-10-27 commits and need re-checking.

To report shadow flicker usefully: `/gamerule doDaylightCycle false`, stand still, then walk and
turn. Use debug view 9 (cascade texel checker) and note whether the checker itself moves (a
coordinate problem) or only the shadow edges shimmer (filtering or TAA).

### Water and flicker checks (2026-10-27)

* **Debug view 24 (Water Simulation).** It shows the simulated height on the water and a status
  strip: active, still moving, entry armed, splash pending, steps this frame, splash applied. Use
  it for these checks:
  * after leaving a boat, "still moving" must stay green while ripples spread;
  * a jump in must light "splash applied" once.
* **Flicker.** Stand by a torch and turn. Then switch on Static Noise (Advanced):
  * if the flicker stops, it comes from stochastic sampling (try TAA on, and AO and Indirect Sun
    off, to find which pass);
  * if it doesn't stop, check debug view 18 (Exposure) for pulsing, and view 11 (Coloured Light
    Volume).

### Water propagation, clouds and star twinkling (2026-10-27, second batch)

Model tests (`test_water_propagation.py`, `test_cloud_weather.py`, `test_star_twinkle.py`) cover
the maths. These need the game:

* **Ripples.** Hop into still water: debug view 24 should show a ring crossing ~20 blocks
  without a square edge or an echo coming back. Walk, sprint, swim and ride a boat; stop the
  boat and step out: the wake keeps spreading, no new rings appear from the idle boat, and the
  status strip's "still moving" goes red within ~25 s.
* **No false splashes.** Stand dry on a dock in third person (F5) and tilt the view so the
  camera dips under the surface: "splash applied" must stay off. Swim fully under in F5 and
  surface: no splash.
* **Clouds.** Clear weather at Coverage 0.45: some regions of open sky, some cloud groups, some
  banks; clouds should look bright, not grey. `/weather rain` then `/weather thunder`: overcast,
  then tall dark storm cells. Sunrise, sunset and moonlit nights. Fly to cloud level and above.
  Watch for a seam or jump (there should be none) and for GPU time
  (F3 or an overlay) against the previous version at the same profile.
* **Stars.** A clear night with time frozen: stars near the horizon twinkle more than those
  overhead; no star vanishes; the Milky Way glow is steady; TAA on and off; 30 and 144 FPS caps.

### Clouds, colour and End light (2026-10-27, third batch)

`tools/cloud_preview.py` renders the cloud model offline (fisheye, view, map) from the pack's own
noise textures; the model tests cover the maths. These need the game:

* **Clouds** (Coverage 0.45, clear weather, `/time set noon`): separate cumulus in groups with
  open sky between; somewhere within a few km a clear region and somewhere a bank. No smooth grey
  masses. Debug view 25 (weather map: r coverage, g type, b size), 26 (lighting: r direct,
  g ambient, b opacity), 27 (temporal: red = no history, green = sample weight). Turn quickly and
  fly: no smearing or ghost trails (27 red at the screen edges only). Different days
  (`/time add 24000`) give different overall cover. `/weather thunder`: tall cells with anvils.
  Compare GPU time with the previous commit at High and at Low.
* **Colour**: grass rich but not neon, blue sky, white clouds with grey undersides, shadows
  darker than before but with texture detail, nights no darker on average. Debug view 28
  (saturation: magenta marks colours on the gamut edge; large magenta areas would be a problem),
  29 (tone mapping without grading), 30 (bloom). Compare Tone Mapping = Meridian Filmic (flat),
  the old look.
* **End flicker**: the four fixed causes are in docs/REGRESSION_AUDIT.md. Stand still on the main
  island with time frozen for a minute (End flashes come every ~30 s): with debug view 22
  (ambient) the island may glow faintly purple during a flash but must not flash or step. Then
  walk 100 blocks in a straight line and turn on the spot near the pillars: shadow edges must
  not jump (debug view 8). If any flicker remains, isolate it one switch at a time and note which
  one stops it: TAA off; Bloom off; Automatic Exposure off; Static Noise on; Coloured Light off;
  AO and Indirect Sun off; Shadows at the lowest filter. Debug views 21 (direct, the disk light),
  22 (ambient), 23 (emission), 8 (shadows) and 18 (exposure) show which term moves.

### Still to verify

Still to verify after the 2026-10-27 fixes,
on Minecraft 1.21.11 + Fabric + Sodium + Iris:

* Iris loads the pack with no errors in `logs/latest.log`.
* Shadows stay put while walking, strafing, flying and turning, at x≈0 and at x≈±20,000 (debug
  view 9 shows the texel checker, which must not swim).
* Sun: a moderate glow, no flat glare disc; water and wet surfaces show a single sun glint.
* Night: shadows are not crushed at Vibrant / Cinematic; the Moon shows maria and highlands.
* Clouds keep their shape after 30+ minutes of play and move with the rain's lean.
* End and Nether exposure; Distant Horizons and Voxy, each **on its own**. Simultaneous use is
  not supported or claimed.
* Performance: none measured. Record the GPU, resolution, profile, scene and frame time here when
  measured. Do not estimate.

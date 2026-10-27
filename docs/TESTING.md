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
